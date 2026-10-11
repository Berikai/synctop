import SwiftUI
import AppKit
import SyncTopCore

public struct ProfileCardView: View {
    @ObservedObject var state: AppState
    let profile: SyncProfile
    let onEdit: () -> Void
    let onShowLogs: () -> Void

    public init(
        state: AppState,
        profile: SyncProfile,
        onEdit: @escaping () -> Void,
        onShowLogs: @escaping () -> Void
    ) {
        self.state = state
        self.profile = profile
        self.onEdit = onEdit
        self.onShowLogs = onShowLogs
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header: Name & Direction
            HStack {
                Text(profile.name)
                    .font(.headline)
                    .fontWeight(.semibold)

                Spacer()

                directionBadge
            }

            // Path rows
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "folder.fill")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    Text(profile.localPath)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button {
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: profile.localPath)
                    } label: {
                        Image(systemName: "arrow.up.forward.square")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .help("Reveal in Finder")
                }

                HStack(spacing: 6) {
                    Image(systemName: "cloud.fill")
                        .foregroundColor(.accentColor)
                        .font(.caption)
                    Text(profile.fullRemotePath)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .padding(8)
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(6)

            // Tags & Status row
            HStack {
                statusBadge

                Spacer()

                // Exclude preset toggles
                HStack(spacing: 6) {
                    toggleTagView(
                        title: "Dev",
                        icon: profile.isDeveloperPresetEnabled ? "hammer.fill" : "hammer",
                        isEnabled: profile.isDeveloperPresetEnabled,
                        tooltip: profile.isDeveloperPresetEnabled
                            ? "Dev preset: ACTIVE (Ignoring node_modules, .git, .venv, target, etc.)\nClick to disable"
                            : "Dev preset: OFF (Developer build files will be synced)\nClick to enable ignore"
                    ) {
                        Task { await state.toggleDeveloperPreset(id: profile.id) }
                    }

                    toggleTagView(
                        title: "macOS",
                        icon: "apple.logo",
                        isEnabled: profile.isSystemPresetEnabled,
                        tooltip: profile.isSystemPresetEnabled
                            ? "macOS preset: ACTIVE (Ignoring .DS_Store, .Trash, Spotlight, etc.)\nClick to disable"
                            : "macOS preset: OFF (System junk files will be synced)\nClick to enable ignore"
                    ) {
                        Task { await state.toggleSystemPreset(id: profile.id) }
                    }

                    scheduleDropdownMenu
                }
            }

            // Progress bars if currently syncing
            if profile.lastSyncStatus == .syncing, let progress = state.activeProgress[profile.id] {
                VStack(alignment: .leading, spacing: 6) {
                    // Total Progress Bar
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("Total Progress")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.primary)
                            Spacer()
                            if progress.totalBytes > 0 {
                                Text("\(formatBytes(progress.bytesTransferred)) of \(formatBytes(progress.totalBytes)) • \(Int(progress.percentage))%")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            } else if progress.totalFiles > 0 {
                                Text("\(progress.filesTransferred)/\(progress.totalFiles) files • \(Int(progress.percentage))%")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            } else {
                                Text("\(Int(progress.percentage))%")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        ProgressView(value: progress.percentage, total: 100)
                            .tint(.accentColor)
                    }

                    // Current File Progress Bar (if active file exists)
                    if let file = progress.currentFile {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Label(file, systemImage: "doc.fill")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                                if progress.currentFileTotalBytes > 0 {
                                    Text("\(formatBytes(progress.currentFileBytes)) / \(formatBytes(progress.currentFileTotalBytes)) (\(Int(progress.currentFilePercentage))%)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                } else {
                                    Text("\(Int(progress.currentFilePercentage))%")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            ProgressView(value: progress.currentFilePercentage, total: 100)
                                .tint(.green)
                        }
                    }

                    // Bottom stats (speed, files count)
                    HStack {
                        if let speed = progress.transferSpeed {
                            Label(speed, systemImage: "bolt.fill")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        if progress.totalFiles > 0 {
                            Text("• \(progress.filesTransferred)/\(progress.totalFiles) files transferred")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                }
                .padding(.vertical, 2)
            }

            Divider()

            // Actions row
            HStack {
                if profile.lastSyncStatus == .syncing {
                    Button(role: .destructive) {
                        state.cancelSync(id: profile.id)
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .controlSize(.small)
                } else {
                    Button {
                        state.sync(id: profile.id)
                    } label: {
                        Label("Sync Now", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }

                Button {
                    state.runDryRun(for: profile)
                } label: {
                    Label("Dry Run", systemImage: "magnifyingglass")
                }
                .controlSize(.small)
                .disabled(profile.lastSyncStatus == .syncing)

                Button {
                    onShowLogs()
                } label: {
                    Label("Logs", systemImage: "text.alignleft")
                }
                .controlSize(.small)

                Spacer()

                Button {
                    onEdit()
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.plain)
                .help("Edit Profile")

                Button {
                    Task { await state.deleteProfile(id: profile.id) }
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
                .help("Delete Profile")
            }
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        )
    }

    private var directionBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: profile.direction.systemImage)
            Text(profile.direction.displayName)
                .font(.caption)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color.accentColor.opacity(0.12))
        .foregroundColor(.accentColor)
        .cornerRadius(6)
    }

    private var statusBadge: some View {
        HStack(spacing: 4) {
            switch profile.lastSyncStatus {
            case .idle:
                Image(systemName: "circle")
                    .foregroundColor(.secondary)
                Text(profile.lastSyncDate != nil ? "Last synced \(profile.lastSyncDate!.formatted(.relative(presentation: .named)))" : "Ready to sync")
                    .font(.caption)
                    .foregroundColor(.secondary)
            case .syncing:
                ProgressView()
                    .controlSize(.mini)
                Text("Syncing...")
                    .font(.caption)
                    .foregroundColor(.accentColor)
            case .success:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Up to date (\(profile.lastSyncDate?.formatted(date: .omitted, time: .shortened) ?? ""))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            case .conflict:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text("Conflict copy preserved")
                    .font(.caption)
                    .foregroundColor(.orange)
            case .failed:
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                Text(profile.lastSyncMessage ?? "Sync failed")
                    .font(.caption)
                    .foregroundColor(.red)
            }

            if profile.lastSyncStatus != .syncing && profile.isAutoSyncEnabled,
               let countdown = state.scheduler.formatNextSyncCountdown(for: profile) {
                Text("• Next: \(countdown)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var scheduleDropdownMenu: some View {
        Menu {
            Section("Automatic Sync Interval") {
                ForEach(ScheduleInterval.allCases) { interval in
                    Button {
                        Task {
                            await state.updateSchedule(id: profile.id, isEnabled: true, intervalMinutes: interval.rawValue)
                        }
                    } label: {
                        if profile.isAutoSyncEnabled && profile.scheduleIntervalMinutes == interval.rawValue {
                            Label(interval.title, systemImage: "checkmark")
                        } else {
                            Text(interval.title)
                        }
                    }
                }
            }

            Divider()

            Button(role: .destructive) {
                Task {
                    await state.updateSchedule(id: profile.id, isEnabled: false)
                }
            } label: {
                if !profile.isAutoSyncEnabled {
                    Label("Off (Manual Only)", systemImage: "checkmark")
                } else {
                    Text("Turn Off Auto-Sync")
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: profile.isAutoSyncEnabled ? "clock.fill" : "clock")
                    .font(.caption2)
                if profile.isAutoSyncEnabled {
                    Text(ScheduleInterval.nearestBadge(for: profile.scheduleIntervalMinutes))
                        .font(.caption2)
                        .fontWeight(.medium)
                } else {
                    Text("Auto: Off")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 7))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                profile.isAutoSyncEnabled
                    ? Color.accentColor.opacity(0.15)
                    : Color.secondary.opacity(0.08)
            )
            .foregroundColor(profile.isAutoSyncEnabled ? .accentColor : .secondary)
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(
                        profile.isAutoSyncEnabled ? Color.accentColor.opacity(0.3) : Color.secondary.opacity(0.2),
                        lineWidth: 1
                    )
            )
            .cornerRadius(5)
        }
        .menuStyle(.borderlessButton)
        .help(profile.isAutoSyncEnabled
            ? "Auto-sync every \(profile.scheduleIntervalMinutes)m\(state.scheduler.formatNextSyncCountdown(for: profile).map { " (\($0))" } ?? ""). Click to change."
            : "Automatic sync is off. Click to set interval (5m, 15m, 1h, Daily, Weekly)."
        )
    }

    private func tagView(_ text: String, icon: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
            Text(text)
        }
        .font(.caption2)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.secondary.opacity(0.12))
        .cornerRadius(4)
    }

    private func toggleTagView(
        title: String,
        icon: String,
        isEnabled: Bool,
        tooltip: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                Text(title)
                    .font(.caption2)
                    .fontWeight(isEnabled ? .medium : .regular)
                if !isEnabled {
                    Text("Off")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                isEnabled
                    ? Color.accentColor.opacity(0.15)
                    : Color.secondary.opacity(0.08)
            )
            .foregroundColor(isEnabled ? .accentColor : .secondary)
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(
                        isEnabled ? Color.accentColor.opacity(0.3) : Color.secondary.opacity(0.2),
                        lineWidth: 1
                    )
            )
            .cornerRadius(5)
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
