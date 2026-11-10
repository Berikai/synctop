import SwiftUI
import SyncTopCore

public struct MenuBarPopoverView: View {
    @ObservedObject var state: AppState
    let openManagerAction: () -> Void

    public init(state: AppState, openManagerAction: @escaping () -> Void) {
        self.state = state
        self.openManagerAction = openManagerAction
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack {
                Image(systemName: state.isAuthExpired ? "exclamationmark.triangle.fill" : "arrow.triangle.2.circlepath.circle.fill")
                    .foregroundColor(state.isAuthExpired ? .orange : .accentColor)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text("SyncTop")
                        .font(.headline)
                    Text(remoteStatusText)
                        .font(.caption)
                        .foregroundColor(state.isAuthExpired ? .orange : (state.hasFailures ? .red : .secondary))
                }
                Spacer()
                if state.isAnySyncing || state.reconnectingRemote != nil {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)

            if state.isAuthExpired || state.reconnectingRemote != nil {
                popoverAuthBanner
                    .padding(.horizontal, 12)
            }

            Divider()

            // Profiles List
            if state.isInitializing && state.profiles.isEmpty {
                VStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading folder pairs...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            } else if state.profiles.isEmpty {
                VStack(spacing: 6) {
                    Text("No folders configured")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Button("Add Folder Pair") {
                        state.editingProfile = SyncProfile(name: "", localPath: "", remotePath: "")
                        state.isEditorPresented = true
                        openManagerAction()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            } else if state.profiles.count > 4 {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(state.profiles) { profile in
                            profileRow(profile)
                        }
                    }
                    .padding(.horizontal, 12)
                }
                .frame(height: 240)
            } else {
                VStack(spacing: 8) {
                    ForEach(state.profiles) { profile in
                        profileRow(profile)
                    }
                }
                .padding(.horizontal, 12)
            }

            Divider()

            // Actions
            HStack {
                Button {
                    state.syncAll()
                } label: {
                    Label("Sync All", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(state.profiles.isEmpty || state.isAnySyncing)

                Spacer()

                Button {
                    openManagerAction()
                } label: {
                    Label("Manager...", systemImage: "gearshape")
                }
                .controlSize(.small)

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .controlSize(.small)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
        .frame(width: 320)
        .task {
            await state.initialize()
        }
    }

    private func profileRow(_ profile: SyncProfile) -> some View {
        let isRemoteExpired = state.authExpiredRemotes.contains(RcloneAuthHelper.cleanRemoteName(profile.remoteName))
        let isAuthIssue = profile.lastSyncStatus == .authRequired || isRemoteExpired

        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    rowStatusIcon(for: profile, isAuthIssue: isAuthIssue)
                        .font(.caption)
                    Text(profile.name.isEmpty ? URL(fileURLWithPath: profile.localPath).lastPathComponent : profile.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                }

                if profile.lastSyncStatus == .syncing, let progress = state.activeProgress[profile.id] {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(progress.transferSpeed ?? "Syncing...") • Total: \(Int(progress.percentage))%")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        if let file = progress.currentFile {
                            Text(file)
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                } else if isAuthIssue {
                    Text("Auth expired • Reconnect required")
                        .font(.caption2)
                        .foregroundColor(.orange)
                } else if profile.lastSyncStatus == .failed {
                    Text(profile.lastSyncMessage ?? "Sync failed")
                        .font(.caption2)
                        .foregroundColor(.red)
                        .lineLimit(1)
                } else if profile.lastSyncStatus == .conflict {
                    Text("Conflict detected • Check logs")
                        .font(.caption2)
                        .foregroundColor(.orange)
                } else if let lastDate = profile.lastSyncDate {
                    Text("Synced \(lastDate.formatted(.relative(presentation: .named)))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else {
                    Text("Not synced yet")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if profile.lastSyncStatus == .syncing {
                Button {
                    state.cancelSync(id: profile.id)
                } label: {
                    Image(systemName: "stop.fill")
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    state.sync(id: profile.id)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
        }
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
        .cornerRadius(6)
    }

    @ViewBuilder
    private func rowStatusIcon(for profile: SyncProfile, isAuthIssue: Bool) -> some View {
        if profile.lastSyncStatus == .syncing {
            Image(systemName: profile.direction.systemImage)
                .foregroundColor(.accentColor)
        } else if isAuthIssue {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
        } else if profile.lastSyncStatus == .failed {
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.red)
        } else if profile.lastSyncStatus == .conflict {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
        } else {
            Image(systemName: profile.direction.systemImage)
                .foregroundColor(.accentColor)
        }
    }

    private var popoverAuthBanner: some View {
        HStack(spacing: 8) {
            if let reconnecting = state.reconnectingRemote {
                ProgressView()
                    .controlSize(.mini)
                Text("Signing into '\(reconnecting)' in browser...")
                    .font(.caption2)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Spacer()
                Button("Cancel") {
                    state.cancelReconnect()
                }
                .controlSize(.mini)
            } else if let remote = state.primaryExpiredRemote {
                Image(systemName: "key.slash.fill")
                    .foregroundColor(.orange)
                    .font(.caption)
                Text("Token expired for '\(remote)'")
                    .font(.caption2)
                    .foregroundColor(.primary)
                Spacer()
                Button("Reconnect") {
                    state.reconnectRemote(remote)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .controlSize(.mini)
            }
        }
        .padding(8)
        .background(Color.orange.opacity(0.14))
        .cornerRadius(6)
    }

    private var remoteStatusText: String {
        if state.isInitializing {
            return "Checking rclone & remotes..."
        }
        if !state.isRcloneAvailable {
            return "rclone not detected"
        }
        if state.detectedRemotes.isEmpty {
            return "No remotes configured"
        }
        if let expired = state.primaryExpiredRemote {
            return "Auth expired: \(expired)"
        }
        if state.hasFailures {
            return "Sync failure detected"
        }
        return "Connected: \(state.detectedRemotes.joined(separator: ", "))"
    }
}
