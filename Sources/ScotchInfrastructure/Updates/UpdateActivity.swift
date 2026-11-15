import Foundation

/// Shared by launch paths and update installers. A lease closes the race between
/// checking for a running game and starting to replace software.
public final class UpdateActivity: @unchecked Sendable {
    public static let shared = UpdateActivity()
    private let lock = NSLock()
    private var operations = 0
    private var maintenance = false
    private var maintenanceID: UUID?
    private let processCheck: @Sendable () -> Bool
    public init(processCheck: @escaping @Sendable () -> Bool = UpdateActivity.hasWineProcesses) { self.processCheck = processCheck }

    public var hasRunningWineProcesses: Bool { processCheck() }
    public var isApplyingUpdate: Bool { lock.withLock { maintenance } }
    public func beginOperation() throws -> UpdateLease {
        try lock.withLock {
            guard !maintenance else { throw UpdateActivityError.busy("An update is being installed. Try again when it finishes.") }
            operations += 1
            return UpdateLease { [self] in lock.withLock { operations -= 1 } }
        }
    }
    public func acquireMaintenance() throws -> UpdateLease {
        try lock.withLock {
            guard !maintenance, operations == 0 else {
                throw UpdateActivityError.busy("Waiting for bottle operations to finish.")
            }
            if processCheck() { throw UpdateActivityError.busy("Close running games and Wine processes before installing updates.") }
            maintenance = true
            let id = UUID()
            maintenanceID = id
            return UpdateLease(id: id) { [self] in lock.withLock {
                if maintenanceID == id { maintenance = false; maintenanceID = nil }
            } }
        }
    }
    /// Atomically protect the newly selected configuration through process
    /// launch; there is no idle gap in which another selection can replace it.
    public func beginOperation(replacing maintenanceLease: UpdateLease) throws -> UpdateLease {
        try lock.withLock {
            guard maintenance, maintenanceID == maintenanceLease.id else {
                throw UpdateActivityError.busy("The launch no longer owns bottle maintenance.")
            }
            maintenance = false; maintenanceID = nil; operations += 1
            return UpdateLease { [self] in lock.withLock { operations -= 1 } }
        }
    }
    public static func hasWineProcesses() -> Bool {
        WineProcessInspector.hasWineProcesses
    }
}
public enum UpdateActivityError: LocalizedError {
    case busy(String)
    public var errorDescription: String? { switch self { case .busy(let message): message } }
}
public final class UpdateLease: @unchecked Sendable {
    fileprivate let id: UUID
    private let release: @Sendable () -> Void
    public init(id: UUID = UUID(), release: @escaping @Sendable () -> Void) { self.id = id; self.release = release }
    deinit { release() }
}

public struct ActivityTrackingProcessRunner: ProcessRunner {
    public let underlying: ProcessRunner
    public init(_ underlying: ProcessRunner = DefaultProcessRunner()) { self.underlying = underlying }
    public func captureProcess(_ specification: ProcessSpecification, outputFileHandle: FileHandle?) async throws -> String {
        let lease = try UpdateActivity.shared.beginOperation()
        defer { withExtendedLifetime(lease) {} }
        return try await underlying.captureProcess(specification, outputFileHandle: outputFileHandle)
    }
    public func streamProcess(_ specification: ProcessSpecification, outputFileHandle: FileHandle?) throws -> AsyncStream<ProcessEvent> {
        let lease = try UpdateActivity.shared.beginOperation()
        let events = try underlying.streamProcess(specification, outputFileHandle: outputFileHandle)
        return AsyncStream { continuation in
            let task = Task {
                defer { withExtendedLifetime(lease) {} }
                for await event in events { continuation.yield(event) }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
