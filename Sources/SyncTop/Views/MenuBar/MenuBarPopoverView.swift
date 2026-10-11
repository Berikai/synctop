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
                Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                    .foregroundColor(.accentColor)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text("SyncTop")
                        .font(.headline)
                    Text(remoteStatusText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if state.isAnySyncing {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)

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
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: profile.direction.systemImage)
                        .foregroundColor(.accentColor)
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
        return "Connected: \(state.detectedRemotes.joined(separator: ", "))"
    }
}
