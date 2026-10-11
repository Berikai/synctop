import Foundation

public enum SyncStatus: String, Codable, Sendable {
    case idle = "idle"
    case syncing = "syncing"
    case success = "success"
    case failed = "failed"
    case conflict = "conflict"

    public var displayName: String {
        switch self {
        case .idle: return "Idle"
        case .syncing: return "Syncing..."
        case .success: return "Up to date"
        case .failed: return "Failed"
        case .conflict: return "Conflict Detected"
        }
    }
}

/// A configured folder pair profile defining a local directory and its Google Drive destination.
public struct SyncProfile: Identifiable, Codable, Sendable {
    public var id: UUID
    public var name: String
    public var localPath: String
    public var remoteName: String       // e.g. "google"
    public var remotePath: String       // e.g. "Backups/WorkDocs"
    public var direction: SyncDirection
    
    // Exclude Rules
    public var isDeveloperPresetEnabled: Bool
    public var isSystemPresetEnabled: Bool
    public var customExcludes: [String]
    
    // Automation & Schedule
    public var isAutoSyncEnabled: Bool
    public var scheduleIntervalMinutes: Int // e.g. 60 = hourly, 1440 = daily
    
    // Security Bookmark for macOS App Sandbox
    public var securityScopedBookmark: Data?
    
    // State & History
    public var isBisyncInitialized: Bool
    public var lastSyncDate: Date?
    public var lastSyncStatus: SyncStatus
    public var lastSyncMessage: String?
    
    public init(
        id: UUID = UUID(),
        name: String,
        localPath: String,
        remoteName: String = "google",
        remotePath: String,
        direction: SyncDirection = .bidirectional,
        isDeveloperPresetEnabled: Bool = true,
        isSystemPresetEnabled: Bool = true,
        customExcludes: [String] = [],
        isAutoSyncEnabled: Bool = false,
        scheduleIntervalMinutes: Int = 60,
        securityScopedBookmark: Data? = nil,
        isBisyncInitialized: Bool = false,
        lastSyncDate: Date? = nil,
        lastSyncStatus: SyncStatus = .idle,
        lastSyncMessage: String? = nil
    ) {
        self.id = id
        self.name = name
        self.localPath = localPath
        self.remoteName = remoteName
        self.remotePath = remotePath
        self.direction = direction
        self.isDeveloperPresetEnabled = isDeveloperPresetEnabled
        self.isSystemPresetEnabled = isSystemPresetEnabled
        self.customExcludes = customExcludes
        self.isAutoSyncEnabled = isAutoSyncEnabled
        self.scheduleIntervalMinutes = scheduleIntervalMinutes
        self.securityScopedBookmark = securityScopedBookmark
        self.isBisyncInitialized = isBisyncInitialized
        self.lastSyncDate = lastSyncDate
        self.lastSyncStatus = lastSyncStatus
        self.lastSyncMessage = lastSyncMessage
    }

    /// Full remote target specification (e.g. "google:Backups/WorkDocs")
    public var fullRemotePath: String {
        let cleanedRemote = remoteName.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
        let cleanedPath = remotePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return "\(cleanedRemote):\(cleanedPath)"
    }
}
