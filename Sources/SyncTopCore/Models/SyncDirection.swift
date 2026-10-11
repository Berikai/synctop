import Foundation

/// Defines the synchronization direction for a folder profile.
public enum SyncDirection: String, Codable, CaseIterable, Sendable {
    /// Two-way sync: keeps both local and Google Drive in sync with conflict preservation.
    case bidirectional = "bidirectional"
    
    /// One-way backup: pushes local changes to Google Drive.
    case push = "push"
    
    /// One-way restore: pulls Google Drive changes down to the local directory.
    case pull = "pull"

    public var displayName: String {
        switch self {
        case .bidirectional:
            return "Two-Way (Bidirectional)"
        case .push:
            return "Push (Local → Cloud)"
        case .pull:
            return "Pull (Cloud → Local)"
        }
    }

    public var systemImage: String {
        switch self {
        case .bidirectional:
            return "arrow.triangle.2.circlepath"
        case .push:
            return "arrow.up.circle.fill"
        case .pull:
            return "arrow.down.circle.fill"
        }
    }
}
