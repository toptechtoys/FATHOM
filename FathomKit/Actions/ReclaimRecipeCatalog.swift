import Darwin
import CryptoKit
import Foundation

public enum ReclaimRecipeRoot: String, Sendable, Codable, CaseIterable {
    case xcodeDerivedData
    case xcodeDeviceSupport
    case swiftUIPreviews
    case npmCache
    case yarnCache
    case cargoRegistry
    case goBuildCache
    case gradleCache
    case mavenRepository
    case cocoaPodsCache
    case pipCache
    case userLogs

    public func url(home: URL) -> URL {
        switch self {
        case .xcodeDerivedData:
            home.appending(path: "Library/Developer/Xcode/DerivedData")
        case .xcodeDeviceSupport:
            home.appending(path: "Library/Developer/Xcode/iOS DeviceSupport")
        case .swiftUIPreviews:
            home.appending(path: "Library/Developer/Xcode/UserData/Previews")
        case .npmCache:
            home.appending(path: ".npm/_cacache")
        case .yarnCache:
            home.appending(path: "Library/Caches/Yarn")
        case .cargoRegistry:
            home.appending(path: ".cargo/registry")
        case .goBuildCache:
            home.appending(path: "Library/Caches/go-build")
        case .gradleCache:
            home.appending(path: ".gradle/caches")
        case .mavenRepository:
            home.appending(path: ".m2/repository")
        case .cocoaPodsCache:
            home.appending(path: "Library/Caches/CocoaPods")
        case .pipCache:
            home.appending(path: "Library/Caches/pip")
        case .userLogs:
            home.appending(path: "Library/Logs")
        }
    }
}

public enum ReclaimSafetyClass: String, Sendable, Codable {
    case safe
    case requiresPerItemConfirmation
    case reportOnly
}

public struct ReclaimDetectionRecipe: Sendable, Equatable, Codable, Identifiable {
    public let identifier: String
    public let version: UInt64
    public let root: ReclaimRecipeRoot
    public let glob: String
    public let maximumMatches: UInt64
    public let regenerationCost: String
    public let safetyClass: ReclaimSafetyClass
    public let minimumAppVersion: String?

    public var id: String { identifier }

    private enum CodingKeys: String, CodingKey {
        case identifier
        case version
        case root
        case glob
        case maximumMatches
        case regenerationCost
        case safetyClass
        case minimumAppVersion
    }

    public init(
        identifier: String,
        version: UInt64,
        root: ReclaimRecipeRoot,
        glob: String,
        maximumMatches: UInt64,
        regenerationCost: String,
        safetyClass: ReclaimSafetyClass,
        minimumAppVersion: String? = nil
    ) throws {
        guard !identifier.isEmpty,
              !regenerationCost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              maximumMatches > 0,
              !glob.isEmpty,
              !glob.hasPrefix("/"),
              !glob.split(separator: "/", omittingEmptySubsequences: false)
                .contains(".."),
              glob.unicodeScalars.allSatisfy({ scalar in
                  scalar.value >= 0x20 && scalar.value != 0x7F
              }),
              minimumAppVersion.map(Self.isSemanticVersion) ?? true else {
            throw ReclaimRecipeCatalogError.invalidRecipe(identifier)
        }
        self.identifier = identifier
        self.version = version
        self.root = root
        self.glob = glob
        self.maximumMatches = maximumMatches
        self.regenerationCost = regenerationCost
        self.safetyClass = safetyClass
        self.minimumAppVersion = minimumAppVersion
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            identifier: values.decode(String.self, forKey: .identifier),
            version: values.decode(UInt64.self, forKey: .version),
            root: values.decode(ReclaimRecipeRoot.self, forKey: .root),
            glob: values.decode(String.self, forKey: .glob),
            maximumMatches: values.decode(
                UInt64.self,
                forKey: .maximumMatches
            ),
            regenerationCost: values.decode(
                String.self,
                forKey: .regenerationCost
            ),
            safetyClass: values.decode(
                ReclaimSafetyClass.self,
                forKey: .safetyClass
            ),
            minimumAppVersion: values.decodeIfPresent(
                String.self,
                forKey: .minimumAppVersion
            )
        )
    }

    private static func isSemanticVersion(_ value: String) -> Bool {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 3 && parts.allSatisfy {
            !$0.isEmpty && $0.allSatisfy(\.isNumber)
        }
    }

    public func actionRecipe(
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) throws -> ReclaimRecipe {
        let allowedRoot = root.url(home: home)
            .standardizedFileURL.resolvingSymlinksInPath().path
        return try ReclaimRecipe(
            identifier: identifier,
            version: version,
            regenerationCost: regenerationCost,
            safetyClass: safetyClass,
            allowedRootPath: allowedRoot
        )
    }
}

public enum ReclaimRecipeCatalogError: Error, Sendable, Equatable {
    case missingBundledCatalog
    case invalidBundledSignature
    case invalidRecipe(String)
    case maximumMatchesExceeded(identifier: String, maximum: UInt64)
    case escapedRoot(path: String)
    case invalidCatalogShape
}

public struct ReclaimRecipeMatch: Sendable, Equatable {
    public let recipe: ReclaimDetectionRecipe
    public let paths: [URL]
}

public struct ReclaimRecipeCatalog: Sendable {
    private static let signingPublicKey = Data(
        base64Encoded: "0ddnQvEtJJLOfed5ToO7X/g6eAfrfe75FEnPEmxH49M="
    )!
    public let recipes: [ReclaimDetectionRecipe]

    public init(recipes: [ReclaimDetectionRecipe]) throws {
        guard Set(recipes.map(\.identifier)).count == recipes.count else {
            throw ReclaimRecipeCatalogError.invalidRecipe(
                "Duplicate recipe identifier"
            )
        }
        self.recipes = recipes
    }

    public static func bundled() throws -> ReclaimRecipeCatalog {
        guard let url = Bundle.module.url(
            forResource: "reclaim-recipes",
            withExtension: "json"
        ), let signatureURL = Bundle.module.url(
            forResource: "reclaim-recipes",
            withExtension: "sig"
        ) else {
            throw ReclaimRecipeCatalogError.missingBundledCatalog
        }
        let payload = try Data(contentsOf: url)
        let signatureText = try String(contentsOf: signatureURL)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let signature = Data(base64Encoded: signatureText),
              verify(payload: payload, signature: signature) else {
            throw ReclaimRecipeCatalogError.invalidBundledSignature
        }
        return try decode(
            payload,
            currentAppVersion: Bundle.main.object(
                forInfoDictionaryKey: "CFBundleShortVersionString"
            ) as? String ?? "0.0.0"
        )
    }

    public static func decode(
        _ payload: Data,
        currentAppVersion: String
    ) throws -> ReclaimRecipeCatalog {
        guard semanticVersion(currentAppVersion) != nil,
              let objects = try JSONSerialization.jsonObject(with: payload)
                as? [[String: Any]] else {
            throw ReclaimRecipeCatalogError.invalidCatalogShape
        }
        let allowedKeys: Set<String> = [
            "identifier", "version", "root", "glob", "maximumMatches",
            "regenerationCost", "safetyClass", "minimumAppVersion"
        ]
        let requiredKeys: Set<String> = [
            "identifier", "version", "root", "glob", "maximumMatches",
            "regenerationCost", "safetyClass"
        ]
        var recipes: [ReclaimDetectionRecipe] = []
        for object in objects {
            let identifier = object["identifier"] as? String ??
                "recipe without identifier"
            if let minimum = object["minimumAppVersion"] as? String {
                guard let minimumVersion = semanticVersion(minimum) else {
                    throw ReclaimRecipeCatalogError.invalidRecipe(identifier)
                }
                if compare(
                    semanticVersion(currentAppVersion)!,
                    minimumVersion
                ) == .orderedAscending {
                    continue
                }
            }
            let keys = Set(object.keys)
            guard keys.isSubset(of: allowedKeys),
                  requiredKeys.isSubset(of: keys) else {
                throw ReclaimRecipeCatalogError.invalidRecipe(identifier)
            }
            let data = try JSONSerialization.data(
                withJSONObject: object,
                options: [.sortedKeys]
            )
            recipes.append(
                try JSONDecoder().decode(
                    ReclaimDetectionRecipe.self,
                    from: data
                )
            )
        }
        return try ReclaimRecipeCatalog(recipes: recipes)
    }

    private static func semanticVersion(_ value: String) -> [UInt64]? {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        let values = parts.compactMap { UInt64($0) }
        return values.count == 3 ? values : nil
    }

    private static func compare(
        _ left: [UInt64],
        _ right: [UInt64]
    ) -> ComparisonResult {
        for (leftPart, rightPart) in zip(left, right) {
            if leftPart < rightPart { return .orderedAscending }
            if leftPart > rightPart { return .orderedDescending }
        }
        return .orderedSame
    }

    static func verify(payload: Data, signature: Data) -> Bool {
        guard let key = try? Curve25519.Signing.PublicKey(
            rawRepresentation: signingPublicKey
        ) else { return false }
        return key.isValidSignature(signature, for: payload)
    }

    static func bundledSignatureIsValid() -> Bool {
        (try? bundled()) != nil
    }

    public func match(
        _ recipe: ReclaimDetectionRecipe,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) throws -> ReclaimRecipeMatch {
        let root = recipe.root.url(home: home)
            .standardizedFileURL.resolvingSymlinksInPath()
        guard FileManager.default.fileExists(atPath: root.path) else {
            return ReclaimRecipeMatch(recipe: recipe, paths: [])
        }
        let names = try FileManager.default.contentsOfDirectory(
            atPath: root.path
        )
        var matches: [URL] = []
        for name in names where fnmatch(recipe.glob, name, FNM_PATHNAME) == 0 {
            let candidate = root.appending(path: name)
                .standardizedFileURL.resolvingSymlinksInPath()
            guard candidate.path.hasPrefix(root.path + "/") else {
                throw ReclaimRecipeCatalogError.escapedRoot(
                    path: candidate.path
                )
            }
            matches.append(candidate)
            guard UInt64(matches.count) <= recipe.maximumMatches else {
                throw ReclaimRecipeCatalogError.maximumMatchesExceeded(
                    identifier: recipe.identifier,
                    maximum: recipe.maximumMatches
                )
            }
        }
        return ReclaimRecipeMatch(
            recipe: recipe,
            paths: matches.sorted { $0.path < $1.path }
        )
    }
}
