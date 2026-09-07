import Foundation
import ScotchDomain

public enum ProcessEvent: Sendable {
    case started
    case output(String)
    case error(String)
    case terminated(Int32)
    case timedOut(elapsed: TimeInterval)
}

public enum ProcessRunnerError: LocalizedError, Sendable {
    case missingTerminationStatus(String)
    case nonZeroExit(displayName: String, status: Int32, output: String)
    case timeout(displayName: String, elapsed: TimeInterval)

    public var errorDescription: String? {
        switch self {
        case .missingTerminationStatus(let displayName):
            return "Process \(displayName) finished without a termination status."
        case .nonZeroExit(let displayName, let status, let output):
            if output.isEmpty {
                return "Process \(displayName) exited with status \(status)."
            }
            return "Process \(displayName) exited with status \(status): \(output)"
        case .timeout(let displayName, let elapsed):
            return "Process \(displayName) timed out after \(String(format: "%.1f", elapsed))s."
        }
    }
}

public struct ProcessSpecification: Sendable {
    public let executableURL: URL
    public let arguments: [String]
    public let currentDirectoryURL: URL?
    public let environment: [String: String]
    public let displayName: String
    public let timeout: TimeInterval?

    public init(
        executableURL: URL,
        arguments: [String] = [],
        currentDirectoryURL: URL? = nil,
        environment: [String: String] = [:],
        displayName: String,
        timeout: TimeInterval? = nil
    ) {
        self.executableURL = executableURL
        self.arguments = arguments
        self.currentDirectoryURL = currentDirectoryURL
        self.environment = environment
        self.displayName = displayName
        self.timeout = timeout
    }
}

public protocol ProcessRunner: Sendable {
    func streamProcess(_ specification: ProcessSpecification, outputFileHandle: FileHandle?) throws -> AsyncStream<ProcessEvent>
    func captureProcess(_ specification: ProcessSpecification, outputFileHandle: FileHandle?) async throws -> String
}

// `@unchecked Sendable`: this type owns no mutable state. Every `streamProcess` call
// creates a fresh `Process` + `Pipe` pair whose lifetimes are bounded by the returned
// `AsyncStream`. Termination handlers nil out readability handlers before finishing the
// stream continuation, so the only cross-thread mutation flows through
// `AsyncStream.Continuation`, which is itself `Sendable`.
public final class DefaultProcessRunner: ProcessRunner, @unchecked Sendable {
    public init() {}

    public func streamProcess(_ specification: ProcessSpecification, outputFileHandle: FileHandle?) throws -> AsyncStream<ProcessEvent> {
        let process = Process()
        process.executableURL = specification.executableURL
        process.arguments = specification.arguments
        process.currentDirectoryURL = specification.currentDirectoryURL ?? specification.executableURL.deletingLastPathComponent()
        process.environment = Self.mergedEnvironment(specification.environment)
        process.qualityOfService = .userInitiated

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        let timeout = specification.timeout

        return AsyncStream { continuation in
            stdout.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let string = String(data: data, encoding: .utf8) else { return }
                outputFileHandle?.write(line: string)
                continuation.yield(.output(string))
            }

            stderr.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let string = String(data: data, encoding: .utf8) else { return }
                outputFileHandle?.write(line: string)
                continuation.yield(.error(string))
            }

            process.terminationHandler = { terminated in
                let stdoutHandle = stdout.fileHandleForReading
                let stderrHandle = stderr.fileHandleForReading
                stdoutHandle.readabilityHandler = nil
                stderrHandle.readabilityHandler = nil

                // Drain any final buffered output without blocking. After a normal exit the
                // pipe is at EOF and the read returns 0 immediately; after SIGKILL the OS
                // may not have closed the writer FD yet, so non-blocking mode prevents us
                // from hanging here while still grabbing whatever is already buffered.
                Self.drainNonBlocking(handle: stdoutHandle) { string in
                    outputFileHandle?.write(line: string)
                    continuation.yield(.output(string))
                }
                Self.drainNonBlocking(handle: stderrHandle) { string in
                    outputFileHandle?.write(line: string)
                    continuation.yield(.error(string))
                }

                continuation.yield(.terminated(terminated.terminationStatus))
                continuation.finish()
            }

            do {
                try process.run()
                continuation.yield(.started)

                if let timeout {
                    Self.scheduleTimeout(timeout, on: process, continuation: continuation)
                }
            } catch {
                continuation.yield(.error("Failed to run \(specification.displayName): \(error.localizedDescription)"))
                continuation.yield(.terminated(-1))
                continuation.finish()
            }
        }
    }

    private static func drainNonBlocking(handle: FileHandle, yield: (String) -> Void) {
        let fd = handle.fileDescriptor
        let oldFlags = fcntl(fd, F_GETFL, 0)
        guard oldFlags != -1 else { return }
        _ = fcntl(fd, F_SETFL, oldFlags | O_NONBLOCK)
        defer { _ = fcntl(fd, F_SETFL, oldFlags) }

        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let bytesRead = buffer.withUnsafeMutableBufferPointer { ptr -> Int in
                Darwin.read(fd, ptr.baseAddress, ptr.count)
            }
            if bytesRead > 0 {
                let data = Data(buffer[0..<bytesRead])
                if let string = String(data: data, encoding: .utf8) {
                    yield(string)
                }
            } else {
                break
            }
        }
    }

    private static func scheduleTimeout(
        _ timeout: TimeInterval,
        on process: Process,
        continuation: AsyncStream<ProcessEvent>.Continuation
    ) {
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + timeout) { [weak process] in
            guard let process, process.isRunning else { return }
            continuation.yield(.timedOut(elapsed: timeout))
            process.terminate()
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 3) { [weak process] in
                guard let process, process.isRunning else { return }
                kill(process.processIdentifier, SIGKILL)
            }
        }
    }

    private static func mergedEnvironment(_ overrides: [String: String]) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment.merge(overrides, uniquingKeysWith: { _, new in new })
        return environment
    }

    public func captureProcess(_ specification: ProcessSpecification, outputFileHandle: FileHandle?) async throws -> String {
        var collected = ""
        var status: Int32?
        var timedOutAfter: TimeInterval?
        for await event in try streamProcess(specification, outputFileHandle: outputFileHandle) {
            switch event {
            case .output(let line), .error(let line):
                collected += line
            case .terminated(let terminationStatus):
                status = terminationStatus
            case .timedOut(let elapsed):
                timedOutAfter = elapsed
            case .started:
                break
            }
        }

        if let timedOutAfter {
            throw ProcessRunnerError.timeout(displayName: specification.displayName, elapsed: timedOutAfter)
        }
        guard let status else {
            throw ProcessRunnerError.missingTerminationStatus(specification.displayName)
        }
        guard status == 0 else {
            let trimmed = collected.trimmingCharacters(in: .whitespacesAndNewlines)
            throw ProcessRunnerError.nonZeroExit(displayName: specification.displayName, status: status, output: trimmed)
        }
        return collected
    }
}

private extension FileHandle {
    func write(line: String) {
        guard let data = line.data(using: .utf8) else { return }
        do {
            try write(contentsOf: data)
        } catch {
            return
        }
    }
}

