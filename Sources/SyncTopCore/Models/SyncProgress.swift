import Foundation

/// Real-time progress updates emitted during an active synchronization job.
public struct SyncProgress: Sendable, Codable {
    public var bytesTransferred: Int64
    public var totalBytes: Int64
    public var percentage: Double
    public var currentFile: String?
    public var transferSpeed: String?
    public var eta: String?
    public var filesTransferred: Int
    public var totalFiles: Int
    public var rawLog: String

    public init(
        bytesTransferred: Int64 = 0,
        totalBytes: Int64 = 0,
        percentage: Double = 0.0,
        currentFile: String? = nil,
        transferSpeed: String? = nil,
        eta: String? = nil,
        filesTransferred: Int = 0,
        totalFiles: Int = 0,
        rawLog: String = ""
    ) {
        self.bytesTransferred = bytesTransferred
        self.totalBytes = totalBytes
        self.percentage = percentage
        self.currentFile = currentFile
        self.transferSpeed = transferSpeed
        self.eta = eta
        self.filesTransferred = filesTransferred
        self.totalFiles = totalFiles
        self.rawLog = rawLog
    }

    public static let zero = SyncProgress()
}
