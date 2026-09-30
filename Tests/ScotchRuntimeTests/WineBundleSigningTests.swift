import Foundation
import Testing
import ScotchDomain
import ScotchInfrastructure
@testable import ScotchRuntime

struct WineBundleSigningTests {
    private let bundle = URL(fileURLWithPath: "/tmp/Scotch Libraries/Wine.app")

    @Test func newWrapperIsSignedThenVerified() async throws {
        let runner = SigningProcessRunner()
        try await WineBundleSigning(processRunner: runner).signAndVerify(at: bundle)
        let calls = await runner.calls
        #expect(calls.map(\.arguments) == [signArguments, verifyArguments])
        #expect(calls.allSatisfy { $0.executableURL.path == "/usr/bin/codesign" && $0.timeout == 60 })
    }

    @Test func validWrapperIsNotResigned() async throws {
        let runner = SigningProcessRunner()
        try await WineBundleSigning(processRunner: runner).ensureSigned(at: bundle)
        #expect(await runner.calls.map(\.arguments) == [verifyArguments])
    }

    @Test func unsignedOrModifiedWrapperIsRepairedAndReverified() async throws {
        let runner = SigningProcessRunner(failingCalls: [0])
        try await WineBundleSigning(processRunner: runner).ensureSigned(at: bundle)
        #expect(await runner.calls.map(\.arguments) == [verifyArguments, signArguments, verifyArguments])
    }

    @Test func signingFailureIsReported() async {
        let runner = SigningProcessRunner(failingCalls: [0])
        await #expect(throws: RuntimeInstallerError.self) {
            try await WineBundleSigning(processRunner: runner).signAndVerify(at: bundle)
        }
        #expect(await runner.calls.count == 1)
    }

    @Test func verificationFailureAfterSigningIsReported() async {
        let runner = SigningProcessRunner(failingCalls: [0, 2])
        await #expect(throws: RuntimeInstallerError.self) {
            try await WineBundleSigning(processRunner: runner).ensureSigned(at: bundle)
        }
        #expect(await runner.calls.count == 3)
    }

    @Test func verificationTimeoutDoesNotTriggerResigning() async {
        let runner = SigningProcessRunner(timeoutCalls: [0])
        await #expect(throws: ProcessRunnerError.self) {
            try await WineBundleSigning(processRunner: runner).ensureSigned(at: bundle)
        }
        #expect(await runner.calls.count == 1)
    }

    @Test func replacingWrapperTriggersAnotherVerification() async throws {
        let runner = SigningProcessRunner(failingCalls: [1])
        let signing = WineBundleSigning(processRunner: runner)
        try await signing.ensureSigned(at: bundle)
        try await signing.ensureSigned(at: bundle)
        #expect(await runner.calls.map(\.arguments) == [verifyArguments, verifyArguments, signArguments, verifyArguments])
    }

    @Test func nativeCodesignRepairsShellLauncherBundle() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "ScotchSigningTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let wrapper = root.appending(path: "Wine.app")
        let executable = wrapper.appending(path: "Contents/MacOS/wine-launcher")
        try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "#!/bin/bash\nexit 0\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let info: [String: String] = [
            "CFBundleExecutable": "wine-launcher",
            "CFBundleIdentifier": "com.s3brr.Scotch.WineBundle",
            "CFBundlePackageType": "APPL",
            "CFBundleName": "Wine"
        ]
        let plist = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try plist.write(to: wrapper.appending(path: "Contents/Info.plist"))
        let signing = WineBundleSigning(processRunner: DefaultProcessRunner())
        try await signing.ensureSigned(at: wrapper)
        try await signing.verify(at: wrapper)
        // Changing a sealed file should cause the same repair as a runtime update.
        try "#!/bin/bash\nexit 1\n".write(to: executable, atomically: true, encoding: .utf8)
        try await signing.ensureSigned(at: wrapper)
        try await signing.verify(at: wrapper)
    }

    private var signArguments: [String] { ["--force", "--deep", "--sign", "-", bundle.path] }
    private var verifyArguments: [String] { ["--verify", "--deep", "--strict", bundle.path] }
}

private actor SigningProcessRunner: ProcessRunner {
    private(set) var calls: [ProcessSpecification] = []
    let failingCalls: Set<Int>
    let timeoutCalls: Set<Int>

    init(failingCalls: Set<Int> = [], timeoutCalls: Set<Int> = []) {
        self.failingCalls = failingCalls
        self.timeoutCalls = timeoutCalls
    }

    nonisolated func streamProcess(_ specification: ProcessSpecification, outputFileHandle: FileHandle?) throws -> AsyncStream<ProcessEvent> {
        fatalError("Tests use captureProcess")
    }

    func captureProcess(_ specification: ProcessSpecification, outputFileHandle: FileHandle?) async throws -> String {
        let index = calls.count
        calls.append(specification)
        if timeoutCalls.contains(index) {
            throw ProcessRunnerError.timeout(displayName: specification.displayName, elapsed: 60)
        }
        if failingCalls.contains(index) {
            throw ProcessRunnerError.nonZeroExit(displayName: specification.displayName, status: 1, output: "invalid signature")
        }
        return ""
    }
}
