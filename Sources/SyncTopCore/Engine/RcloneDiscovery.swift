import Foundation

public struct RcloneInfo: Sendable {
    public let binaryURL: URL
    public let version: String
    public let remotes: [String]
}

public enum RcloneDiscoveryError: LocalizedError, Sendable {
    case binaryNotFound
    case executionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .binaryNotFound:
            return "rclone binary not found. Please install rclone via Homebrew (`brew install rclone`) or place it in `/usr/local/bin/rclone`."
        case .executionFailed(let reason):
            return "Failed to execute rclone: \(reason)"
        }
    }
}

/// Discovers local rclone installations and configured remotes.
public final class RcloneDiscovery: Sendable {
    private let candidatePaths: [String] = [
        "/usr/local/bin/rclone",
        "/opt/homebrew/bin/rclone",
        "/usr/bin/rclone"
    ]
    
    private let runner: ProcessRunner

    public init(runner: ProcessRunner = ProcessRunner()) {
        self.runner = runner
    }

    /// Finds the rclone executable URL on the current machine.
    public func locateBinary(customPath: String? = nil) -> URL? {
        if let customPath, !customPath.isEmpty {
            let url = URL(fileURLWithPath: customPath)
            if FileManager.default.isExecutableFile(atPath: url.path) {
                return url
            }
        }

        for path in candidatePaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }

        // Try `which rclone`
        let whichProcess = Process()
        whichProcess.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        whichProcess.arguments = ["rclone"]
        let pipe = Pipe()
        whichProcess.standardOutput = pipe
        try? whichProcess.run()
        whichProcess.waitUntilExit()

        if whichProcess.terminationStatus == 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !output.isEmpty, FileManager.default.isExecutableFile(atPath: output) {
                return URL(fileURLWithPath: output)
            }
        }

        return nil
    }

    /// Detects rclone version and configured remotes.
    public func discover(customBinaryPath: String? = nil) async throws -> RcloneInfo {
        guard let binaryURL = locateBinary(customPath: customBinaryPath) else {
            throw RcloneDiscoveryError.binaryNotFound
        }

        // 1. Get version
        let versionResult = try await runner.run(
            executableURL: binaryURL,
            arguments: ["version"]
        )
        guard versionResult.exitCode == 0 else {
            throw RcloneDiscoveryError.executionFailed(versionResult.errorOutput)
        }
        let firstLine = versionResult.output.components(separatedBy: .newlines).first ?? "rclone"

        // 2. Get remotes
        let remotes = try await listRemotes(binaryURL: binaryURL)

        return RcloneInfo(
            binaryURL: binaryURL,
            version: firstLine,
            remotes: remotes
        )
    }

    /// Lists remotes configured in rclone.conf (e.g. ["google"]).
    public func listRemotes(binaryURL: URL) async throws -> [String] {
        let result = try await runner.run(
            executableURL: binaryURL,
            arguments: ["listremotes"]
        )
        guard result.exitCode == 0 else {
            throw RcloneDiscoveryError.executionFailed(result.errorOutput)
        }

        let lines = result.output.components(separatedBy: .newlines)
        return lines.compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return trimmed.hasSuffix(":") ? String(trimmed.dropLast()) : trimmed
        }
    }
}
