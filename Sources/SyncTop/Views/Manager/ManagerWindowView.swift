import SwiftUI
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
            HStack {
                Text("\(state.profiles.count) configured folder \(state.profiles.count == 1 ? "pair" : "pairs")")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

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
        HStack(spacing: 5) {
            Circle()
                .fill(state.isRcloneAvailable ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            Text(state.isRcloneAvailable ? (state.detectedRemotes.first ?? "rclone ready") : "Engine Missing")
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
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
