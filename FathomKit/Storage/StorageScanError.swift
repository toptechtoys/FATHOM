import Foundation

public struct StorageScanIssue: Error, Sendable, Equatable {
    public let path: String
    public let errorNumber: Int32

    public init(path: String, errorNumber: Int32) {
        self.path = path
        self.errorNumber = errorNumber
    }
}

public enum StorageScanError: Error, Sendable, Equatable {
    case cannotStart(path: String, errorNumber: Int32)
}
