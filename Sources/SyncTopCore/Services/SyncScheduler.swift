import Foundation

/// Coordinates periodic background sync checks for profiles with active schedules.
public final class SyncScheduler: Sendable {
    public init() {}

    /// Determines which profiles are due for execution based on their schedule interval.
    public func profilesDueForSync(profiles: [SyncProfile], now: Date = Date()) -> [SyncProfile] {
        return profiles.filter { profile in
            guard profile.isAutoSyncEnabled else { return false }
            guard profile.lastSyncStatus != .syncing else { return false }

            let intervalSeconds = Double(max(1, profile.scheduleIntervalMinutes) * 60)
            guard let lastSync = profile.lastSyncDate else {
                // Never synced before, trigger immediately
                return true
            }

            return now.timeIntervalSince(lastSync) >= intervalSeconds
        }
    }
}
