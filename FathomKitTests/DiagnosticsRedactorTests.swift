@testable import FathomKit
import Foundation
import Testing

@Test
func diagnosticsRedactorHashesPathFieldsAndAbsoluteStrings() throws {
    let source = Data(
        """
        {"path":"/Users/alice/secret.mov","detail":"kept","nested":{"sourcePath":"relative/private","label":"public"},"items":["/Volumes/Work/file",4]}
        """.utf8
    )

    let redacted = try DiagnosticsRedactor.redactJSONLines(
        source,
        includePaths: false
    )
    let object = try #require(
        JSONSerialization.jsonObject(with: redacted) as? [String: Any]
    )
    #expect(object["path"] as? String == DiagnosticsRedactor.pathToken("/Users/alice/secret.mov"))
    #expect(object["detail"] as? String == "kept")
    let nested = try #require(object["nested"] as? [String: Any])
    #expect(nested["sourcePath"] as? String == DiagnosticsRedactor.pathToken("relative/private"))
    #expect(nested["label"] as? String == "public")
    let items = try #require(object["items"] as? [Any])
    #expect(items[0] as? String == DiagnosticsRedactor.pathToken("/Volumes/Work/file"))
}

@Test
func diagnosticsRedactorLeavesOptedInPathsByteForByte() throws {
    let source = Data("{\"path\":\"/Users/alice/file\"}\n".utf8)
    #expect(
        try DiagnosticsRedactor.redactJSONLines(source, includePaths: true)
            == source
    )
}

@Test
func diagnosticsPathTokensAreStableAndDoNotRevealThePath() {
    let first = DiagnosticsRedactor.pathToken("/Users/alice/private")
    let second = DiagnosticsRedactor.pathToken("/Users/alice/private")
    #expect(first == second)
    #expect(first.hasPrefix("path-sha256:"))
    #expect(!first.contains("alice"))
}
