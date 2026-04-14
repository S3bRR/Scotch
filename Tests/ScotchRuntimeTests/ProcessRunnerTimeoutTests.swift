import Foundation
import Testing
@testable import ScotchInfrastructure

struct ProcessRunnerTimeoutTests {
    @Test func timeoutTerminatesSleep() async throws {
        let runner = DefaultProcessRunner()
        let spec = ProcessSpecification(
            executableURL: URL(fileURLWithPath: "/bin/sleep"),
            arguments: ["10"],
            displayName: "sleep-timeout",
            timeout: 0.5
        )
        let start = Date()
        do {
            _ = try await runner.captureProcess(spec, outputFileHandle: nil)
            Issue.record("expected timeout but capture succeeded")
        } catch let ProcessRunnerError.timeout(displayName, elapsed) {
            #expect(displayName == "sleep-timeout")
            #expect(elapsed == 0.5)
        } catch {
            Issue.record("wrong error: \(error)")
        }
        let wall = Date().timeIntervalSince(start)
        #expect(wall < 2.0, "wall clock \(wall)s — timeout did not fire promptly")
    }

    @Test func noTimeoutAllowsSuccessfulRun() async throws {
        let runner = DefaultProcessRunner()
        let spec = ProcessSpecification(
            executableURL: URL(fileURLWithPath: "/bin/echo"),
            arguments: ["hello-world"],
            displayName: "echo-no-timeout",
            timeout: nil
        )
        let output = try await runner.captureProcess(spec, outputFileHandle: nil)
        #expect(output.contains("hello-world"))
    }

    @Test func sigkillEscalationFiresWhenTermIgnored() async throws {
        let runner = DefaultProcessRunner()
        let spec = ProcessSpecification(
            executableURL: URL(fileURLWithPath: "/bin/bash"),
            arguments: ["-c", "trap '' TERM; sleep 30"],
            displayName: "bash-trap-term",
            timeout: 0.5
        )
        let start = Date()
        do {
            _ = try await runner.captureProcess(spec, outputFileHandle: nil)
            Issue.record("expected timeout but capture succeeded")
        } catch ProcessRunnerError.timeout {
            // SIGTERM at t=0.5, SIGKILL at t=3.5 (3s grace), allow 6s ceiling.
            let wall = Date().timeIntervalSince(start)
            #expect(wall < 6.0, "SIGKILL escalation took \(wall)s")
        } catch {
            Issue.record("wrong error: \(error)")
        }
    }

    @Test func processCompletesNormallyBeforeTimeoutDoesNotThrow() async throws {
        let runner = DefaultProcessRunner()
        let spec = ProcessSpecification(
            executableURL: URL(fileURLWithPath: "/bin/echo"),
            arguments: ["fast"],
            displayName: "echo-fast",
            timeout: 5.0
        )
        let output = try await runner.captureProcess(spec, outputFileHandle: nil)
        #expect(output.contains("fast"))
    }
}
