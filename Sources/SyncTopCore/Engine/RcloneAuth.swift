import Foundation

public enum RemoteAuthCheckResult: Sendable, Equatable {
    case valid
    case authExpired(String)
    case offlineOrError(String)
}

public enum ReconnectEvent: Sendable, Equatable {
    case authURL(URL)
    case log(String)
    case succeeded
    case failed(String)
}

/// Utilities for detecting, normalizing, and recovering from rclone OAuth token expiration errors.
public enum RcloneAuthHelper: Sendable {
    /// Normalizes a remote string by stripping trailing colons and any rclone on-the-fly option hash (e.g. "google{nZ8i7}:" -> "google").
    public static func cleanRemoteName(_ raw: String) -> String {
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while cleaned.hasSuffix(":") {
            cleaned.removeLast()
        }
        if let braceIndex = cleaned.firstIndex(of: "{") {
            cleaned = String(cleaned[..<braceIndex])
        }
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Returns true if an rclone log or error line indicates an expired, revoked, or invalid OAuth token.
    public static func isAuthExpiredError(_ text: String) -> Bool {
        let lower = text.lowercased()
        let markers = [
            "invalid_grant",
            "couldn't fetch token",
            "token expired",
            "token has been expired or revoked",
            "oauth2: cannot fetch token",
            "rclone config reconnect"
        ]
        return markers.contains { lower.contains($0) }
    }

    /// Extracts the remote name from an rclone reconnect hint such as `rclone config reconnect google{nZ8i7}:`.
    public static func extractReconnectRemote(from text: String) -> String? {
        guard let range = text.range(of: "rclone config reconnect ", options: .caseInsensitive) else {
            return nil
        }
        let remainder = text[range.upperBound...]
        let token = remainder.split { ch in
            ch.isWhitespace || ch == "\"" || ch == "'" || ch == "`"
        }.first
        guard let token else { return nil }
        let cleaned = cleanRemoteName(String(token))
        return cleaned.isEmpty ? nil : cleaned
    }

    /// Extracts a local OAuth callback URL printed by `rclone config reconnect`.
    public static func extractAuthURL(from text: String) -> URL? {
        let pattern = #"https?://(?:127\.0\.0\.1|localhost):\d+/[^\s"']+"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text) else {
            return nil
        }
        return URL(string: String(text[range]))
    }
}

/// Executes lightweight auth checks and in-app OAuth reconnections against rclone remotes.
public final class RcloneAuthService: Sendable {
    private let discovery: RcloneDiscovery
    private let runner: ProcessRunner

    public init(
        discovery: RcloneDiscovery = RcloneDiscovery(),
        runner: ProcessRunner = ProcessRunner()
    ) {
        self.discovery = discovery
        self.runner = runner
    }

    /// Checks whether a remote's cached OAuth token is currently accepted by its backend.
    public func checkRemoteAuth(
        remoteName: String,
        customBinaryPath: String? = nil
    ) async -> RemoteAuthCheckResult {
        guard let binary = discovery.locateBinary(customPath: customBinaryPath) else {
            return .offlineOrError("rclone binary not found")
        }

        let cleanRemote = RcloneAuthHelper.cleanRemoteName(remoteName)
        guard !cleanRemote.isEmpty else {
            return .offlineOrError("Empty remote name")
        }

        do {
            let result = try await runner.run(
                executableURL: binary,
                arguments: ["lsd", "\(cleanRemote):", "--max-depth", "1"]
            )
            if result.exitCode == 0 {
                return .valid
            }
            let combined = "\(result.errorOutput)\n\(result.output)"
            if RcloneAuthHelper.isAuthExpiredError(combined) {
                return .authExpired(combined.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            return .offlineOrError(result.errorOutput.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch {
            return .offlineOrError(error.localizedDescription)
        }
    }

    /// Runs `rclone config reconnect <remote>: --auto-confirm` and streams status & browser OAuth URL.
    public func reconnect(
        remoteName: String,
        customBinaryPath: String? = nil
    ) -> (stream: AsyncStream<ReconnectEvent>, cancel: @Sendable () -> Void) {
        let binaryURL = discovery.locateBinary(customPath: customBinaryPath) ?? URL(fileURLWithPath: "/usr/local/bin/rclone")
        let cleanRemote = RcloneAuthHelper.cleanRemoteName(remoteName)

        let (rawStream, proc) = runner.stream(
            executableURL: binaryURL,
            arguments: ["config", "reconnect", "\(cleanRemote):", "--auto-confirm"]
        )

        let cancelHandler: @Sendable () -> Void = {
            if proc.isRunning {
                proc.terminate()
            }
        }

        let eventStream = AsyncStream<ReconnectEvent> { continuation in
            Task {
                var capturedErrors: [String] = []

                for await line in rawStream {
                    let text: String
                    switch line {
                    case .stdout(let str): text = str
                    case .stderr(let str): text = str
                    }

                    for singleLine in text.components(separatedBy: .newlines) {
                        let trimmed = singleLine.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { continue }

                        if let url = RcloneAuthHelper.extractAuthURL(from: trimmed) {
                            continuation.yield(.authURL(url))
                        }
                        if trimmed.localizedCaseInsensitiveContains("error") || trimmed.localizedCaseInsensitiveContains("fatal") {
                            capturedErrors.append(trimmed)
                        }
                        continuation.yield(.log(trimmed))
                    }
                }

                let exitCode = proc.terminationStatus
                if exitCode == 0 {
                    continuation.yield(.succeeded)
                } else {
                    let msg = capturedErrors.last ?? "Reconnect exited with code \(exitCode)"
                    continuation.yield(.failed(msg))
                }
                continuation.finish()
            }
        }

        return (eventStream, cancelHandler)
    }
}
