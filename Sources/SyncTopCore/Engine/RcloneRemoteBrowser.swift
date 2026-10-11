import Foundation

public struct RemoteFolderItem: Identifiable, Hashable, Sendable {
    public var id: String { fullPath }
    public let name: String
    public let relativePath: String
    public let fullPath: String

    public init(name: String, relativePath: String, fullPath: String) {
        self.name = name
        self.relativePath = relativePath
        self.fullPath = fullPath
    }
}

public enum RemoteBrowserError: LocalizedError, Sendable, Equatable {
    case binaryNotFound
    case directoryNotFound(path: String, rawError: String)
    case executionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .binaryNotFound:
            return "rclone binary not found. Please install rclone or specify custom path."
        case .directoryNotFound(let path, _):
            return "Directory '\(path)' was not found on remote."
        case .executionFailed(let reason):
            return "Failed to browse remote: \(reason)"
        }
    }
}

/// Allows interactive navigation and folder creation directly inside Google Drive via rclone APIs.
public final class RcloneRemoteBrowser: Sendable {
    private let discovery: RcloneDiscovery
    private let runner: ProcessRunner

    public init(
        discovery: RcloneDiscovery = RcloneDiscovery(),
        runner: ProcessRunner = ProcessRunner()
    ) {
        self.discovery = discovery
        self.runner = runner
    }

    /// Lists subdirectories inside a specific remote path.
    public func listDirectories(
        remoteName: String,
        subPath: String = "",
        customBinaryPath: String? = nil
    ) async throws -> [RemoteFolderItem] {
        guard let binary = discovery.locateBinary(customPath: customBinaryPath) else {
            throw RemoteBrowserError.binaryNotFound
        }

        let cleanRemote = remoteName.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
        let cleanSubPath = subPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let target = cleanSubPath.isEmpty ? "\(cleanRemote):" : "\(cleanRemote):\(cleanSubPath)"

        let result = try await runner.run(
            executableURL: binary,
            arguments: ["lsf", target, "--dirs-only"]
        )

        guard result.exitCode == 0 else {
            let stderrLower = result.errorOutput.lowercased()
            if stderrLower.contains("directory not found") {
                throw RemoteBrowserError.directoryNotFound(path: cleanSubPath, rawError: result.errorOutput)
            }
            throw RemoteBrowserError.executionFailed(result.errorOutput)
        }

        let lines = result.output.components(separatedBy: .newlines)
        return lines.compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let dirName = trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
            let itemRelPath = cleanSubPath.isEmpty ? dirName : "\(cleanSubPath)/\(dirName)"
            let itemFullPath = "\(cleanRemote):\(itemRelPath)"
            return RemoteFolderItem(name: dirName, relativePath: itemRelPath, fullPath: itemFullPath)
        }
    }

    /// Creates a directory on the remote.
    public func createDirectory(
        remoteName: String,
        directoryPath: String,
        customBinaryPath: String? = nil
    ) async throws {
        guard let binary = discovery.locateBinary(customPath: customBinaryPath) else {
            throw RemoteBrowserError.binaryNotFound
        }

        let cleanRemote = remoteName.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
        let cleanPath = directoryPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let target = "\(cleanRemote):\(cleanPath)"

        let result = try await runner.run(
            executableURL: binary,
            arguments: ["mkdir", target]
        )

        guard result.exitCode == 0 else {
            throw RemoteBrowserError.executionFailed(result.errorOutput)
        }
    }
}
