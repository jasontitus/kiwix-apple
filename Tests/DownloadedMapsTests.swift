// This file is part of Kiwix for iOS & macOS.
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreData
import Foundation
import XCTest
@testable import Kiwix

@MainActor
final class DownloadedMapsTests: XCTestCase {
    func testImportSurvivesStoreReopenAndDoesNotDuplicate() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = try copyFixture(to: directory)
        let store = directory.appendingPathComponent("library.sqlite")
        let database = try Database(storeURL: store)
        defer { try? database.close() }
        let imported = await LibraryOperations.open(url: file, database: database)
        let metadata = try XCTUnwrap(imported)
        addTeardownBlock { await ZimFileService.shared.close(fileID: metadata.fileID) }
        let first = try XCTUnwrap(maps(in: database).first)
        XCTAssertEqual(first.fileID, metadata.fileID)
        XCTAssertEqual(first.persistentID, "osm_en_testland")
        XCTAssertEqual(first.name, "StreetZim Demo")
        let bookmark = try XCTUnwrap(first.fileURLBookmark)
        XCTAssertEqual(try resolve(bookmark).standardizedFileURL, file.standardizedFileURL)
        try database.close()

        let reopened = try Database(storeURL: store)
        defer { try? reopened.close() }
        let restored = try XCTUnwrap(maps(in: reopened).first)
        XCTAssertEqual(restored.fileID, metadata.fileID)
        XCTAssertEqual(restored.fileURLBookmark, bookmark)
        await ZimFileService.shared.close(fileID: metadata.fileID)
        try await ZimFileService.shared.revalidate(fileURLBookmark: bookmark, for: metadata.fileID)
        let mainPage = await ZimFileService.shared.getMainPageURL(zimFileID: metadata.fileID)
        XCTAssertEqual(mainPage?.zimFileID, metadata.fileID)
        XCTAssertTrue(mainPage?.path.hasSuffix("index.html") == true)

        let reimported = await LibraryOperations.open(url: file, database: reopened)
        XCTAssertEqual(reimported?.fileID, metadata.fileID)
        XCTAssertEqual(try maps(in: reopened).map(\.fileID), [metadata.fileID])
    }

    func testSQLiteFetchExcludesMissingUnlinkedAndNonMapFiles() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = try copyFixture(to: directory)
        let database = try Database(storeURL: directory.appendingPathComponent("library.sqlite"))
        defer { try? database.close() }
        let imported = await LibraryOperations.open(url: file, database: database)
        let metadata = try XCTUnwrap(imported)
        addTeardownBlock { await ZimFileService.shared.close(fileID: metadata.fileID) }
        let map = try XCTUnwrap(maps(in: database).first)
        let bookmark = map.fileURLBookmark

        map.isMissing = true
        try database.viewContext.save()
        XCTAssertEqual(try maps(in: database).count, 0)
        map.isMissing = false
        map.fileURLBookmark = nil
        try database.viewContext.save()
        XCTAssertEqual(try maps(in: database).count, 0)

        map.fileURLBookmark = bookmark
        map.category = "other"
        map.tags = "roadmaps;maps-guide"
        try database.viewContext.save()
        XCTAssertEqual(try maps(in: database).count, 0)
        map.tags = "offline;maps;osm"
        try database.viewContext.save()
        XCTAssertEqual(try maps(in: database).map(\.fileID), [metadata.fileID])
        map.tags = "offline"
        map.category = "maps"
        try database.viewContext.save()
        XCTAssertEqual(try maps(in: database).map(\.fileID), [metadata.fileID])
    }

    func testFailedSaveDoesNotExposeMapOrDiscardUnrelatedEdits() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = try copyFixture(to: directory)
        let rawMetadata = await ZimFileService.getMetaData(url: file)
        let metadata = try XCTUnwrap(rawMetadata)
        addTeardownBlock { await ZimFileService.shared.close(fileID: metadata.fileID) }
        let modelURL = try XCTUnwrap(Bundle.main.url(forResource: "DataModel", withExtension: "momd"))
        let model = try XCTUnwrap(NSManagedObjectModel(contentsOf: modelURL))
        let name = try XCTUnwrap(model.entitiesByName["ZimFile"]?.attributesByName["name"])
        name.setValidationPredicates(
            [NSPredicate(format: "SELF != %@", metadata.title)],
            withValidationWarnings: ["Reject the fixture title to exercise an actual Core Data save failure."]
        )
        let store = directory.appendingPathComponent("library.sqlite")
        let database = try Database(storeURL: store, model: model)
        defer { try? database.close() }
        let unrelated = ZimFile(context: database.viewContext)
        LibraryOperations.configureZimFile(unrelated, metadata: metadata)
        unrelated.fileID = UUID()
        unrelated.name = "Unrelated pending edit"
        unrelated.tags = ""
        unrelated.fileURLBookmark = nil

        let result = await LibraryOperations.open(url: file, database: database)
        XCTAssertNil(result)
        XCTAssertEqual(try maps(in: database).count, 0)
        XCTAssertTrue(unrelated.isInserted)
        XCTAssertEqual(unrelated.name, "Unrelated pending edit")
        try database.viewContext.save()
        let unrelatedID = unrelated.fileID
        try database.close()

        let reopened = try Database(storeURL: store, model: model)
        defer { try? reopened.close() }
        XCTAssertEqual(try maps(in: reopened).count, 0)
        XCTAssertEqual(
            try reopened.viewContext.fetch(ZimFile.fetchRequest()).map(\.fileID),
            [unrelatedID]
        )
    }

    private func maps(in database: Database) throws -> [ZimFile] {
        try database.viewContext.fetch(ZimFile.fetchRequest(predicate: ZimFile.downloadedMapsPredicate()))
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func copyFixture(to directory: URL) throws -> URL {
        let source = try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: "streetzim-demo", withExtension: "zim")
        )
        let destination = directory.appendingPathComponent("streetzim-demo.zim")
        try FileManager.default.copyItem(at: source, to: destination)
        return destination
    }

    private func resolve(_ bookmark: Data) throws -> URL {
        var stale = false
        #if os(macOS)
        return try URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, bookmarkDataIsStale: &stale)
        #else
        return try URL(resolvingBookmarkData: bookmark, bookmarkDataIsStale: &stale)
        #endif
    }
}
