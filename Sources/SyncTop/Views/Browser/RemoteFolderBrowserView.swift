import SwiftUI
import Combine
import SyncTopCore

@MainActor
public final class RemoteBrowserViewModel: ObservableObject {
    @Published public var currentPathComponents: [String] = []
    @Published public var folders: [RemoteFolderItem] = []
    @Published public var isLoading: Bool = false
    @Published public var errorMessage: String? = nil
    @Published public var errorDetails: String? = nil
    @Published public var isDirectoryNotFound: Bool = false
    
    @Published public var infoBanner: String? = nil
    @Published public var suggestedMissingPath: String? = nil

    @Published public var isNewFolderAlertPresented: Bool = false
    @Published public var newFolderName: String = ""

    private let browser = RcloneRemoteBrowser()
    public let remoteName: String

    public var cleanRemoteName: String {
        remoteName.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
    }

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

    public func loadFolders(autoFallback: Bool = true) async {
        isLoading = true
        errorMessage = nil
        errorDetails = nil
        isDirectoryNotFound = false

        do {
            let items = try await browser.listDirectories(
                remoteName: cleanRemoteName,
                subPath: currentSubPath
            )
            self.folders = items
            self.isLoading = false
        } catch let error as RemoteBrowserError {
            if case .directoryNotFound(let target, let details) = error {
                if autoFallback && !currentPathComponents.isEmpty {
                    let attemptedPath = currentSubPath
                    var fallbackComponents = currentPathComponents
                    var fallbackSuccess = false

                    while !fallbackComponents.isEmpty {
                        fallbackComponents.removeLast()
                        let fallbackSubPath = fallbackComponents.joined(separator: "/")
                        do {
                            let items = try await browser.listDirectories(
                                remoteName: cleanRemoteName,
                                subPath: fallbackSubPath
                            )
                            self.currentPathComponents = fallbackComponents
                            self.folders = items
                            self.isLoading = false
                            let dest = fallbackSubPath.isEmpty ? "root folder" : "'\(fallbackSubPath)'"
                            self.infoBanner = "Folder '\(attemptedPath)' does not exist on \(cleanRemoteName) yet. Showing \(dest)."
                            self.suggestedMissingPath = attemptedPath
                            fallbackSuccess = true
                            break
                        } catch let nextErr as RemoteBrowserError {
                            if case .directoryNotFound = nextErr {
                                continue
                            } else {
                                self.errorMessage = nextErr.localizedDescription
                                self.errorDetails = details
                                self.isLoading = false
                                return
                            }
                        } catch {
                            self.errorMessage = error.localizedDescription
                            self.isLoading = false
                            return
                        }
                    }

                    if fallbackSuccess {
                        return
                    }
                }

                self.isDirectoryNotFound = true
                self.errorMessage = "Directory '\(target.isEmpty ? "/" : target)' does not exist on \(cleanRemoteName)."
                self.errorDetails = details
                self.isLoading = false
            } else if case .executionFailed(let details) = error {
                self.errorMessage = error.localizedDescription
                self.errorDetails = details
                self.isLoading = false
            } else {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        } catch {
            self.errorMessage = error.localizedDescription
            self.isLoading = false
        }
    }

    public func navigateTo(components: [String]) async {
        self.currentPathComponents = components
        self.infoBanner = nil
        await loadFolders(autoFallback: false)
    }

    public func goToRoot() async {
        await navigateTo(components: [])
    }

    public func goUp() async {
        guard !currentPathComponents.isEmpty else { return }
        var updated = currentPathComponents
        updated.removeLast()
        await navigateTo(components: updated)
    }

    public func createFolder() async {
        let trimmed = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let fullRelPath = currentSubPath.isEmpty ? trimmed : "\(currentSubPath)/\(trimmed)"
        do {
            try await browser.createDirectory(remoteName: cleanRemoteName, directoryPath: fullRelPath)
            self.infoBanner = nil
            await loadFolders(autoFallback: false)
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    public func createPath(path: String) async {
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmed.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        errorDetails = nil
        do {
            try await browser.createDirectory(remoteName: cleanRemoteName, directoryPath: trimmed)
            self.infoBanner = nil
            self.suggestedMissingPath = nil
            self.currentPathComponents = trimmed.components(separatedBy: "/")
            await loadFolders(autoFallback: false)
        } catch {
            self.errorMessage = error.localizedDescription
            self.isLoading = false
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
            // Header & Interactive Breadcrumbs
            HStack(spacing: 8) {
                Image(systemName: "cloud.fill")
                    .foregroundColor(.accentColor)
                    .imageScale(.medium)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        Button {
                            Task { await vm.goToRoot() }
                        } label: {
                            Text("\(vm.cleanRemoteName):")
                                .font(.headline)
                                .foregroundColor(vm.currentPathComponents.isEmpty ? .primary : .accentColor)
                        }
                        .buttonStyle(.plain)

                        Text("/")
                            .foregroundColor(.secondary)
                            .font(.headline)

                        ForEach(Array(vm.currentPathComponents.enumerated()), id: \.offset) { index, component in
                            Button {
                                let targetComponents = Array(vm.currentPathComponents.prefix(through: index))
                                Task { await vm.navigateTo(components: targetComponents) }
                            } label: {
                                Text(component)
                                    .font(.headline)
                                    .foregroundColor(index == vm.currentPathComponents.count - 1 ? .primary : .accentColor)
                            }
                            .buttonStyle(.plain)

                            if index < vm.currentPathComponents.count - 1 {
                                Text("/")
                                    .foregroundColor(.secondary)
                                    .font(.headline)
                            }
                        }
                    }
                }

                Spacer()

                if !vm.currentPathComponents.isEmpty {
                    Button {
                        Task { await vm.goUp() }
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
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Optional info banner when auto-fallback occurred
            if let banner = vm.infoBanner {
                HStack(spacing: 10) {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.blue)
                        .font(.body)

                    Text(banner)
                        .font(.callout)
                        .foregroundColor(.primary)

                    Spacer()

                    if let missing = vm.suggestedMissingPath {
                        Button("Create '\(missing)'") {
                            Task { await vm.createPath(path: missing) }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }

                    Button {
                        vm.infoBanner = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color.blue.opacity(0.1))
                Divider()
            }

            // Folder list / States
            if vm.isLoading {
                VStack(spacing: 10) {
                    Spacer()
                    ProgressView()
                    Text("Loading remote folders...")
                        .font(.callout)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = vm.errorMessage {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: vm.isDirectoryNotFound ? "folder.badge.questionmark" : "exclamationmark.triangle")
                        .font(.system(size: 40))
                        .foregroundColor(vm.isDirectoryNotFound ? .blue : .orange)

                    Text(vm.isDirectoryNotFound ? "Folder Does Not Exist" : "Failed to Load Directories")
                        .font(.headline)

                    Text(error)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)

                    if vm.isDirectoryNotFound && !vm.currentSubPath.isEmpty {
                        Text("This folder hasn't been created on \(vm.cleanRemoteName) yet. You can create it now or browse the root folder.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }

                    HStack(spacing: 10) {
                        if vm.isDirectoryNotFound && !vm.currentSubPath.isEmpty {
                            Button {
                                Task { await vm.createPath(path: vm.currentSubPath) }
                            } label: {
                                Label("Create This Folder", systemImage: "folder.badge.plus")
                            }
                            .buttonStyle(.borderedProminent)
                        }

                        Button {
                            Task { await vm.goToRoot() }
                        } label: {
                            Label("Go to Root Folder", systemImage: "house")
                        }

                        if !vm.currentPathComponents.isEmpty {
                            Button {
                                Task { await vm.goUp() }
                            } label: {
                                Label("Up", systemImage: "arrow.up")
                            }
                        }

                        Button("Retry") {
                            Task { await vm.loadFolders(autoFallback: false) }
                        }
                    }
                    .controlSize(.regular)
                    .padding(.top, 4)

                    if let details = vm.errorDetails, !details.isEmpty {
                        DisclosureGroup("Error Details") {
                            ScrollView {
                                Text(details)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxHeight: 70)
                            .padding(6)
                            .background(Color(NSColor.textBackgroundColor).opacity(0.5))
                            .cornerRadius(6)
                        }
                        .frame(maxWidth: 420)
                        .padding(.top, 4)
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
                        Task {
                            var components = vm.currentPathComponents
                            components.append(folder.name)
                            await vm.navigateTo(components: components)
                        }
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

                Text("Selected: \(vm.cleanRemoteName):/\(vm.currentSubPath)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                Button("Select Current Folder") {
                    onSelectPath(vm.currentSubPath)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 560, height: 440)
        .task {
            await vm.loadFolders(autoFallback: true)
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
