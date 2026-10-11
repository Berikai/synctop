import Foundation

public enum ScheduleInterval: Int, CaseIterable, Identifiable, Sendable {
    case fiveMinutes = 5
    case fifteenMinutes = 15
    case thirtyMinutes = 30
    case oneHour = 60
    case fourHours = 240
    case twelveHours = 720
    case daily = 1440
    case weekly = 10080

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .fiveMinutes: return "Every 5 minutes"
        case .fifteenMinutes: return "Every 15 minutes"
        case .thirtyMinutes: return "Every 30 minutes"
        case .oneHour: return "Every 1 hour"
        case .fourHours: return "Every 4 hours"
        case .twelveHours: return "Every 12 hours"
        case .daily: return "Daily (24 hours)"
        case .weekly: return "Weekly (7 days)"
        }
    }

    public var shortBadge: String {
        switch self {
        case .fiveMinutes: return "5m"
        case .fifteenMinutes: return "15m"
        case .thirtyMinutes: return "30m"
        case .oneHour: return "1h"
        case .fourHours: return "4h"
        case .twelveHours: return "12h"
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        }
    }

    public static func nearestBadge(for minutes: Int) -> String {
        if let exact = ScheduleInterval(rawValue: minutes) {
            return exact.shortBadge
        }
        if minutes >= 1440 {
            let days = minutes / 1440
            return "\(days)d"
        }
        if minutes >= 60 {
            let hours = minutes / 60
            return "\(hours)h"
        }
        return "\(minutes)m"
    }
}

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

    /// Computes the estimated next execution date for a profile.
    public func nextSyncDate(for profile: SyncProfile, now: Date = Date()) -> Date? {
        guard profile.isAutoSyncEnabled else { return nil }
        guard let lastSync = profile.lastSyncDate else { return now }
        let intervalSeconds = Double(max(1, profile.scheduleIntervalMinutes) * 60)
        return lastSync.addingTimeInterval(intervalSeconds)
    }

    /// Formats a user-friendly string describing when the next auto-sync is scheduled.
    public func formatNextSyncCountdown(for profile: SyncProfile, now: Date = Date()) -> String? {
        guard let nextDate = nextSyncDate(for: profile, now: now) else { return nil }
        let diff = nextDate.timeIntervalSince(now)
        if diff <= 0 {
            return "Due now"
        }
        let minutes = Int(ceil(diff / 60.0))
        if minutes < 60 {
            return "in \(minutes)m"
        }
        let hours = minutes / 60
        let remMinutes = minutes % 60
        if hours < 24 {
            return remMinutes > 0 ? "in \(hours)h \(remMinutes)m" : "in \(hours)h"
        }
        let days = hours / 24
        return "in \(days)d"
    }
}
