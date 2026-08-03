import Darwin
import Foundation

public struct PublicIPSnapshot: Sendable, Codable, Equatable {
    public let address: String
    public let countryCode: String
    public let fetchedAt: Date

    public init(address: String, countryCode: String, fetchedAt: Date) {
        self.address = address
        self.countryCode = countryCode
        self.fetchedAt = fetchedAt
    }
}

public enum PublicIPServiceError: Error, Equatable {
    case disabled
    case invalidResponse
    case responseTooLarge
    case unexpectedStatus(Int)
}

public actor PublicIPService {
    public typealias Fetch = @Sendable (URLRequest) async throws -> (Data, Int)

    public static let endpoint = URL(
        string: "https://cloudflare.com/cdn-cgi/trace"
    )!
    public static let cacheLifetime: TimeInterval = 6 * 60 * 60
    public static let maximumResponseBytes = 16 * 1_024

    private let cacheURL: URL
    private let fetch: Fetch

    public init(cacheURL: URL, fetch: @escaping Fetch = PublicIPService.liveFetch) {
        self.cacheURL = cacheURL
        self.fetch = fetch
    }

    public func read(
        enabled: Bool,
        now: Date = Date()
    ) async -> Measurement<PublicIPSnapshot> {
        guard enabled else {
            return .notPublished(reason: "Public IP lookup is disabled")
        }
        if let cached = Self.loadCache(at: cacheURL),
           now.timeIntervalSince(cached.fetchedAt) < Self.cacheLifetime {
            return .known(cached, source: .cloudflareTracePublicAddress)
        }

        do {
            var request = URLRequest(
                url: Self.endpoint,
                cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
                timeoutInterval: 10
            )
            request.httpMethod = "GET"
            let (data, status) = try await fetch(request)
            guard status == 200 else {
                throw PublicIPServiceError.unexpectedStatus(status)
            }
            guard data.count <= Self.maximumResponseBytes else {
                throw PublicIPServiceError.responseTooLarge
            }
            let snapshot = try Self.parse(data, fetchedAt: now)
            try Self.saveCache(snapshot, at: cacheURL)
            return .known(snapshot, source: .cloudflareTracePublicAddress)
        } catch {
            return .notPublished(reason: "Public IP request failed: \(error)")
        }
    }

    public static func parse(
        _ data: Data,
        fetchedAt: Date
    ) throws -> PublicIPSnapshot {
        guard data.count <= maximumResponseBytes,
              let body = String(data: data, encoding: .utf8) else {
            throw PublicIPServiceError.invalidResponse
        }
        var fields: [String: String] = [:]
        for line in body.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            fields[String(parts[0])] = String(parts[1])
        }
        guard let address = fields["ip"], isIPAddress(address),
              let country = fields["loc"], isCountryCode(country) else {
            throw PublicIPServiceError.invalidResponse
        }
        return PublicIPSnapshot(
            address: address,
            countryCode: country,
            fetchedAt: fetchedAt
        )
    }

    private static func isIPAddress(_ value: String) -> Bool {
        var ipv4 = in_addr()
        var ipv6 = in6_addr()
        return value.withCString {
            inet_pton(AF_INET, $0, &ipv4) == 1 ||
                inet_pton(AF_INET6, $0, &ipv6) == 1
        }
    }

    private static func isCountryCode(_ value: String) -> Bool {
        value.count == 2 && value.unicodeScalars.allSatisfy {
            (65...90).contains($0.value)
        }
    }

    private static func loadCache(at url: URL) -> PublicIPSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(PublicIPSnapshot.self, from: data)
    }

    private static func saveCache(_ snapshot: PublicIPSnapshot, at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: url, options: [.atomic])
    }

    public static func liveFetch(_ request: URLRequest) async throws -> (Data, Int) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.waitsForConnectivity = false
        let session = URLSession(
            configuration: configuration,
            delegate: RedirectRefusingDelegate.shared,
            delegateQueue: nil
        )
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw PublicIPServiceError.invalidResponse
        }
        return (data, http.statusCode)
    }
}

private final class RedirectRefusingDelegate: NSObject,
    URLSessionTaskDelegate, @unchecked Sendable {
    static let shared = RedirectRefusingDelegate()

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
