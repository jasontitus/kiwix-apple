// This file is part of Kiwix for iOS & macOS.
// SPDX-License-Identifier: GPL-3.0-or-later

import Combine
import CoreData
import CryptoKit
import XCTest
@testable import Kiwix

@MainActor
final class StreetZimViewModelTests: XCTestCase {
    func testCancelledTransferCannotOverwriteNextOperationsProgress() async throws {
        let fixture = try MapFixture()
        defer { fixture.remove() }
        let reader = HeldMapReader()
        let model = try fixture.model { _, _, _, _, _, progress in
            try await reader.read(progress: progress)
        }
        var subscriptions = Set<AnyCancellable>()
        let firstStarted = expectation(description: "First transfer started")
        await reader.setStarted { firstStarted.fulfill() }
        model.start()
        await fulfillment(of: [firstStarted], timeout: 5)
        let firstCallback = await reader.latestProgress()
        let firstProgress = try XCTUnwrap(firstCallback)
        let firstVisible = expectation(description: "Incoming bytes visible")
        model.$transferProgress.filter { $0?.received == 100 }.prefix(1)
            .sink { _ in firstVisible.fulfill() }.store(in: &subscriptions)
        firstProgress(100, 1_000)
        await fulfillment(of: [firstVisible], timeout: 5)
        let cancelled = expectation(description: "Cancelled operation finished")
        model.$isRunning.dropFirst().filter { !$0 }.prefix(1)
            .sink { _ in cancelled.fulfill() }.store(in: &subscriptions)
        model.cancel()
        await fulfillment(of: [cancelled], timeout: 5)

        let secondStarted = expectation(description: "Second transfer started")
        await reader.setStarted { secondStarted.fulfill() }
        model.start()
        await fulfillment(of: [secondStarted], timeout: 5)
        let secondCallback = await reader.latestProgress()
        let secondProgress = try XCTUnwrap(secondCallback)
        let currentVisible = expectation(description: "Current operation owns progress")
        model.$transferProgress.filter { $0?.received == 200 }.prefix(1)
            .sink { _ in currentVisible.fulfill() }.store(in: &subscriptions)
        secondProgress(200, 1_000)
        await fulfillment(of: [currentVisible], timeout: 5)
        let staleVisible = expectation(description: "Stale transfer must not publish")
        staleVisible.isInverted = true
        model.$transferProgress.filter { $0?.received == 999 }.prefix(1)
            .sink { _ in staleVisible.fulfill() }.store(in: &subscriptions)
        firstProgress(999, 1_000)
        await fulfillment(of: [staleVisible], timeout: 0.2)
        XCTAssertEqual(model.transferProgress?.received, 200)
        let finished = expectation(description: "Second cancellation finished")
        model.$isRunning.dropFirst().filter { !$0 }.prefix(1)
            .sink { _ in finished.fulfill() }.store(in: &subscriptions)
        model.cancel()
        await fulfillment(of: [finished], timeout: 5)
        XCTAssertNil(model.completedID)
        XCTAssertEqual(try fixture.database.viewContext.count(for: ZimFile.fetchRequest()), 0)
    }

    func testCancellationAfterPublicationStillImportsVerifiedMap() async throws {
        let fixture = try MapFixture()
        defer { fixture.remove() }
        let bytes = fixture.bytes
        let model = try fixture.model { _, offset, length, _, _, progress in
            progress?(length, length)
            return bytes.subdata(in: Int(offset)..<Int(offset + length))
        }
        let finished = expectation(description: "Published map imported")
        var subscriptions = Set<AnyCancellable>()
        model.$written.filter { $0 == Int64(bytes.count) }.prefix(1)
            .sink { _ in model.cancel() }.store(in: &subscriptions)
        model.$isRunning.dropFirst().filter { !$0 }.prefix(1)
            .sink { _ in finished.fulfill() }.store(in: &subscriptions)
        model.start()
        await fulfillment(of: [finished], timeout: 10)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.completedID, fixture.id)
        let maps = try fixture.database.viewContext.fetch(
            ZimFile.fetchRequest(predicate: ZimFile.downloadedMapsPredicate())
        )
        XCTAssertEqual(maps.map(\.fileID), [fixture.id])
        let page = await ZimFileService.shared.getMainPageURL(zimFileID: fixture.id)
        XCTAssertTrue(page?.path.hasSuffix("index.html") == true)
        await ZimFileService.shared.close(fileID: fixture.id)
    }

    func testDamagedInstalledMapIsRebuiltWithoutOverwritingTheDamagedFile() async throws {
        let fixture = try MapFixture()
        defer { fixture.remove() }
        let damaged = fixture.directory.appendingPathComponent("damaged.zim")
        try fixture.bytes.write(to: damaged)
        let imported = await LibraryOperations.open(url: damaged, database: fixture.database)
        let metadata = try XCTUnwrap(imported)
        addTeardownBlock { await ZimFileService.shared.close(fileID: metadata.fileID) }
        let row = try XCTUnwrap(fixture.database.viewContext.fetch(
            ZimFile.fetchRequest(predicate: ZimFile.Predicate.isDownloaded())
        ).first)
        let bookmark = try XCTUnwrap(row.fileURLBookmark)
        await ZimFileService.shared.close(fileID: metadata.fileID)
        let invalidBytes = Data([0])
        try invalidBytes.write(to: damaged)
        try await ZimFileService.shared.revalidate(fileURLBookmark: bookmark, for: metadata.fileID)

        let bytes = fixture.bytes
        let model = try fixture.model { _, offset, length, _, _, progress in
            progress?(length, length)
            return bytes.subdata(in: Int(offset)..<Int(offset + length))
        }
        let finished = expectation(description: "Damaged installed map rebuilt")
        var subscriptions = Set<AnyCancellable>()
        model.$isRunning.dropFirst().filter { !$0 }.prefix(1)
            .sink { _ in finished.fulfill() }.store(in: &subscriptions)
        model.start()
        await fulfillment(of: [finished], timeout: 10)

        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.completedID, fixture.id)
        let restoredURL = await ZimFileService.shared.getFileURL(zimFileID: fixture.id)
        let restored = try XCTUnwrap(restoredURL)
        XCTAssertNotEqual(restored, damaged)
        XCTAssertEqual(try Data(contentsOf: restored), bytes)
        XCTAssertEqual(try Data(contentsOf: damaged), invalidBytes)
        let maps = try fixture.database.viewContext.fetch(
            ZimFile.fetchRequest(predicate: ZimFile.downloadedMapsPredicate())
        )
        XCTAssertEqual(maps.map(\.fileID), [fixture.id])
    }
}

private actor HeldMapReader {
    private var started: (@Sendable () -> Void)?
    private var progress: (@Sendable (Int64, Int64) -> Void)?

    func setStarted(_ started: @escaping @Sendable () -> Void) { self.started = started }
    func latestProgress() -> (@Sendable (Int64, Int64) -> Void)? { progress }

    func read(progress: (@Sendable (Int64, Int64) -> Void)?) async throws -> Data {
        self.progress = progress
        started?()
        try await Task.sleep(for: .seconds(60))
        throw URLError(.timedOut)
    }
}

@MainActor
private final class MapFixture {
    let directory: URL
    let bytes: Data
    let id = UUID()
    let database: Database
    private let session: URLSession
    private let endpoint: StreetZimEndpoint
    private let catalog: StreetZimCatalog

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = try XCTUnwrap(Bundle(for: StreetZimViewModelTests.self)
            .url(forResource: "streetzim-demo", withExtension: "zim"))
        var data = try Data(contentsOf: url)
        var uuid = id.uuid
        withUnsafeBytes(of: &uuid) { data.replaceSubrange(8..<24, with: $0) }
        let digest = Data(Insecure.MD5.hash(data: data.dropLast(16)))
        data.replaceSubrange((data.count - 16)..<data.count, with: digest)
        bytes = data
        let md5 = StreetZimRecipe.hex(digest)
        let host = "map-\(id.uuidString.lowercased()).invalid"
        endpoint = StreetZimEndpoint(
            indexURL: URL(string: "https://\(host)/build/recipes/index.json")!,
            proxyURL: URL(string: "https://\(host)")!
        )
        let source: [String: Any] = [
            "file": "base.zim", "size": data.count, "uuid": id.uuidString,
            "chunk": data.count, "sha256": [StreetZimRecipe.sha256(data)]
        ]
        let recipe: [String: Any] = [
            "format": "streetzim-recipe/2", "uuid": id.uuidString, "name": "osm_en_testland",
            "size": data.count, "md5": md5, "base": source, "packs": [:],
            "segments": [["src": "base", "off": 0, "len": data.count - 16], ["src": "md5"]]
        ]
        RecipeProtocol.responses.set(try JSONSerialization.data(withJSONObject: recipe), host: host)
        let document: [String: Any] = [
            "format": "streetzim-build-index/1", "regions": [[
                "id": "testland", "title": "Testland",
                "base": ["file": "base.zim", "size": data.count, "download": "https://\(host)/base.zim"],
                "menu": [["lang": "en", "label": "English", "name": "osm_en_testland",
                          "recipe": "recipes/testland/en.json", "size": data.count,
                          "download_bytes": data.count, "md5": md5]]
            ]]
        ]
        catalog = try JSONDecoder().decode(
            StreetZimCatalog.self, from: JSONSerialization.data(withJSONObject: document)
        )
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RecipeProtocol.self]
        session = URLSession(configuration: config)
        // Reuse the app's model so entity-to-class lookup is unambiguous even
        // when this fixture is the first test to open a separate store.
        _ = Database.shared
        database = try Database(
            storeURL: directory.appendingPathComponent("library.sqlite"),
            model: ZimFile.entity().managedObjectModel
        )
    }

    func model(readRange: @escaping StreetZimViewModel.RangeReader) throws -> StreetZimViewModel {
        let model = StreetZimViewModel(
            endpoint: endpoint, session: session, cache: directory.appendingPathComponent("cache"),
            destination: directory, database: database, readRange: readRange
        )
        try model.setCatalog(catalog)
        return model
    }

    func remove() {
        session.invalidateAndCancel()
        RecipeProtocol.responses.set(nil, host: endpoint.indexURL.host!)
        try? database.close()
        try? FileManager.default.removeItem(at: directory)
    }
}

private final class RecipeProtocol: URLProtocol, @unchecked Sendable {
    static let responses = RecipeResponses()
    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host?.hasPrefix("map-") == true
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url, let body = Self.responses.get(host: url.host!) else {
            client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable))
            return
        }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Length": String(body.count)])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}

private final class RecipeResponses: @unchecked Sendable {
    private let lock = NSLock()
    private var data: [String: Data] = [:]
    func set(_ value: Data?, host: String) {
        lock.lock()
        data[host] = value
        lock.unlock()
    }
    func get(host: String) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return data[host]
    }
}
