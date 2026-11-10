import SwiftUI
import AppKit
import SyncTopCore

public struct ManagerWindowView: View {
    @ObservedObject var state: AppState

    public init(state: AppState) {
        self.state = state
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Top App Bar
            HStack(spacing: 12) {
                Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                    .foregroundColor(.accentColor)
                    .font(.title2)

                VStack(alignment: .leading, spacing: 2) {
                    Text("SyncTop")
                        .font(.title3)
                        .fontWeight(.bold)
                    Text("Direct Google Drive Sync (Mount-Free)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Remote status pill
                remoteStatusPill

                Button {
                    state.editingProfile = nil
                    state.isEditorPresented = true
                } label: {
                    Label("Add Folder Pair", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    state.syncAll()
                } label: {
                    Label("Sync All", systemImage: "play.fill")
                }
                .disabled(state.profiles.isEmpty || state.isAnySyncing)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Auth expiration / Reconnect banner
            if state.isAuthExpired || state.reconnectingRemote != nil || state.reconnectErrorMessage != nil {
                authAlertBanner
                Divider()
            }

            // Profiles list or Empty State
            if state.profiles.isEmpty {
                emptyStateView
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(state.profiles) { profile in
                            ProfileCardView(
                                state: state,
                                profile: profile,
                                onEdit: {
                                    state.editingProfile = profile
                                    state.isEditorPresented = true
                                },
                                onShowLogs: {
                                    state.selectedLogProfileId = profile.id
                                    state.isLogConsolePresented = true
                                }
                            )
                        }
                    }
                    .padding(16)
                }
            }

            Divider()

            // Footer Bar
            HStack(spacing: 12) {
                Text("\(state.profiles.count) configured folder \(state.profiles.count == 1 ? "pair" : "pairs")")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Button {
                    state.toggleLaunchAtLogin()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: state.isLaunchAtLoginEnabled ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(state.isLaunchAtLoginEnabled ? .accentColor : .secondary)
                        Text("Start at Login")
                    }
                    .font(.caption)
                }
                .buttonStyle(.plain)
                .help("Automatically launch SyncTop in the background when logging into macOS")

                Divider()
                    .frame(height: 12)

                if let firstRemote = state.detectedRemotes.first {
                    Text("Remote Engine: \(firstRemote):")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(minWidth: 640, minHeight: 480)
        .sheet(isPresented: $state.isEditorPresented) {
            ProfileEditorView(
                state: state,
                profileToEdit: state.editingProfile
            ) { newProfile in
                Task { await state.saveProfile(newProfile) }
            }
        }
        .sheet(isPresented: $state.isDryRunPresented) {
            DryRunModalView(state: state) {
                if let profile = state.dryRunProfile {
                    state.sync(id: profile.id)
                }
            }
        }
        .sheet(isPresented: $state.isLogConsolePresented) {
            LogConsoleView(
                state: state,
                profileId: state.selectedLogProfileId
            )
        }
    }

    private var remoteStatusPill: some View {
        let dotColor: Color = {
            if !state.isRcloneAvailable { return .red }
            if state.isAuthExpired { return .orange }
            return .green
        }()

        let statusText: String = {
            if !state.isRcloneAvailable { return "Engine Missing" }
            if state.reconnectingRemote != nil { return "Reconnecting..." }
            if let expired = state.primaryExpiredRemote { return "\(expired) (Auth Expired)" }
            return state.detectedRemotes.first ?? "rclone ready"
        }()

        return HStack(spacing: 5) {
            Circle()
                .fill(dotColor)
                .frame(width: 8, height: 8)
            Text(statusText)
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(state.isAuthExpired ? Color.orange.opacity(0.45) : Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var authAlertBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                if let reconnecting = state.reconnectingRemote {
                    ProgressView()
                        .controlSize(.small)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Waiting for browser authorization for '\(reconnecting)'...")
                            .font(.callout)
                            .fontWeight(.medium)
                        Text("Complete the Google sign-in in your browser. SyncTop will automatically resume stalled folders.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    if let url = state.reconnectAuthURL {
                        Button("Open Auth Link") {
                            NSWorkspace.shared.open(url)
                        }
                        .controlSize(.small)
                    }
                    Button("Cancel") {
                        state.cancelReconnect()
                    }
                    .controlSize(.small)
                } else if let expired = state.primaryExpiredRemote {
                    Image(systemName: "key.slash.fill")
                        .foregroundColor(.orange)
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Google Drive authentication expired for '\(expired)'")
                            .font(.callout)
                            .fontWeight(.semibold)
                        Text("Scheduled syncs for this account are paused until you sign in again.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button {
                        state.reconnectRemote(expired)
                    } label: {
                        Label("Reconnect \(expired)", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .controlSize(.regular)
                }
            }

            if let errorMsg = state.reconnectErrorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                        .font(.caption)
                    Text("Reconnect failed: \(errorMsg)")
                        .font(.caption)
                        .foregroundColor(.red)
                    Spacer()
                    Button("Dismiss") {
                        state.reconnectErrorMessage = nil
                    }
                    .font(.caption2)
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.12))
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "folder.badge.gearshape")
                .font(.system(size: 54))
                .foregroundColor(.accentColor.opacity(0.8))

            Text("No Folders Configured")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Select any folder on your Mac and map it directly to a folder in Google Drive.\nNo virtual mounts, no stub files, and complete selective control.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)

            Button {
                state.editingProfile = nil
                state.isEditorPresented = true
            } label: {
                Label("Add Your First Folder Pair", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, 8)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
