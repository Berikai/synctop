import SwiftUI
import AppKit
import Combine
import SyncTopCore

@MainActor
public final class ProfileEditorViewModel: ObservableObject {
    @Published public var name: String = ""
    @Published public var localPath: String = ""
    @Published public var remoteName: String = "google"
    @Published public var remotePath: String = ""
    @Published public var direction: SyncDirection = .bidirectional

    @Published public var isDeveloperPresetEnabled: Bool = true
    @Published public var isSystemPresetEnabled: Bool = true
    @Published public var customExcludesString: String = ""

    @Published public var isAutoSyncEnabled: Bool = false
    @Published public var scheduleIntervalMinutes: Int = 60

    @Published public var isRemoteBrowserPresented: Bool = false

    private let bookmarkManager = BookmarkManager()

    public init(profileToEdit: SyncProfile?, defaultRemote: String) {
        if let existing = profileToEdit {
            self.name = existing.name
            self.localPath = existing.localPath
            self.remoteName = existing.remoteName
            self.remotePath = existing.remotePath
            self.direction = existing.direction
            self.isDeveloperPresetEnabled = existing.isDeveloperPresetEnabled
            self.isSystemPresetEnabled = existing.isSystemPresetEnabled
            self.customExcludesString = existing.customExcludes.joined(separator: ", ")
            self.isAutoSyncEnabled = existing.isAutoSyncEnabled
            self.scheduleIntervalMinutes = existing.scheduleIntervalMinutes
        } else {
            self.remoteName = defaultRemote
        }
    }

    public func chooseLocalFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            self.localPath = url.path
            if self.name.isEmpty {
                self.name = url.lastPathComponent
            }
            if self.remotePath.isEmpty {
                self.remotePath = "Backups/\(url.lastPathComponent)"
            }
        }
    }

    public func buildProfile(existing: SyncProfile?) -> SyncProfile {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = trimmedName.isEmpty ? URL(fileURLWithPath: localPath).lastPathComponent : trimmedName

        let customList = customExcludesString
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let localURL = URL(fileURLWithPath: localPath)
        let bookmark = bookmarkManager.createBookmark(for: localURL)

        var profile = existing ?? SyncProfile(
            name: resolvedName,
            localPath: localPath,
            remoteName: remoteName,
            remotePath: remotePath
        )

        profile.name = resolvedName
        profile.localPath = localPath
        profile.remoteName = remoteName
        profile.remotePath = remotePath
        profile.direction = direction
        profile.isDeveloperPresetEnabled = isDeveloperPresetEnabled
        profile.isSystemPresetEnabled = isSystemPresetEnabled
        profile.customExcludes = customList
        profile.isAutoSyncEnabled = isAutoSyncEnabled
        profile.scheduleIntervalMinutes = scheduleIntervalMinutes
        if let bookmark {
            profile.securityScopedBookmark = bookmark
        }

        return profile
    }
}

public struct ProfileEditorView: View {
    @ObservedObject var state: AppState
    let profileToEdit: SyncProfile?
    let onSave: (SyncProfile) -> Void
    @Environment(\.dismiss) private var dismiss

    @StateObject private var vm: ProfileEditorViewModel

    public init(
        state: AppState,
        profileToEdit: SyncProfile?,
        onSave: @escaping (SyncProfile) -> Void
    ) {
        self.state = state
        self.profileToEdit = profileToEdit
        self.onSave = onSave
        let defaultRemote = state.detectedRemotes.first ?? "google"
        _vm = StateObject(wrappedValue: ProfileEditorViewModel(profileToEdit: profileToEdit, defaultRemote: defaultRemote))
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(profileToEdit?.id == nil ? "Add Folder Pair" : "Edit Folder Pair")
                    .font(.headline)
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            Form {
                Section("General") {
                    TextField("Profile Name", text: $vm.name, prompt: Text("e.g. Work Documents"))
                }

                Section("Locations") {
                    // Local Folder
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Local Folder")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        HStack {
                            TextField("Local Folder Path", text: $vm.localPath)
                            Button("Choose...") {
                                vm.chooseLocalFolder()
                            }
                        }
                    }

                    // Cloud Destination
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Google Drive Destination")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        HStack {
                            if !state.detectedRemotes.isEmpty {
                                Picker("", selection: $vm.remoteName) {
                                    ForEach(state.detectedRemotes, id: \.self) { r in
                                        Text(r).tag(r)
                                    }
                                }
                                .frame(width: 100)
                            } else {
                                TextField("Remote", text: $vm.remoteName)
                                    .frame(width: 80)
                            }
                            Text(":")
                            TextField("Path in Drive (e.g. Backups/Work)", text: $vm.remotePath)
                            Button("Browse...") {
                                vm.isRemoteBrowserPresented = true
                            }
                        }
                    }
                }

                Section("Sync Direction") {
                    Picker("Mode", selection: $vm.direction) {
                        ForEach(SyncDirection.allCases, id: \.self) { dir in
                            Label(dir.displayName, systemImage: dir.systemImage).tag(dir)
                        }
                    }
                    .pickerStyle(.segmented)

                    if vm.direction == .bidirectional {
                        Text("Keeps both folders in sync. Any conflicting edits will be preserved as .sync-conflict copies.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else if vm.direction == .push {
                        Text("Local files will be backed up to Google Drive. Remote-only edits will not overwrite local.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Google Drive files will be restored down to your local directory.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Section("Exclusions & Filters") {
                    Toggle("Ignore Developer Junk (node_modules, .git, .venv, target)", isOn: $vm.isDeveloperPresetEnabled)
                    Toggle("Ignore macOS System Junk (.DS_Store, .Trash, Thumbs.db)", isOn: $vm.isSystemPresetEnabled)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Custom Exclude Rules (comma separated)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("e.g. *.log, temp/**", text: $vm.customExcludesString)
                    }
                }

                Section("Automation Schedule") {
                    Toggle("Auto-Sync on Schedule", isOn: $vm.isAutoSyncEnabled)

                    if vm.isAutoSyncEnabled {
                        Picker("Interval", selection: $vm.scheduleIntervalMinutes) {
                            ForEach(ScheduleInterval.allCases) { interval in
                                Text(interval.title).tag(interval.rawValue)
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .padding(.horizontal, 8)

            Divider()

            // Footer
            HStack {
                Spacer()
                Button("Save Folder Pair") {
                    let result = vm.buildProfile(existing: profileToEdit)
                    onSave(result)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(vm.localPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 540, height: 560)
        .sheet(isPresented: $vm.isRemoteBrowserPresented) {
            RemoteFolderBrowserView(
                remoteName: vm.remoteName,
                initialPath: vm.remotePath
            ) { selectedPath in
                vm.remotePath = selectedPath
            }
        }
    }
}
