// This file is part of Kiwix for iOS & macOS.
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import XCTest
@testable import Kiwix

final class StreetZimTests: XCTestCase, @unchecked Sendable {
    private let endpoint = StreetZimEndpoint(
        indexURL: URL(string: "https://maps.example/build/recipes/index.json")!,
        proxyURL: URL(string: "https://parts.example")!
    )

    func testLanguageUsesAppLanguageThenEnglishFallback() throws {
        let region = try catalogRegion()
        XCTAssertEqual(region.preferredLanguage(["fr-CA", "en-US"]), "fr")
        XCTAssertEqual(region.preferredLanguage(["deu"]), "de")
        XCTAssertEqual(region.preferredLanguage(["ja"]), "en")
        XCTAssertEqual(try catalogRegion(languages: ["fr"]).preferredLanguage(["ja"]), "fr")
    }

    func testCatalogRejectsOverflowNegativeSizesAndDuplicateLanguages() throws {
        let region = try catalogRegion()
        let index = StreetZimCatalog(format: "streetzim-build-index/1", regions: [region])
        XCTAssertNoThrow(try index.validate())
        XCTAssertThrowsError(try StreetZimCatalog(format: "wrong", regions: [region]).validate())
        XCTAssertThrowsError(try StreetZimCatalog(format: index.format, regions: [region, region]).validate())
        for mutation in 0..<3 {
            let base = StreetZimCatalog.Base(file: "base.zim", size: mutation == 0 ? Int64.max : 10,
                                            download: "https://example.org/base.zim", url: nil)
            let version = StreetZimCatalog.LanguageVersion(lang: "en", label: "English", name: "osm_en_test",
                                                          recipe: "recipes/test/en.json", size: 100,
                                                          downloadBytes: mutation == 1 ? -1 : 1,
                                                          md5: String(repeating: "0", count: 32))
            let invalid = StreetZimCatalog.Region(id: "test", title: "Test", base: base,
                                                  menu: mutation == 2 ? [version, version] : [version])
            XCTAssertThrowsError(try StreetZimCatalog(format: index.format, regions: [invalid]).validate())
        }
    }

    func testRelativeRecipesAndProxyPlaceholder() throws {
        XCTAssertEqual(try endpoint.recipeURL("recipes/iceland/fr.json").absoluteString,
                       "https://maps.example/build/recipes/iceland/fr.json")
        XCTAssertEqual(try endpoint.sourceURL("{proxy}/item/file.zim").absoluteString,
                       "https://parts.example/item/file.zim")
        XCTAssertThrowsError(try endpoint.sourceURL("file:///etc/passwd"))
        XCTAssertThrowsError(try endpoint.recipeURL("http://maps.example/recipe.json"))
    }

    func testMatchesUpstreamMergeAndReusesCacheWithoutNetwork() async throws {
        let fixture = try Fixture()
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let reader = Reader(sources: fixture.sources)
        let assembler = StreetZimAssembler(endpoint: endpoint, cache: folder.appendingPathComponent("cache"),
                                          readRange: { url, off, len, size in
                                              try await reader.read(url, off, len, size)
                                          })
        let recipe = try fixture.recipe()
        let first = try await assembler.assemble(recipe: recipe, baseURL: fixture.baseURL, destination: folder)
        XCTAssertEqual(try Data(contentsOf: first), fixture.expected)
        let calls = await reader.count
        XCTAssertGreaterThan(calls, 0)
        let offline = StreetZimAssembler(endpoint: endpoint, cache: folder.appendingPathComponent("cache")) { _, _, _, _ in
            XCTFail("Verified shared chunks should be reused")
            throw URLError(.notConnectedToInternet)
        }
        let second = try await offline.assemble(recipe: recipe, baseURL: fixture.baseURL, destination: folder)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(try Data(contentsOf: second), fixture.expected)
        XCTAssertEqual(try Data(contentsOf: first), fixture.expected)
    }

    func testCorruptCachedChunkIsDownloadedAgain() async throws {
        let fixture = try Fixture()
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let cache = folder.appendingPathComponent("cache")
        let reader = Reader(sources: fixture.sources)
        let assembler = StreetZimAssembler(endpoint: endpoint, cache: cache, readRange: { url, off, len, size in
            try await reader.read(url, off, len, size)
        })
        let recipe = try fixture.recipe()
        _ = try await assembler.assemble(recipe: recipe, baseURL: fixture.baseURL, destination: folder)
        let before = await reader.count
        let firstChunk = cache.appendingPathComponent("\(recipe.base.sha256[0])-256")
        try Data([0]).write(to: firstChunk)
        let output = try await assembler.assemble(recipe: recipe, baseURL: fixture.baseURL, destination: folder)
        XCTAssertEqual(try Data(contentsOf: output), fixture.expected)
        let after = await reader.count
        XCTAssertEqual(after, before + 1)
    }

    func testInstalledBaseIsReadLocallyAndNotDownloaded() async throws {
        let fixture = try Fixture()
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let base = folder.appendingPathComponent("local.zim")
        try XCTUnwrap(fixture.sources["base"]).write(to: base)
        let reader = Reader(sources: fixture.sources)
        let assembler = StreetZimAssembler(endpoint: endpoint, cache: folder.appendingPathComponent("cache")) {
            url, off, len, size in
            XCTAssertNotEqual(url, fixture.baseURL)
            return try await reader.read(url, off, len, size)
        }
        let output = try await assembler.assemble(recipe: fixture.recipe(), baseURL: fixture.baseURL,
                                                   localBase: base, destination: folder)
        XCTAssertEqual(try Data(contentsOf: output), fixture.expected)
    }

    func testComposedLanguageVersionCanSupplyBaseChunks() async throws {
        let fixture = try Fixture()
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let version = folder.appendingPathComponent("other-language.zim")
        try fixture.otherVersion.write(to: version)
        let reader = Reader(sources: fixture.sources)
        let assembler = StreetZimAssembler(endpoint: endpoint, cache: folder.appendingPathComponent("cache"),
                                          readRange: { url, off, len, size in
            if url == fixture.baseURL { XCTAssertTrue(off < 2048 || off >= 36352) }
            return try await reader.read(url, off, len, size)
        })
        let output = try await assembler.assemble(recipe: fixture.recipe(), baseURL: fixture.baseURL,
                                                   localBase: version, destination: folder)
        XCTAssertEqual(try Data(contentsOf: output), fixture.expected)
    }

    func testBadInlineHashRejectedBeforeDownloading() async throws {
        var fixture = try Fixture()
        var segments = fixture.document["segments"] as! [[String: Any]]
        let index = segments.firstIndex { $0["src"] as? String == "inline" }!
        segments[index]["sha256"] = String(repeating: "0", count: 64)
        fixture.document["segments"] = segments
        XCTAssertThrowsError(try fixture.recipe().validate())
    }

    func testBoundsUnknownSourceAndMissingChecksumRejected() throws {
        for mutation in 0..<3 {
            var fixture = try Fixture()
            var segments = fixture.document["segments"] as! [[String: Any]]
            if mutation == 0 {
                let index = segments.firstIndex { $0["src"] as? String == "base" }!
                segments[index]["off"] = Int64.max
            } else if mutation == 1 {
                segments[0]["src"] = "unrecognized"
            } else { segments.removeLast() }
            fixture.document["segments"] = segments
            XCTAssertThrowsError(try fixture.recipe().validate())
        }
    }

    func testWrongFinalChecksumNeverPublishesOutput() async throws {
        for key in ["md5", "file_md5"] {
            var fixture = try Fixture()
            fixture.document[key] = String(repeating: "0", count: 32)
            try await expectFailedAssembly(fixture)
        }
    }

    func testCorruptSourceAndWrongBaseUUIDNeverPublishOutput() async throws {
        var fixture = try Fixture()
        var base = fixture.document["base"] as! [String: Any]
        base["uuid"] = UUID().uuidString
        fixture.document["base"] = base
        try await expectFailedAssembly(fixture)
        fixture = try Fixture()
        fixture.sources["base"]![30] ^= 1
        try await expectFailedAssembly(fixture)
    }

    func testMaskedBaseBytesAllowViewerPatchesButCannotBeRead() async throws {
        var fixture = try Fixture()
        var base = fixture.document["base"] as! [String: Any]
        // Add a checksum mask to the upstream fixture (which has no viewer
        // slots); the recipe never reads these bytes from the base.
        let checksumOffset = fixture.sources["base"]!.count - 16
        base["mask"] = [[checksumOffset, 16]]
        var masked = fixture.sources["base"]!
        masked.resetBytes(in: checksumOffset..<checksumOffset + 16)
        base["sha256"] = stride(from: 0, to: masked.count, by: 256).map {
            StreetZimRecipe.sha256(masked.subdata(in: $0..<min($0 + 256, masked.count)))
        }
        fixture.document["base"] = base
        fixture.sources["base"]![checksumOffset] ^= 1
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let reader = Reader(sources: fixture.sources)
        let assembler = StreetZimAssembler(endpoint: endpoint, cache: folder.appendingPathComponent("cache"),
                                          readRange: { url, off, len, size in
                                              try await reader.read(url, off, len, size)
                                          })
        let output = try await assembler.assemble(recipe: fixture.recipe(), baseURL: fixture.baseURL, destination: folder)
        XCTAssertEqual(try Data(contentsOf: output), fixture.expected)
        base["mask"] = [[2048, 256]]
        fixture.document["base"] = base
        var segments = fixture.document["segments"] as! [[String: Any]]
        let index = segments.firstIndex { $0["src"] as? String == "base" }!
        segments[index]["off"] = 2048
        fixture.document["segments"] = segments
        XCTAssertThrowsError(try fixture.recipe().validate())
    }

    func testCancellationRemovesPartialFileAndKeepsVerifiedChunks() async throws {
        let fixture = try Fixture()
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let cache = folder.appendingPathComponent("cache")
        let reader = Reader(sources: fixture.sources)
        let assembler = StreetZimAssembler(endpoint: endpoint, cache: cache, readRange: { url, off, len, size in
                                              try await reader.read(url, off, len, size)
                                          })
        let task = Task {
            try await assembler.assemble(recipe: fixture.recipe(), baseURL: fixture.baseURL, destination: folder) { written, _ in
                if written > 0 { withUnsafeCurrentTask { $0?.cancel() } }
            }
        }
        do {
            _ = try await task.value
            XCTFail("Should be cancelled")
        } catch is CancellationError { } catch { XCTFail("Unexpected error: \(error)") }
        let files = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        XCTAssertEqual(files, ["cache"])
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: cache.path).isEmpty)
        let output = try await assembler.assemble(recipe: fixture.recipe(), baseURL: fixture.baseURL, destination: folder)
        XCTAssertEqual(try Data(contentsOf: output), fixture.expected)
    }

    private func expectFailedAssembly(_ fixture: Fixture) async throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let reader = Reader(sources: fixture.sources)
        let assembler = StreetZimAssembler(endpoint: endpoint, cache: folder.appendingPathComponent("cache"),
                                          readRange: { url, off, len, size in
                                              try await reader.read(url, off, len, size)
                                          })
        do {
            _ = try await assembler.assemble(recipe: fixture.recipe(), baseURL: fixture.baseURL, destination: folder)
            XCTFail("Corruption should fail")
        } catch StreetZimError.integrity { }
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: folder.path).contains {
            $0.hasSuffix(".zim") || $0.hasSuffix(".part")
        })
    }

    private func temporaryFolder() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    private func catalogRegion(languages: [String] = ["de", "fr", "en"]) throws -> StreetZimCatalog.Region {
        let menu = languages.map { lang in
            ["lang": lang, "label": lang, "name": "osm_\(lang)_test", "recipe": "recipes/test/\(lang).json", "size": 123,
             "download_bytes": 100, "md5": String(repeating: "0", count: 32)] as [String: Any]
        }
        let json: [String: Any] = ["id": "test", "title": "Test", "menu": menu,
                                  "base": ["file": "base.zim", "size": 1, "download": "https://example.org/base.zim"]]
        return try JSONDecoder().decode(StreetZimCatalog.Region.self, from: JSONSerialization.data(withJSONObject: json))
    }
}

private struct Fixture: @unchecked Sendable {
    var document: [String: Any]
    var sources: [String: Data]
    let expected: Data
    let otherVersion: Data
    let baseURL = URL(string: "https://parts.example/base.zim")!

    init() throws {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle(for: StreetZimTests.self)
        #endif
        let url = try XCTUnwrap(bundle.url(forResource: "StreetZimFixture", withExtension: "json"))
        let fixture = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        document = fixture["recipe"] as! [String: Any]
        sources = (fixture["sources"] as! [String: String]).mapValues { Data(base64Encoded: $0)! }
        expected = Data(base64Encoded: fixture["expected"] as! String)!
        otherVersion = Data(base64Encoded: fixture["otherVersion"] as! String)!
    }

    func recipe() throws -> StreetZimRecipe {
        try JSONDecoder().decode(StreetZimRecipe.self, from: JSONSerialization.data(withJSONObject: document))
    }
}

private actor Reader {
    let sources: [String: Data]
    private(set) var count = 0
    init(sources: [String: Data]) { self.sources = sources }

    func read(_ url: URL, _ off: Int64, _ len: Int64, _ size: Int64) throws -> Data {
        count += 1
        let key: String
        if url.lastPathComponent == "base.zim" { key = "base" }
        else if url.lastPathComponent == "de.zim" || url.lastPathComponent.contains("wiki-de") { key = "de" }
        else { key = "fr" }
        let data = try XCTUnwrap(sources[key])
        XCTAssertEqual(Int64(data.count), size)
        return data.subdata(in: Int(off)..<Int(off + len))
    }
}
