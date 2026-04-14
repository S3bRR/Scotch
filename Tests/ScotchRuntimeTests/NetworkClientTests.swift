import Foundation
import Testing
@testable import ScotchInfrastructure

@Suite(.serialized)
struct NetworkClientTests {
    private func makeClient(retry: RetryPolicy = .default) -> DefaultNetworkClient {
        let session = URLSession(configuration: StubURLProtocol.sessionConfig())
        return DefaultNetworkClient(session: session, userAgent: "ScotchTest", retry: retry)
    }

    @Test func success200ReturnsData() async throws {
        let url = URL(string: "https://stub.test/success")!
        StubURLProtocol.register(for: url, responses: [.ok("hello")])
        defer { StubURLProtocol.reset() }

        let client = makeClient()
        let data = try await client.data(for: NetworkRequest(url: url))
        #expect(String(data: data, encoding: .utf8) == "hello")
        #expect(StubURLProtocol.attemptCount(for: url) == 1)
    }

    @Test func retriesOn500UntilSuccess() async throws {
        let url = URL(string: "https://stub.test/transient")!
        StubURLProtocol.register(
            for: url,
            responses: [.status(500), .status(500), .ok("recovered")]
        )
        defer { StubURLProtocol.reset() }

        let policy = RetryPolicy(maxAttempts: 3, backoff: { _ in .milliseconds(10) })
        let client = makeClient(retry: policy)
        let data = try await client.data(for: NetworkRequest(url: url))
        #expect(String(data: data, encoding: .utf8) == "recovered")
        #expect(StubURLProtocol.attemptCount(for: url) == 3)
    }

    @Test func givesUpAfterMaxAttempts() async throws {
        let url = URL(string: "https://stub.test/always500")!
        StubURLProtocol.register(
            for: url,
            responses: [.status(500), .status(500), .status(500)]
        )
        defer { StubURLProtocol.reset() }

        let policy = RetryPolicy(maxAttempts: 3, backoff: { _ in .milliseconds(10) })
        let client = makeClient(retry: policy)
        do {
            _ = try await client.data(for: NetworkRequest(url: url))
            Issue.record("expected failure")
        } catch let NetworkClientError.exhaustedRetries(_, attempts, _) {
            #expect(attempts == 3)
        } catch {
            Issue.record("wrong error: \(error)")
        }
        #expect(StubURLProtocol.attemptCount(for: url) == 3)
    }

    @Test func nonRetryable404FailsImmediately() async throws {
        let url = URL(string: "https://stub.test/missing")!
        StubURLProtocol.register(for: url, responses: [.status(404)])
        defer { StubURLProtocol.reset() }

        let policy = RetryPolicy(maxAttempts: 3, backoff: { _ in .milliseconds(10) })
        let client = makeClient(retry: policy)
        do {
            _ = try await client.data(for: NetworkRequest(url: url))
            Issue.record("expected failure")
        } catch let NetworkClientError.nonSuccessStatus(_, status) {
            #expect(status == 404)
        } catch {
            Issue.record("wrong error: \(error)")
        }
        #expect(StubURLProtocol.attemptCount(for: url) == 1)
    }

    @Test func userAgentAppliedByDefault() async throws {
        let url = URL(string: "https://stub.test/agent")!
        StubURLProtocol.register(for: url, responses: [.ok("")])
        defer { StubURLProtocol.reset() }

        let client = makeClient()
        _ = try await client.data(for: NetworkRequest(url: url))
        let captured = StubURLProtocol.lastRequest(for: url)
        #expect(captured?.value(forHTTPHeaderField: "User-Agent") == "ScotchTest")
    }

    @Test func customHeadersOverrideDefaults() async throws {
        let url = URL(string: "https://stub.test/override")!
        StubURLProtocol.register(for: url, responses: [.ok("")])
        defer { StubURLProtocol.reset() }

        let client = makeClient()
        _ = try await client.data(for: NetworkRequest(
            url: url,
            headers: ["User-Agent": "Override/2.0", "Accept": "application/json"]
        ))
        let captured = StubURLProtocol.lastRequest(for: url)
        #expect(captured?.value(forHTTPHeaderField: "User-Agent") == "Override/2.0")
        #expect(captured?.value(forHTTPHeaderField: "Accept") == "application/json")
    }

    @Test func perRequestTimeoutIsApplied() async throws {
        let url = URL(string: "https://stub.test/timeout")!
        StubURLProtocol.register(for: url, responses: [.ok("")])
        defer { StubURLProtocol.reset() }

        let client = makeClient()
        _ = try await client.data(for: NetworkRequest(url: url, timeout: 7.5))
        let captured = StubURLProtocol.lastRequest(for: url)
        #expect(captured?.timeoutInterval == 7.5)
    }

    @Test func downloadReturnsTempFileURL() async throws {
        let url = URL(string: "https://stub.test/file.bin")!
        StubURLProtocol.register(for: url, responses: [.ok("payload")])
        defer { StubURLProtocol.reset() }

        let client = makeClient()
        let tempURL = try await client.download(from: NetworkRequest(url: url))
        defer { try? FileManager.default.removeItem(at: tempURL) }
        let payload = try Data(contentsOf: tempURL)
        #expect(String(data: payload, encoding: .utf8) == "payload")
    }

    @Test func downloadCleansTempFileOnNonSuccess() async throws {
        let url = URL(string: "https://stub.test/bad.bin")!
        StubURLProtocol.register(for: url, responses: [.status(404, Data("nope".utf8))])
        defer { StubURLProtocol.reset() }

        let policy = RetryPolicy(maxAttempts: 1, backoff: { _ in .zero })
        let client = makeClient(retry: policy)
        do {
            _ = try await client.download(from: NetworkRequest(url: url))
            Issue.record("expected failure")
        } catch is NetworkClientError {
            // expected
        } catch {
            Issue.record("wrong error: \(error)")
        }
    }
}
