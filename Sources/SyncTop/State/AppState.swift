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
    @Published public var authExpiredRemotes: Set<String> = []
    @Published public var reconnectingRemote: String? = nil
    @Published public var reconnectAuthURL: URL? = nil
    @Published public var reconnectErrorMessage: String? = nil
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
    private let authService: RcloneAuthService
    public let scheduler: SyncScheduler
    private var schedulerTask: Task<Void, Never>?
    private var reconnectCancellation: (@Sendable () -> Void)? = nil
    private var isUserCancelledProfiles: Set<UUID> = []

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
        authService: RcloneAuthService = RcloneAuthService(),
        scheduler: SyncScheduler = SyncScheduler()
    ) {
        self.store = store
        self.discovery = discovery
        self.engine = engine
        self.authService = authService
        self.scheduler = scheduler

        Task { [weak self] in
            await self?.initialize()
        }
    }

    public var isAnySyncing: Bool {
        return profiles.contains { $0.lastSyncStatus == .syncing }
    }

    public var hasFailures: Bool {
        return profiles.contains { $0.lastSyncStatus == .failed || $0.lastSyncStatus == .authRequired }
    }

    public var hasConflicts: Bool {
        return profiles.contains { $0.lastSyncStatus == .conflict }
    }

    public var isAuthExpired: Bool {
        return !authExpiredRemotes.isEmpty || profiles.contains { $0.lastSyncStatus == .authRequired }
    }

    public var primaryExpiredRemote: String? {
        if let first = authExpiredRemotes.sorted().first {
            return first
        }
        return profiles.first(where: { $0.lastSyncStatus == .authRequired })
            .map { RcloneAuthHelper.cleanRemoteName($0.remoteName) }
    }

    public func initialize(force: Bool = false) async {
        if hasInitialized && !force { return }
        hasInitialized = true
        isInitializing = true
        NotificationManager.shared.requestPermissionIfNeeded()
        await checkEnvironment()
        await loadProfiles()
        await verifyRemoteConnections()
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

    public func verifyRemoteConnections() async {
        guard isRcloneAvailable else { return }
        let remotesToCheck = Set(
            detectedRemotes.map(RcloneAuthHelper.cleanRemoteName)
            + profiles.map { RcloneAuthHelper.cleanRemoteName($0.remoteName) }
        ).filter { !$0.isEmpty }

        for remote in remotesToCheck {
            let result = await authService.checkRemoteAuth(remoteName: remote)
            switch result {
            case .valid:
                await markRemoteAuthValid(remote)
            case .authExpired:
                markRemoteAuthExpired(remote)
            case .offlineOrError:
                // Avoid marking offline networks as expired tokens
                break
            }
        }
    }

    public func markRemoteAuthExpired(_ remoteName: String) {
        let clean = RcloneAuthHelper.cleanRemoteName(remoteName)
        guard !clean.isEmpty else { return }
        authExpiredRemotes.insert(clean)
    }

    public func markRemoteAuthValid(_ remoteName: String) async {
        let clean = RcloneAuthHelper.cleanRemoteName(remoteName)
        guard !clean.isEmpty else { return }
        authExpiredRemotes.remove(clean)
        NotificationManager.shared.clearAuthNotification(for: clean)

        var didUpdate = false
        for idx in profiles.indices {
            if RcloneAuthHelper.cleanRemoteName(profiles[idx].remoteName) == clean &&
                profiles[idx].lastSyncStatus == .authRequired {
                profiles[idx].lastSyncStatus = .idle
                profiles[idx].lastSyncMessage = "Connection restored"
                didUpdate = true
            }
        }
        if didUpdate {
            await saveProfiles()
        }
    }

    public func reconnectRemote(_ remoteName: String) {
        let clean = RcloneAuthHelper.cleanRemoteName(remoteName)
        guard !clean.isEmpty, reconnectingRemote == nil else { return }

        reconnectingRemote = clean
        reconnectAuthURL = nil
        reconnectErrorMessage = nil

        let (stream, cancel) = authService.reconnect(remoteName: clean)
        reconnectCancellation = cancel

        Task {
            for await event in stream {
                switch event {
                case .authURL(let url):
                    self.reconnectAuthURL = url
                case .log:
                    break
                case .succeeded:
                    self.reconnectCancellation = nil
                    self.reconnectingRemote = nil
                    self.reconnectAuthURL = nil
                    self.reconnectErrorMessage = nil

                    let profilesToRetry = self.profiles.filter {
                        RcloneAuthHelper.cleanRemoteName($0.remoteName) == clean &&
                        ($0.lastSyncStatus == .authRequired || $0.lastSyncStatus == .failed)
                    }
                    await self.markRemoteAuthValid(clean)
                    for p in profilesToRetry {
                        self.sync(id: p.id)
                    }
                case .failed(let message):
                    self.reconnectCancellation = nil
                    self.reconnectingRemote = nil
                    self.reconnectAuthURL = nil
                    self.reconnectErrorMessage = message
                }
            }
        }
    }

    public func cancelReconnect() {
        reconnectCancellation?()
        reconnectCancellation = nil
        reconnectingRemote = nil
        reconnectAuthURL = nil
    }

    public func syncAll() {
        for profile in profiles where profile.lastSyncStatus != .syncing {
            sync(id: profile.id)
        }
    }

    public func sync(id: UUID, isDryRun: Bool = false, forceResync: Bool = false) {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        var profile = profiles[index]

        isUserCancelledProfiles.remove(id)
        profile.lastAttemptDate = Date()
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
                case .authRequired(let remoteName, let message):
                    var logs = self.activeLogs[id] ?? []
                    logs.append("🔑 AUTH EXPIRED (\(remoteName)): \(message)")
                    self.activeLogs[id] = logs
                    self.markRemoteAuthExpired(remoteName)
                    NotificationManager.shared.notifyAuthExpired(remoteName: remoteName)
                case .completed(let report):
                    SleepAssertionManager.shared.releaseAssertion()
                    let wasUserCancelled = self.isUserCancelledProfiles.remove(id) != nil
                    if let currentIndex = self.profiles.firstIndex(where: { $0.id == id }) {
                        var updated = self.profiles[currentIndex]
                        let cleanRemote = RcloneAuthHelper.cleanRemoteName(updated.remoteName)

                        if wasUserCancelled {
                            updated.lastSyncStatus = .failed
                            updated.lastSyncMessage = "Cancelled by user"
                        } else {
                            updated.lastSyncStatus = report.status
                            switch report.status {
                            case .success:
                                updated.lastSyncDate = report.endTime
                                updated.lastSyncMessage = "Sync completed successfully"
                                if updated.direction == .bidirectional {
                                    updated.isBisyncInitialized = true
                                }
                                await self.markRemoteAuthValid(cleanRemote)
                            case .conflict:
                                updated.lastSyncDate = report.endTime
                                updated.lastSyncMessage = "Conflict copy preserved"
                                await self.markRemoteAuthValid(cleanRemote)
                            case .authRequired:
                                updated.lastSyncMessage = "Authentication expired — Reconnect required"
                            case .failed:
                                updated.lastSyncMessage = "Sync failed (exit code \(report.exitCode))"
                                NotificationManager.shared.notifySyncFailed(
                                    profileId: id,
                                    profileName: updated.name,
                                    reason: updated.lastSyncMessage ?? "Sync failed"
                                )
                            case .idle, .syncing:
                                break
                            }
                        }
                        self.profiles[currentIndex] = updated
                        await self.saveProfiles()
                    }
                    try? await self.store.appendReport(report)
                    self.activeCancellations.removeValue(forKey: id)
                case .failed:
                    break
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
                case .authRequired(let remoteName, let msg):
                    self.dryRunLogs.append("🔑 AUTH EXPIRED (\(remoteName)): \(msg)")
                    self.markRemoteAuthExpired(remoteName)
                    NotificationManager.shared.notifyAuthExpired(remoteName: remoteName)
                    self.isDryRunExecuting = false
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
        isUserCancelledProfiles.insert(id)
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
                let due = self.scheduler.profilesDueForSync(
                    profiles: self.profiles,
                    blockedRemotes: self.authExpiredRemotes
                )
                for profile in due {
                    self.sync(id: profile.id)
                }
            }
        }
    }
}
