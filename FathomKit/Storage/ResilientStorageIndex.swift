import Darwin
import Foundation

public struct StorageIndexPersistenceConfiguration: Sendable, Equatable {
    public let primaryURL: URL
    public let alternateURL: URL?
    public let initialReservationBytes: UInt64

    public init(
        primaryURL: URL,
        alternateURL: URL? = nil,
        initialReservationBytes: UInt64 = 536_870_912
    ) {
        self.primaryURL = primaryURL
        self.alternateURL = alternateURL
        self.initialReservationBytes = initialReservationBytes
    }
}

public enum StorageIndexReservationOutcome: Sendable, Equatable {
    case reserved(url: URL, bytes: UInt64)
    case notReserved(reason: String)
}

public enum ResilientStorageIndexWriteOutcome: Sendable, Equatable {
    case persisted(scanID: Int64, indexURL: URL)
    case memoryOnly(primaryFailure: String, alternateFailure: String?)
}

/// Owns the index-space reservation and the primary/alternate write policy.
///
/// The reservation is a F_PREALLOCATE-backed sibling file. It is truncated,
/// not removed, immediately before the index transaction so its blocks become
/// the budget SQLite can consume. A completed in-memory scan remains the
/// caller's authority if both locations fail.
public actor ResilientStorageIndex {
    public let configuration: StorageIndexPersistenceConfiguration

    private let primaryAdditionalPagesForTesting: Int32?

    public init(configuration: StorageIndexPersistenceConfiguration) {
        self.configuration = configuration
        primaryAdditionalPagesForTesting = nil
    }

    init(
        configuration: StorageIndexPersistenceConfiguration,
        primaryAdditionalPagesForTesting: Int32?
    ) {
        self.configuration = configuration
        self.primaryAdditionalPagesForTesting =
            primaryAdditionalPagesForTesting
    }

    public nonisolated func reserveInitialBudget()
        -> StorageIndexReservationOutcome
    {
        guard configuration.initialReservationBytes > 0 else {
            return .reserved(
                url: reservationURL,
                bytes: 0
            )
        }

        do {
            try FileManager.default.createDirectory(
                at: reservationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let descriptor = open(
                reservationURL.path,
                O_RDWR | O_CREAT | O_CLOEXEC,
                S_IRUSR | S_IWUSR
            )
            guard descriptor >= 0 else {
                return .notReserved(
                    reason: "Index budget reservation failed with errno \(errno)"
                )
            }
            defer { close(descriptor) }

            guard configuration.initialReservationBytes <= UInt64(Int64.max)
            else {
                return .notReserved(
                    reason: "The configured index budget is too large"
                )
            }
            var allocation = fstore_t(
                fst_flags: UInt32(F_ALLOCATEALL),
                fst_posmode: F_PEOFPOSMODE,
                fst_offset: 0,
                fst_length: Int64(configuration.initialReservationBytes),
                fst_bytesalloc: 0
            )
            if fcntl(descriptor, F_PREALLOCATE, &allocation) != 0 {
                return .notReserved(
                    reason: "macOS could not reserve the index budget (errno \(errno))"
                )
            }
            if ftruncate(
                descriptor,
                off_t(configuration.initialReservationBytes)
            ) != 0 {
                return .notReserved(
                    reason: "macOS could not size the index reservation (errno \(errno))"
                )
            }
            return .reserved(
                url: reservationURL,
                bytes: configuration.initialReservationBytes
            )
        } catch {
            return .notReserved(
                reason: "The index reservation directory is unavailable: \(error)"
            )
        }
    }

    public func store(
        result: StorageEngineResult,
        accounting: StorageAccountingSnapshot,
        startedAt: Date = Date()
    ) async -> ResilientStorageIndexWriteOutcome {
        let releaseFailure = releaseReservation()
        if let releaseFailure {
            return await storeAtAlternateOrRemainInMemory(
                result: result,
                accounting: accounting,
                startedAt: startedAt,
                primaryFailure: releaseFailure
            )
        }

        do {
            let index = try StorageIndex(
                url: configuration.primaryURL,
                maximumAdditionalPagesForTesting:
                    primaryAdditionalPagesForTesting
            )
            let outcome: StorageIndexWriteOutcome
            do {
                outcome = try await index.store(
                    result: result,
                    accounting: accounting,
                    startedAt: startedAt
                )
            } catch {
                await index.close()
                throw error
            }
            await index.close()
            switch outcome {
            case let .persisted(scanID):
                return .persisted(
                    scanID: scanID,
                    indexURL: configuration.primaryURL
                )
            case .memoryOnly:
                return await storeAtAlternateOrRemainInMemory(
                    result: result,
                    accounting: accounting,
                    startedAt: startedAt,
                    primaryFailure: "The primary index volume is full"
                )
            }
        } catch {
            return await storeAtAlternateOrRemainInMemory(
                result: result,
                accounting: accounting,
                startedAt: startedAt,
                primaryFailure: String(describing: error)
            )
        }
    }

    /// Releases the preallocated budget immediately before a staged scan starts
    /// writing. A non-nil value is an exact operational failure, not a storage
    /// measurement.
    public nonisolated func releaseInitialBudgetForStagedScan() -> String? {
        releaseReservation()
    }

    private nonisolated var reservationURL: URL {
        configuration.primaryURL.appendingPathExtension("reserve")
    }

    private nonisolated func releaseReservation() -> String? {
        let descriptor = open(
            reservationURL.path,
            O_RDWR | O_CLOEXEC
        )
        if descriptor < 0 {
            if errno == ENOENT {
                return nil
            }
            return "The index reservation could not be opened (errno \(errno))"
        }
        defer { close(descriptor) }
        guard ftruncate(descriptor, 0) == 0 else {
            return "The index reservation could not be released (errno \(errno))"
        }
        return nil
    }

    private func storeAtAlternateOrRemainInMemory(
        result: StorageEngineResult,
        accounting: StorageAccountingSnapshot,
        startedAt: Date,
        primaryFailure: String
    ) async -> ResilientStorageIndexWriteOutcome {
        guard let alternateURL = configuration.alternateURL else {
            return .memoryOnly(
                primaryFailure: primaryFailure,
                alternateFailure: nil
            )
        }

        do {
            let alternate = try StorageIndex(url: alternateURL)
            let outcome: StorageIndexWriteOutcome
            do {
                outcome = try await alternate.store(
                    result: result,
                    accounting: accounting,
                    startedAt: startedAt
                )
            } catch {
                await alternate.close()
                throw error
            }
            await alternate.close()
            switch outcome {
            case let .persisted(scanID):
                return .persisted(
                    scanID: scanID,
                    indexURL: alternateURL
                )
            case .memoryOnly:
                return .memoryOnly(
                    primaryFailure: primaryFailure,
                    alternateFailure: "The alternate index volume is full"
                )
            }
        } catch {
            return .memoryOnly(
                primaryFailure: primaryFailure,
                alternateFailure: String(describing: error)
            )
        }
    }
}
