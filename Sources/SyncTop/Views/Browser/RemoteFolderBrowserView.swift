import SwiftUI
import Combine
import SyncTopCore

@MainActor
public final class RemoteBrowserViewModel: ObservableObject {
    @Published public var currentPathComponents: [String] = []
    @Published public var folders: [RemoteFolderItem] = []
    @Published public var isLoading: Bool = false
    @Published public var errorMessage: String? = nil
    
    @Published public var isNewFolderAlertPresented: Bool = false
    @Published public var newFolderName: String = ""

    private let browser = RcloneRemoteBrowser()
    let remoteName: String

    public init(remoteName: String, initialPath: String) {
        self.remoteName = remoteName
        let cleaned = initialPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !cleaned.isEmpty {
            self.currentPathComponents = cleaned.components(separatedBy: "/")
        }
    }

    public var currentSubPath: String {
        currentPathComponents.joined(separator: "/")
    }

    public func loadFolders() async {
        isLoading = true
        errorMessage = nil
        do {
            let items = try await browser.listDirectories(
                remoteName: remoteName,
                subPath: currentSubPath
            )
            self.folders = items
            self.isLoading = false
        } catch {
            self.errorMessage = error.localizedDescription
            self.isLoading = false
        }
    }

    public func createFolder() async {
        let trimmed = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let fullRelPath = currentSubPath.isEmpty ? trimmed : "\(currentSubPath)/\(trimmed)"
        do {
            try await browser.createDirectory(remoteName: remoteName, directoryPath: fullRelPath)
            await loadFolders()
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }
}

public struct RemoteFolderBrowserView: View {
    let remoteName: String
    let initialPath: String
    let onSelectPath: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    @StateObject private var vm: RemoteBrowserViewModel

    public init(
        remoteName: String,
        initialPath: String,
        onSelectPath: @escaping (String) -> Void
    ) {
        self.remoteName = remoteName
        self.initialPath = initialPath
        self.onSelectPath = onSelectPath
        _vm = StateObject(wrappedValue: RemoteBrowserViewModel(remoteName: remoteName, initialPath: initialPath))
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header & Breadcrumb
            HStack {
                Image(systemName: "cloud.fill")
                    .foregroundColor(.accentColor)
                Text("\(remoteName):/\(vm.currentSubPath)")
                    .font(.headline)
                    .lineLimit(1)
                Spacer()

                if !vm.currentPathComponents.isEmpty {
                    Button {
                        vm.currentPathComponents.removeLast()
                        Task { await vm.loadFolders() }
                    } label: {
                        Label("Up", systemImage: "arrow.up")
                    }
                    .controlSize(.small)
                }

                Button {
                    vm.newFolderName = ""
                    vm.isNewFolderAlertPresented = true
                } label: {
                    Label("New Folder", systemImage: "folder.badge.plus")
                }
                .controlSize(.small)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Folder list
            if vm.isLoading {
                VStack {
                    Spacer()
                    ProgressView("Loading remote folders...")
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = vm.errorMessage {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.orange)
                    Text("Failed to load directories")
                        .font(.headline)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Button("Retry") {
                        Task { await vm.loadFolders() }
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if vm.folders.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "folder")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No subdirectories found")
                        .foregroundColor(.secondary)
                    Text("You can create one or select this directory.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(vm.folders) { folder in
                    HStack {
                        Image(systemName: "folder.fill")
                            .foregroundColor(.accentColor)
                        Text(folder.name)
                            .font(.body)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        vm.currentPathComponents.append(folder.name)
                        Task { await vm.loadFolders() }
                    }
                }
            }

            Divider()

            // Footer / Selection
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                Spacer()
                Button("Select Current Folder") {
                    onSelectPath(vm.currentSubPath)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 520, height: 420)
        .task {
            await vm.loadFolders()
        }
        .alert("Create New Folder", isPresented: $vm.isNewFolderAlertPresented) {
            TextField("Folder Name", text: $vm.newFolderName)
            Button("Create") {
                Task { await vm.createFolder() }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}
