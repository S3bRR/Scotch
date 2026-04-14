import Foundation

/// URLProtocol stub for unit-testing `DefaultNetworkClient` without real network I/O.
/// Register a queue of canned responses per URL; each request consumes the front of the queue.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    indirect enum Response: @unchecked Sendable {
        case ok(Data)
        case status(Int, Data)
        case delay(TimeInterval, then: Response)

        static func ok(_ string: String) -> Response { .ok(Data(string.utf8)) }
        static func status(_ code: Int) -> Response { .status(code, Data()) }
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var responseQueues: [URL: [Response]] = [:]
    nonisolated(unsafe) private static var capturedRequests: [URL: [URLRequest]] = [:]

    static func register(for url: URL, responses: [Response]) {
        lock.lock(); defer { lock.unlock() }
        responseQueues[url] = responses
        capturedRequests[url] = []
    }

    static func attemptCount(for url: URL) -> Int {
        lock.lock(); defer { lock.unlock() }
        return capturedRequests[url]?.count ?? 0
    }

    static func lastRequest(for url: URL) -> URLRequest? {
        lock.lock(); defer { lock.unlock() }
        return capturedRequests[url]?.last
    }

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        responseQueues = [:]
        capturedRequests = [:]
    }

    static func sessionConfig() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 10
        return config
    }

    private var workItem: DispatchWorkItem?
    private var stopped = false

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        Self.lock.lock()
        Self.capturedRequests[url, default: []].append(request)
        let response: Response?
        if var queue = Self.responseQueues[url], !queue.isEmpty {
            response = queue.removeFirst()
            Self.responseQueues[url] = queue
        } else {
            response = nil
        }
        Self.lock.unlock()

        guard let response else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        emit(response, for: url)
    }

    override func stopLoading() {
        stopped = true
        workItem?.cancel()
    }

    private func emit(_ response: Response, for url: URL) {
        guard !stopped else { return }
        switch response {
        case .ok(let data):
            sendResponse(statusCode: 200, data: data, url: url)
        case .status(let code, let data):
            sendResponse(statusCode: code, data: data, url: url)
        case .delay(let seconds, let then):
            let item = DispatchWorkItem { [weak self] in
                self?.emit(then, for: url)
            }
            self.workItem = item
            DispatchQueue.global().asyncAfter(deadline: .now() + seconds, execute: item)
        }
    }

    private func sendResponse(statusCode: Int, data: Data, url: URL) {
        guard !stopped else { return }
        let http = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/octet-stream"]
        )!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
}
