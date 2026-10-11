import Foundation

public enum ProcessOutputLine: Sendable {
    case stdout(String)
    case stderr(String)
}

public struct ProcessResult: Sendable {
    public let exitCode: Int32
    public let output: String
    public let errorOutput: String
}

/// Helper to execute external processes with async streaming support and cancellation.
public final class ProcessRunner: Sendable {
    public init() {}

    /// Runs a process synchronously returning the full result.
    public func run(
        executableURL: URL,
        arguments: [String],
        environment: [String: String]? = nil,
        currentDirectoryURL: URL? = nil
    ) async throws -> ProcessResult {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        if let currentDirectoryURL {
            process.currentDirectoryURL = currentDirectoryURL
        }
        if let env = environment {
            var currentEnv = ProcessInfo.processInfo.environment
            currentEnv.merge(env) { _, new in new }
            process.environment = currentEnv
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        return try await withTaskCancellationHandler {
            try process.run()
            process.waitUntilExit()

            let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

            let stdoutString = String(data: stdoutData, encoding: .utf8) ?? ""
            let stderrString = String(data: stderrData, encoding: .utf8) ?? ""

            return ProcessResult(
                exitCode: process.terminationStatus,
                output: stdoutString,
                errorOutput: stderrString
            )
        } onCancel: {
            if process.isRunning {
                process.terminate()
            }
        }
    }

    /// Runs a process yielding output lines as they arrive via an AsyncStream.
    public func stream(
        executableURL: URL,
        arguments: [String],
        environment: [String: String]? = nil,
        currentDirectoryURL: URL? = nil
    ) -> (stream: AsyncStream<ProcessOutputLine>, process: Process) {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        if let currentDirectoryURL {
            process.currentDirectoryURL = currentDirectoryURL
        }
        if let env = environment {
            var currentEnv = ProcessInfo.processInfo.environment
            currentEnv.merge(env) { _, new in new }
            process.environment = currentEnv
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stream = AsyncStream<ProcessOutputLine> { continuation in
            let stdoutHandle = stdoutPipe.fileHandleForReading
            let stderrHandle = stderrPipe.fileHandleForReading

            stdoutHandle.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                if let str = String(data: data, encoding: .utf8) {
                    continuation.yield(.stdout(str))
                }
            }

            stderrHandle.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                if let str = String(data: data, encoding: .utf8) {
                    continuation.yield(.stderr(str))
                }
            }

            process.terminationHandler = { proc in
                stdoutHandle.readabilityHandler = nil
                stderrHandle.readabilityHandler = nil
                continuation.finish()
            }

            do {
                try process.run()
            } catch {
                continuation.finish()
            }
        }

        return (stream, process)
    }
}
