import Foundation

public enum SyncEvent: Sendable {
    case started(Date)
    case progress(SyncProgress)
    case log(String)
    case conflictDetected(String)
    case completed(SyncReport)
    case failed(String)
}

/// The core engine responsible for executing rclone sync and bisync tasks with real-time streaming.
public final class RcloneEngine: Sendable {
    private let discovery: RcloneDiscovery
    private let runner: ProcessRunner

    public init(
        discovery: RcloneDiscovery = RcloneDiscovery(),
        runner: ProcessRunner = ProcessRunner()
    ) {
        self.discovery = discovery
        self.runner = runner
    }

    /// Builds command-line arguments for the given profile and options.
    public func buildArguments(
        for profile: SyncProfile,
        isDryRun: Bool = false,
        forceResync: Bool = false
    ) -> [String] {
        var args: [String] = []

        switch profile.direction {
        case .bidirectional:
            args.append("bisync")
            args.append(profile.localPath)
            args.append(profile.fullRemotePath)

            // Safe conflict resolution with conflict copies
            args.append(contentsOf: [
                "--conflict-resolve", "newer",
                "--conflict-loser", "pathname",
                "--conflict-suffix", "sync-conflict"
            ])

            // If not yet initialized or forced, run --resync
            if !profile.isBisyncInitialized || forceResync {
                args.append("--resync")
            }

        case .push:
            args.append("sync")
            args.append(profile.localPath)
            args.append(profile.fullRemotePath)

        case .pull:
            args.append("sync")
            args.append(profile.fullRemotePath)
            args.append(profile.localPath)
        }

        // Exclusions
        let excludes = ExcludePreset.resolveExcludePatterns(
            includeDeveloper: profile.isDeveloperPresetEnabled,
            includeSystem: profile.isSystemPresetEnabled,
            customRules: profile.customExcludes
        )
        for rule in excludes {
            args.append(contentsOf: ["--exclude", rule])
        }

        // Real-time progress and logging flags
        args.append(contentsOf: [
            "--stats", "1s",
            "--use-json-log",
            "--stats-log-level", "INFO",
            "-v"
        ])

        if isDryRun {
            args.append("--dry-run")
        }

        return args
    }

    /// Executes the sync process and yields real-time streaming events.
    public func execute(
        profile: SyncProfile,
        customBinaryPath: String? = nil,
        isDryRun: Bool = false,
        forceResync: Bool = false
    ) -> (stream: AsyncStream<SyncEvent>, cancel: @Sendable () -> Void) {
        let (rawStream, processRef) = self.prepareProcess(
            profile: profile,
            customBinaryPath: customBinaryPath,
            isDryRun: isDryRun,
            forceResync: forceResync
        )

        let cancelHandler: @Sendable () -> Void = {
            if let proc = processRef.process, proc.isRunning {
                proc.terminate()
            }
        }

        let eventStream = AsyncStream<SyncEvent> { continuation in
            Task {
                continuation.yield(.started(Date()))
                let startTime = Date()
                var fullLogs: [String] = []
                var conflictFiles: [String] = []
                let transferredCount = 0
                let deletedCount = 0

                for await line in rawStream {
                    let text: String
                    switch line {
                    case .stdout(let str): text = str
                    case .stderr(let str): text = str
                    }

                    let lines = text.components(separatedBy: .newlines)
                    for singleLine in lines {
                        let trimmed = singleLine.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { continue }
                        fullLogs.append(trimmed)

                        // Check for conflict mentions
                        if trimmed.localizedCaseInsensitiveContains("conflict") &&
                            trimmed.localizedCaseInsensitiveContains("renam") {
                            conflictFiles.append(trimmed)
                            continuation.yield(.conflictDetected(trimmed))
                        }

                        // Try parsing JSON log from rclone
                        if let progress = parseJsonLog(line: trimmed) {
                            continuation.yield(.progress(progress))
                        } else {
                            continuation.yield(.log(trimmed))
                        }
                    }
                }

                // Process terminated
                let endTime = Date()
                let exitCode = processRef.process?.terminationStatus ?? -1
                let status: SyncStatus
                if exitCode == 0 {
                    status = conflictFiles.isEmpty ? .success : .conflict
                } else {
                    status = .failed
                }

                let report = SyncReport(
                    profileId: profile.id,
                    startTime: startTime,
                    endTime: endTime,
                    status: status,
                    exitCode: exitCode,
                    transferredFilesCount: transferredCount,
                    deletedFilesCount: deletedCount,
                    conflictFiles: conflictFiles,
                    logSummary: fullLogs.suffix(100).joined(separator: "\n")
                )

                if status == .failed {
                    continuation.yield(.failed("Process exited with code \(exitCode)"))
                }
                continuation.yield(.completed(report))
                continuation.finish()
            }
        }

        return (eventStream, cancelHandler)
    }

    private final class ProcessReference: @unchecked Sendable {
        var process: Process?
    }

    private func prepareProcess(
        profile: SyncProfile,
        customBinaryPath: String?,
        isDryRun: Bool,
        forceResync: Bool
    ) -> (AsyncStream<ProcessOutputLine>, ProcessReference) {
        let binaryURL = discovery.locateBinary(customPath: customBinaryPath) ?? URL(fileURLWithPath: "/usr/local/bin/rclone")
        let args = buildArguments(for: profile, isDryRun: isDryRun, forceResync: forceResync)

        let (stream, proc) = runner.stream(
            executableURL: binaryURL,
            arguments: args
        )

        let ref = ProcessReference()
        ref.process = proc
        return (stream, ref)
    }

    private func parseJsonLog(line: String) -> SyncProgress? {
        guard line.hasPrefix("{") && line.hasSuffix("}"),
              let data = line.data(using: .utf8) else {
            return nil
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        // rclone stats object
        if let stats = json["stats"] as? [String: Any] {
            let bytes = (stats["bytes"] as? NSNumber)?.int64Value ?? 0
            let totalBytes = (stats["totalBytes"] as? NSNumber)?.int64Value ?? 0
            let speed = (stats["speed"] as? NSNumber)?.doubleValue ?? 0.0
            let transfers = (stats["transfers"] as? NSNumber)?.intValue ?? 0
            let totalTransfers = (stats["totalTransfers"] as? NSNumber)?.intValue ?? 0
            let percentage: Double = totalBytes > 0 ? (Double(bytes) / Double(totalBytes)) * 100.0 : 0.0

            let speedFormatted = formatBytesPerSec(speed)

            return SyncProgress(
                bytesTransferred: bytes,
                totalBytes: totalBytes,
                percentage: percentage,
                currentFile: nil,
                transferSpeed: speedFormatted,
                eta: nil,
                filesTransferred: transfers,
                totalFiles: totalTransfers,
                rawLog: line
            )
        }

        // rclone transfer entry
        if let object = json["object"] as? String {
            return SyncProgress(
                bytesTransferred: 0,
                totalBytes: 0,
                percentage: 0,
                currentFile: object,
                transferSpeed: nil,
                eta: nil,
                filesTransferred: 0,
                totalFiles: 0,
                rawLog: line
            )
        }

        return nil
    }

    private func formatBytesPerSec(_ bytesPerSec: Double) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return "\(formatter.string(fromByteCount: Int64(bytesPerSec)))/s"
    }
}
