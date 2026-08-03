import CryptoKit
import Darwin
import Foundation

public struct IOReportChannelMapEntry: Sendable, Equatable, Codable {
    public let group: String
    public let subgroup: String
    public let channel: String
    public let friendlyName: String

    public init(
        group: String,
        subgroup: String,
        channel: String,
        friendlyName: String
    ) {
        self.group = group
        self.subgroup = subgroup
        self.channel = channel
        self.friendlyName = friendlyName
    }
}

public struct IOReportChannelMap: Sendable, Equatable, Codable {
    public let version: UInt64
    public let supportedModels: [String]
    public let minimumOSBuild: String
    public let maximumOSBuild: String
    public let channels: [IOReportChannelMapEntry]

    public init(
        version: UInt64,
        supportedModels: [String],
        minimumOSBuild: String,
        maximumOSBuild: String,
        channels: [IOReportChannelMapEntry]
    ) {
        self.version = version
        self.supportedModels = supportedModels
        self.minimumOSBuild = minimumOSBuild
        self.maximumOSBuild = maximumOSBuild
        self.channels = channels
    }

    public func friendlyName(
        group: String,
        subgroup: String,
        channel: String
    ) -> String? {
        channels.first {
            $0.group == group &&
                $0.subgroup == subgroup &&
                $0.channel == channel
        }?.friendlyName
    }
}

public struct IOReportChannelMapLoader: Sendable {
    private static let publicKey = Data(
        base64Encoded: "HyWP1MSy8gaRhkKHcpL/HPIXVxOK2GhlHL3lSVG/ACY="
    )!

    public init() {}

    public func loadBundled() -> Measurement<IOReportChannelMap> {
        guard let payloadURL = Bundle.module.url(
            forResource: "channel-map-v1",
            withExtension: "json"
        ), let signatureURL = Bundle.module.url(
            forResource: "channel-map-v1",
            withExtension: "sig"
        ) else {
            return .notPublished(reason: "The bundled channel map is absent")
        }
        do {
            let payload = try Data(contentsOf: payloadURL)
            let signatureText = try String(contentsOf: signatureURL)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let signature = Data(base64Encoded: signatureText),
                  Self.verify(payload: payload, signature: signature) else {
                return .notPublished(
                    reason: "The bundled channel map signature is invalid"
                )
            }
            let map = try JSONDecoder().decode(
                IOReportChannelMap.self,
                from: payload
            )
            let model = Self.sysctlString("hw.model")
            let build = Self.sysctlString("kern.osversion")
            guard let model, map.supportedModels.contains(model) else {
                return .notPublished(
                    reason: "No signed channel map supports model \(model ?? "not published")"
                )
            }
            guard let build,
                  (map.minimumOSBuild.isEmpty || build >= map.minimumOSBuild),
                  (map.maximumOSBuild.isEmpty || build <= map.maximumOSBuild)
            else {
                return .notPublished(
                    reason: "The signed map does not cover this macOS build"
                )
            }
            return .known(map, source: .signedBundledChannelMap)
        } catch {
            return .notPublished(
                reason: "The bundled channel map is unreadable: \(error)"
            )
        }
    }

    static func verify(payload: Data, signature: Data) -> Bool {
        guard let key = try? Curve25519.Signing.PublicKey(
            rawRepresentation: publicKey
        ) else { return false }
        return key.isValidSignature(signature, for: payload)
    }

    static func bundledSignatureIsValid() -> Bool {
        guard let payloadURL = Bundle.module.url(
            forResource: "channel-map-v1",
            withExtension: "json"
        ), let signatureURL = Bundle.module.url(
            forResource: "channel-map-v1",
            withExtension: "sig"
        ), let payload = try? Data(contentsOf: payloadURL),
           let text = try? String(contentsOf: signatureURL),
           let signature = Data(
               base64Encoded: text.trimmingCharacters(
                   in: .whitespacesAndNewlines
               )
           ) else { return false }
        return verify(payload: payload, signature: signature)
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else {
            return nil
        }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &bytes, &size, nil, 0) == 0 else {
            return nil
        }
        let utf8 = bytes.prefix { $0 != 0 }.map {
            UInt8(bitPattern: $0)
        }
        return String(decoding: utf8, as: UTF8.self)
    }
}
