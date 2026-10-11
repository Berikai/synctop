import Foundation

/// Execution outcome report for a completed sync job.
public struct SyncReport: Identifiable, Codable, Sendable {
    public var id: UUID
    public var profileId: UUID
    public var startTime: Date
    public var endTime: Date
    public var status: SyncStatus
    public var exitCode: Int32
    public var transferredFilesCount: Int
    public var deletedFilesCount: Int
    public var conflictFiles: [String]
    public var logSummary: String

    public init(
        id: UUID = UUID(),
        profileId: UUID,
        startTime: Date,
        endTime: Date,
        status: SyncStatus,
        exitCode: Int32,
        transferredFilesCount: Int = 0,
        deletedFilesCount: Int = 0,
        conflictFiles: [String] = [],
        logSummary: String = ""
    ) {
        self.id = id
        self.profileId = profileId
        self.startTime = startTime
        self.endTime = endTime
        self.status = status
        self.exitCode = exitCode
        self.transferredFilesCount = transferredFilesCount
        self.deletedFilesCount = deletedFilesCount
        self.conflictFiles = conflictFiles
        self.logSummary = logSummary
    }

    public var durationString: String {
        let seconds = Int(endTime.timeIntervalSince(startTime))
        if seconds < 60 {
            return "\(seconds)s"
        } else {
            let mins = seconds / 60
            let remSecs = seconds % 60
            return "\(mins)m \(remSecs)s"
        }
    }
}
