// This file is part of Kiwix for iOS & macOS.
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import XCTest
@testable import Kiwix

final class StreetZimHTTPTests: XCTestCase, @unchecked Sendable {
    func testValidRangeWithKnownOrUnknownLength() async throws {
        for path in ["valid", "chunked"] {
            let session = session()
            defer { session.invalidateAndCancel() }
            let data = try await StreetZimHTTP.range(url(path), offset: 10, length: 4, size: 20,
                                                     cellular: false, session: session)
            XCTAssertEqual(data, Data([1, 2, 3, 4]))
        }
    }

    func testIgnoredRangeWrongRangeAndTruncatedOrOversizedBodiesAreRejected() async throws {
        for path in ["ignored", "wrong-range", "truncated", "oversized"] {
            let session = session()
            defer { session.invalidateAndCancel() }
            do {
                _ = try await StreetZimHTTP.range(url(path), offset: 10, length: 4, size: 20,
                                                    cellular: false, session: session)
                XCTFail("Should reject \(path)")
            } catch StreetZimError.invalidResponse { }
        }
    }

    func testOversizedJSONIsRejected() async throws {
        let session = session()
        defer { session.invalidateAndCancel() }
        do {
            _ = try await StreetZimHTTP.json(url("big-json"), as: StreetZimCatalog.self, session: session)
            XCTFail("Should reject oversized JSON")
        } catch StreetZimError.invalidRecipe { }
    }

    func testCancellationBeforeStarting() async throws {
        let session = session()
        defer { session.invalidateAndCancel() }
        let requestURL = url("held")
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await StreetZimHTTP.range(requestURL, offset: 10, length: 4, size: 20,
                                                   cellular: false, session: session)
        }
        do {
            _ = try await task.value
            XCTFail("Should be cancelled before starting")
        } catch is CancellationError { }
    }

    func testCancellationStopsAnActiveRequest() async throws {
        let started = expectation(description: "Request started")
        let stopped = expectation(description: "Request stopped")
        MapProtocol.events.set(started: { started.fulfill() }, stopped: { stopped.fulfill() })
        defer { MapProtocol.events.set(started: nil, stopped: nil) }
        let session = session()
        defer { session.invalidateAndCancel() }
        let requestURL = url("held")
        let task = Task {
            try await StreetZimHTTP.range(requestURL, offset: 10, length: 4, size: 20,
                                            cellular: false, session: session)
        }
        await fulfillment(of: [started], timeout: 2)
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Should be cancelled")
        } catch is CancellationError { }
        await fulfillment(of: [stopped], timeout: 2)
    }

    private func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MapProtocol.self]
        return URLSession(configuration: config)
    }

    private func url(_ path: String) -> URL { URL(string: "https://streetzim-tests.invalid/" + path)! }
}

private final class MapProtocol: URLProtocol, @unchecked Sendable {
    static let events = RequestEvents()

    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "streetzim-tests.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        let path = url.lastPathComponent
        if path == "held" {
            Self.events.started()
            return
        }
        var body = Data([1, 2, 3, 4])
        var headers = ["Content-Range": "bytes 10-13/20"]
        var status = 206
        switch path {
        case "ignored": status = 200
        case "wrong-range": headers["Content-Range"] = "bytes 0-3/20"
        case "truncated": body.removeLast()
        case "oversized": body.append(5)
        case "big-json":
            status = 200
            body = Data(repeating: 32, count: 32 * 1024 * 1024 + 1)
        default: break
        }
        if path != "chunked" { headers["Content-Length"] = String(body.count) }
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {
        if request.url?.lastPathComponent == "held" { Self.events.stopped() }
    }
}

private final class RequestEvents: @unchecked Sendable {
    private let lock = NSLock()
    private var onStarted: (@Sendable () -> Void)?
    private var onStopped: (@Sendable () -> Void)?

    func set(started: (@Sendable () -> Void)?, stopped: (@Sendable () -> Void)?) {
        lock.lock()
        onStarted = started
        onStopped = stopped
        lock.unlock()
    }

    func started() {
        lock.lock()
        let callback = onStarted
        lock.unlock()
        callback?()
    }

    func stopped() {
        lock.lock()
        let callback = onStopped
        lock.unlock()
        callback?()
    }
}
