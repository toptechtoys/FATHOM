import CryptoKit
import Foundation

public enum DiagnosticsRedactor {
    public static func redactJSONLines(
        _ data: Data,
        includePaths: Bool
    ) throws -> Data {
        guard !includePaths else { return data }
        var output = Data()
        for line in data.split(separator: 0x0A, omittingEmptySubsequences: true) {
            let object = try JSONSerialization.jsonObject(with: Data(line))
            let redacted = redact(object, key: nil)
            output.append(try JSONSerialization.data(withJSONObject: redacted, options: [.sortedKeys]))
            output.append(0x0A)
        }
        return output
    }

    public static func pathToken(_ path: String) -> String {
        let digest = SHA256.hash(data: Data(path.utf8))
        return "path-sha256:" + digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func redact(_ value: Any, key: String?) -> Any {
        if let dictionary = value as? [String: Any] {
            var redacted: [String: Any] = [:]
            redacted.reserveCapacity(dictionary.count)
            for (childKey, child) in dictionary {
                redacted[childKey] = redact(child, key: childKey)
            }
            return redacted
        }
        if let array = value as? [Any] {
            return array.map { redact($0, key: key) }
        }
        guard let string = value as? String else { return value }
        let keyNamesPath = key?.lowercased().contains("path") == true
        if keyNamesPath || string.hasPrefix("/") {
            return pathToken(string)
        }
        return string
    }
}
