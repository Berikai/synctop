import Foundation
import SwiftUI
import Combine
import SyncTopCore

@MainActor
public final class AppState: ObservableObject {
    @Published public var profiles: [SyncProfile] = []
    @Published public var activeProgress: [UUID: SyncProgress] = [:]
    @Published public var activeLogs: [UUID: [String]] = [:]
    public var activeCancellations: [UUID: @Sendable () -> Void] = [:]
    
    @Published public var detectedRemotes: [String] = []
    @Published public var rcloneVersion: String = ""
    @Published public var isRcloneAvailable: Bool = false
    @Published public var rcloneErrorMessage: String?
    
    @Published public var isInitializing: Bool = true
    @Published public var isLaunchAtLoginEnabled: Bool = LaunchAtLoginManager.shared.isEnabled
    private var hasInitialized: Bool = false

    // UI presentation states
    @Published public var isEditorPresented: Bool = false
    @Published public var editingProfile: SyncProfile? = nil
    
    @Published public var isDryRunPresented: Bool = false
    @Published public var dryRunProfile: SyncProfile? = nil
    @Published public var dryRunLogs: [String] = []
    @Published public var isDryRunExecuting: Bool = false
    
    @Published public var isRemoteBrowserPresented: Bool = false
    @Published public var isLogConsolePresented: Bool = false
    @Published public var selectedLogProfileId: UUID? = nil

    private let store: ProfileStore
    private let discovery: RcloneDiscovery
    private let engine: RcloneEngine
    public let scheduler: SyncScheduler
    private var schedulerTask: Task<Void, Never>?

    public func toggleLaunchAtLogin() {
        let target = !isLaunchAtLoginEnabled
        do {
            try LaunchAtLoginManager.shared.setEnabled(target)
            self.isLaunchAtLoginEnabled = LaunchAtLoginManager.shared.isEnabled
        } catch {
            print("Failed to toggle Launch at Login: \(error)")
        }
    }

    public init(
        store: ProfileStore = ProfileStore(),
        discovery: RcloneDiscovery = RcloneDiscovery(),
        engine: RcloneEngine = RcloneEngine(),
        scheduler: SyncScheduler = SyncScheduler()
    ) {
        self.store = store
        self.discovery = discovery
        self.engine = engine
        self.scheduler = scheduler

        Task { [weak self] in
            await self?.initialize()
        }
    }

    public var isAnySyncing: Bool {
        return profiles.contains { $0.lastSyncStatus == .syncing }
    }

    public func initialize(force: Bool = false) async {
        if hasInitialized && !force { return }
        hasInitialized = true
        isInitializing = true
        await checkEnvironment()
        await loadProfiles()
        startScheduler()
        isInitializing = false
    }

    public func checkEnvironment() async {
        do {
            let info = try await discovery.discover()
            self.rcloneVersion = info.version
            self.detectedRemotes = info.remotes
            self.isRcloneAvailable = true
            self.rcloneErrorMessage = nil
        } catch {
            self.isRcloneAvailable = false
            self.rcloneErrorMessage = error.localizedDescription
        }
    }

    public func loadProfiles() async {
        do {
            let loaded = try await store.loadProfiles()
            self.profiles = loaded
        } catch {
            print("Failed to load profiles: \(error)")
        }
    }

    public func saveProfiles() async {
        do {
            try await store.saveProfiles(self.profiles)
        } catch {
            print("Failed to save profiles: \(error)")
        }
    }

    public func saveProfile(_ profile: SyncProfile) async {
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
        } else {
            profiles.append(profile)
        }
        await saveProfiles()
    }

    public func deleteProfile(id: UUID) async {
        cancelSync(id: id)
        profiles.removeAll { $0.id == id }
        activeProgress.removeValue(forKey: id)
        activeLogs.removeValue(forKey: id)
        await saveProfiles()
    }

    public func toggleDeveloperPreset(id: UUID) async {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles[index].isDeveloperPresetEnabled.toggle()
        await saveProfiles()
    }

    public func toggleSystemPreset(id: UUID) async {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles[index].isSystemPresetEnabled.toggle()
        await saveProfiles()
    }

    public func updateSchedule(id: UUID, isEnabled: Bool, intervalMinutes: Int? = nil) async {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        profiles[index].isAutoSyncEnabled = isEnabled
        if let intervalMinutes {
            profiles[index].scheduleIntervalMinutes = intervalMinutes
        }
        await saveProfiles()
    }

    // MARK: - Synchronization Execution

    public func syncAll() {
        for profile in profiles where profile.lastSyncStatus != .syncing {
            sync(id: profile.id)
        }
    }

    public func sync(id: UUID, isDryRun: Bool = false, forceResync: Bool = false) {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        var profile = profiles[index]

        profile.lastSyncStatus = .syncing
        profile.lastSyncMessage = "Starting sync..."
        profiles[index] = profile

        activeProgress[id] = .zero
        activeLogs[id] = []

        SleepAssertionManager.shared.retainAssertion(reason: "SyncTop syncing '\(profile.name)'")

        let (stream, cancel) = engine.execute(
            profile: profile,
            customBinaryPath: nil,
            isDryRun: isDryRun,
            forceResync: forceResync
        )
        activeCancellations[id] = cancel

        Task {
            for await event in stream {
                switch event {
                case .started:
                    break
                case .progress(let progress):
                    self.activeProgress[id] = progress
                case .log(let logLine):
                    var logs = self.activeLogs[id] ?? []
                    logs.append(logLine)
                    if logs.count > 200 {
                        logs = Array(logs.suffix(200))
                    }
                    self.activeLogs[id] = logs
                case .conflictDetected(let conflictLine):
                    var logs = self.activeLogs[id] ?? []
                    logs.append("⚠️ CONFLICT: \(conflictLine)")
                    self.activeLogs[id] = logs
                case .completed(let report):
                    SleepAssertionManager.shared.releaseAssertion()
                    if let currentIndex = self.profiles.firstIndex(where: { $0.id == id }) {
                        var updated = self.profiles[currentIndex]
                        updated.lastSyncDate = report.endTime
                        updated.lastSyncStatus = report.status
                        updated.lastSyncMessage = report.status == .success ? "Sync completed successfully" : "Finished with status: \(report.status.displayName)"
                        if updated.direction == .bidirectional && report.status == .success {
                            updated.isBisyncInitialized = true
                        }
                        self.profiles[currentIndex] = updated
                        await self.saveProfiles()
                    }
                    try? await self.store.appendReport(report)
                    self.activeCancellations.removeValue(forKey: id)
                case .failed(let error):
                    SleepAssertionManager.shared.releaseAssertion()
                    if let currentIndex = self.profiles.firstIndex(where: { $0.id == id }) {
                        var updated = self.profiles[currentIndex]
                        updated.lastSyncStatus = .failed
                        updated.lastSyncMessage = error
                        self.profiles[currentIndex] = updated
                        await self.saveProfiles()
                    }
                    self.activeCancellations.removeValue(forKey: id)
                }
            }
        }
    }

    public func runDryRun(for profile: SyncProfile) {
        self.dryRunProfile = profile
        self.dryRunLogs = []
        self.isDryRunExecuting = true
        self.isDryRunPresented = true

        let (stream, _) = engine.execute(
            profile: profile,
            customBinaryPath: nil,
            isDryRun: true,
            forceResync: false
        )

        Task {
            for await event in stream {
                switch event {
                case .log(let line):
                    self.dryRunLogs.append(line)
                case .conflictDetected(let line):
                    self.dryRunLogs.append("⚠️ CONFLICT: \(line)")
                case .completed:
                    self.isDryRunExecuting = false
                case .failed(let err):
                    self.dryRunLogs.append("❌ ERROR: \(err)")
                    self.isDryRunExecuting = false
                default:
                    break
                }
            }
        }
    }

    public func cancelSync(id: UUID) {
        if let cancel = activeCancellations[id] {
            cancel()
            activeCancellations.removeValue(forKey: id)
            SleepAssertionManager.shared.releaseAssertion()
        }
        if let index = profiles.firstIndex(where: { $0.id == id }), profiles[index].lastSyncStatus == .syncing {
            profiles[index].lastSyncStatus = .failed
            profiles[index].lastSyncMessage = "Cancelled by user"
        }
    }

    // MARK: - Scheduler Loop

    private func startScheduler() {
        schedulerTask?.cancel()
        schedulerTask = Task { [weak self] in
            while !Task.isCancelled {
                // Sleep 30 seconds between checks
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard let self else { break }
                let due = self.scheduler.profilesDueForSync(profiles: self.profiles)
                for profile in due {
                    self.sync(id: profile.id)
                }
            }
        }
    }
}
