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

    func testPreflightMergesRepeatedSourceChunkReferences() throws {
        let source = StreetZimRecipe.Source(file: "base.zim", size: 2_400_000,
                                           uuid: UUID().uuidString, chunk: 24,
                                           sha256: Array(repeating: String(repeating: "0", count: 64), count: 100_000),
                                           mask: nil, url: nil)
        let segment = StreetZimRecipe.Segment(src: "base", pack: nil, off: 0, len: source.size,
                                             data: nil, sha256: nil)
        let recipe = StreetZimRecipe(format: "streetzim-recipe/2", uuid: UUID().uuidString,
                                     name: "test", fileName: nil, size: source.size * 100_000 + 16,
                                     md5: String(repeating: "0", count: 32), fileMD5: nil,
                                     base: source, packs: [:],
                                     segments: Array(repeating: segment, count: 100_000))
        let referenced = try StreetZimAssembler.referencedChunks(
            recipe: recipe, sources: ["base": source], localBase: false
        )
        XCTAssertEqual(referenced["base"]?.ranges, [0..<100_000])
        XCTAssertTrue(try StreetZimAssembler.referencedChunks(
            recipe: recipe, sources: ["base": source], localBase: true
        ).isEmpty)
    }

    func testPreflightCountsBoundaryChunksAndKeepsSourcesSeparate() throws {
        let source = StreetZimRecipe.Source(file: "base.zim", size: 100,
                                           uuid: UUID().uuidString, chunk: 10,
                                           sha256: Array(repeating: String(repeating: "0", count: 64), count: 10),
                                           mask: nil, url: nil)
        let segments = [
            StreetZimRecipe.Segment(src: "base", pack: nil, off: 9, len: 2, data: nil, sha256: nil),
            StreetZimRecipe.Segment(src: "base", pack: nil, off: 20, len: 10, data: nil, sha256: nil),
            StreetZimRecipe.Segment(src: "base", pack: nil, off: 90, len: 0, data: nil, sha256: nil),
            StreetZimRecipe.Segment(src: "pack", pack: "fr", off: 90, len: 10, data: nil, sha256: nil)
        ]
        let recipe = StreetZimRecipe(format: "streetzim-recipe/2", uuid: UUID().uuidString,
                                     name: "test", fileName: nil, size: 38,
                                     md5: String(repeating: "0", count: 32), fileMD5: nil,
                                     base: source, packs: ["fr": source], segments: segments)
        let sources = ["base": source, "pack:fr": source]
        let referenced = try StreetZimAssembler.referencedChunks(recipe: recipe, sources: sources, localBase: false)
        XCTAssertEqual(referenced["base"]?.ranges, [0..<3])
        XCTAssertEqual(referenced["pack:fr"]?.ranges, [9..<10])
        let local = try StreetZimAssembler.referencedChunks(recipe: recipe, sources: sources, localBase: true)
        XCTAssertNil(local["base"])
        XCTAssertEqual(local["pack:fr"]?.ranges, [9..<10])
    }

    func testLanguageUsesAppLanguageThenEnglishFallback() throws {
        let region = try catalogRegion()
        XCTAssertEqual(region.preferredLanguage(["fr-CA", "en-US"]), "fr")
        XCTAssertEqual(region.preferredLanguage(["deu"]), "de")
        XCTAssertEqual(region.preferredLanguage(["ja"]), "en")
        XCTAssertEqual(try catalogRegion(languages: ["fr"]).preferredLanguage(["ja"]), "fr")
    }

    func testLanguagePreferenceKeepsChineseScriptInsteadOfCatalogOrder() throws {
        let traditional = try catalogRegion(languages: ["zh-Hans", "en", "zh-Hant"])
        XCTAssertEqual(traditional.preferredLanguage(["zh-TW"]), "zh-Hant")
        let simplified = try catalogRegion(languages: ["zh-Hant", "en", "zh-Hans"])
        XCTAssertEqual(simplified.preferredLanguage(["zh-CN"]), "zh-Hans")
    }

    func testExplicitRegionalLanguageWinsOverGenericLanguage() throws {
        let region = try catalogRegion(languages: ["pt", "pt-PT", "pt-BR", "en"])
        XCTAssertEqual(region.preferredLanguage(["PT_br"]), "pt-BR")
    }

    func testUnrecognizedLanguageCodesDoNotMatchEachOther() throws {
        let region = try catalogRegion(languages: ["kab", "ln", "eng"])
        XCTAssertEqual(region.preferredLanguage(["kab-Latn"]), "kab")
        XCTAssertEqual(region.preferredLanguage(["dag-GH"]), "eng")
    }

    func testBalticsLanguageGroupsSortAvailableLanguagesInsteadOfCatalogOrder() throws {
        let region = try catalogRegion(languages: ["ru", "lt", "de", "lv", "en", "et"], id: "baltics")
        let groups = region.languageGroups(locale: Locale(identifier: "en"))

        XCTAssertEqual(groups.local.map(\.lang), ["et", "lv", "lt"])
        XCTAssertEqual(groups.other.map(\.lang), ["en", "de", "ru"])
    }

    func testHawaiiLanguageGroupsIncludeOnlyAvailableLocalVersions() throws {
        let region = try catalogRegion(languages: ["ja", "haw", "fr"], id: "hawaii")
        let groups = region.languageGroups(locale: Locale(identifier: "en"))

        XCTAssertEqual(groups.local.map(\.lang), ["haw"])
        XCTAssertEqual(groups.other.map(\.lang), ["fr", "ja"])
        XCTAssertFalse((groups.local + groups.other).contains { $0.lang == "en" })
    }

    func testGermanyLanguageGroupsPutGermanBeforeAlphabeticalOtherLanguages() throws {
        let region = try catalogRegion(languages: ["fr", "de", "en"], id: "germany")
        let groups = region.languageGroups(locale: Locale(identifier: "en"))

        XCTAssertEqual(groups.local.map(\.lang), ["de"])
        XCTAssertEqual(groups.other.map(\.lang), ["en", "fr"])
    }

    func testMappedRegionWithoutAvailableLocalLanguagesHasOnlyAlphabeticalOthers() throws {
        let region = try catalogRegion(languages: ["fr", "en"], id: "germany")
        let groups = region.languageGroups(locale: Locale(identifier: "en"))

        XCTAssertTrue(groups.local.isEmpty)
        XCTAssertEqual(groups.other.map(\.lang), ["en", "fr"])
    }

    func testSwitzerlandLanguageGroupsUseLocalizedDisplayedNameOrder() throws {
        let region = try catalogRegion(languages: ["rm", "it", "en", "de", "fr"], id: "switzerland")
        let english = region.languageGroups(locale: Locale(identifier: "en"))
        let german = region.languageGroups(locale: Locale(identifier: "de"))

        // French precedes German in English; Deutsch precedes Französisch in German.
        XCTAssertEqual(english.local.map(\.lang), ["fr", "de", "it", "rm"])
        XCTAssertEqual(german.local.map(\.lang), ["de", "fr", "it", "rm"])
        XCTAssertEqual(english.other.map(\.lang), ["en"])
        XCTAssertEqual(german.other.map(\.lang), ["en"])
    }

    func testOtherLanguagesAlsoUseLocalizedDisplayedNameOrder() throws {
        let region = try catalogRegion(languages: ["de", "haw", "fr", "en"], id: "hawaii")
        let english = region.languageGroups(locale: Locale(identifier: "en"))
        let german = region.languageGroups(locale: Locale(identifier: "de"))

        XCTAssertEqual(english.local.map(\.lang), ["en", "haw"])
        XCTAssertEqual(english.other.map(\.lang), ["fr", "de"])
        XCTAssertEqual(german.local.map(\.lang), ["en", "haw"])
        XCTAssertEqual(german.other.map(\.lang), ["de", "fr"])
    }

    func testTaiwanLanguageGroupsKeepEveryOriginalScriptAndRegionVersion() throws {
        let languages = ["ja", "zh-TW", "zh-Hans", "en", "zh-Hant", "zh_CN"]
        let region = try catalogRegion(languages: languages, id: "taiwan")
        let locale = Locale(identifier: "en")
        let groups = region.languageGroups(locale: locale)
        let grouped = groups.local + groups.other

        XCTAssertEqual(Set(groups.local.map(\.lang)), Set(["zh-TW", "zh-Hans", "zh-Hant", "zh_CN"]))
        XCTAssertEqual(groups.other.map(\.lang), ["en", "ja"])
        XCTAssertEqual(grouped.count, languages.count)
        XCTAssertEqual(Set(grouped.map(\.lang)), Set(languages))
        XCTAssertEqual(Set(grouped.map(\.lang)).count, grouped.count)
        let localNames = groups.local.map { $0.displayName(locale: locale) }
        XCTAssertEqual(localNames, localNames.sorted {
            $0.compare($1, options: .caseInsensitive, locale: locale) == .orderedAscending
        })
    }

    func testUnmappedRegionHasNoLocalSectionAndSortsAllLanguagesAlphabetically() throws {
        let region = try catalogRegion(languages: ["de", "fr", "en"], id: "unmapped-test-region")
        let groups = region.languageGroups(locale: Locale(identifier: "en"))

        XCTAssertTrue(groups.local.isEmpty)
        XCTAssertEqual(groups.other.map(\.lang), ["en", "fr", "de"])
    }

    func testSavedMapLabelsUseCatalogRegionAndPreserveArchiveTitle() throws {
        let baltics = try catalogRegion(languages: ["es"], id: "baltics", title: "Baltic States")
        let iceland = try catalogRegion(languages: ["ru"], id: "iceland", title: "Iceland")
        let locale = Locale(identifier: "en")
        for (region, archiveTitle, language) in [(baltics, "OSM - Baltics", "Spanish"),
                                                 (iceland, "Исландия", "Russian")] {
            let label = StreetZimMapLabel(persistentID: region.menu[0].name, archiveTitle: archiveTitle,
                                         languageCodes: "eng", regions: [baltics, iceland], locale: locale)
            XCTAssertEqual(label.title, region.title)
            XCTAssertTrue(label.subtitle.contains(language))
            XCTAssertTrue(label.subtitle.contains(archiveTitle))
        }
    }

    func testSavedMapLabelsWorkOfflineWithRegionSlugSeparators() {
        let locale = Locale(identifier: "en")
        for (name, title, language, archiveTitle) in [
            ("osm_es_baltics", "Baltics", "Spanish", "OSM - Baltics"),
            ("osm_ru_iceland", "Iceland", "Russian", "Исландия"),
            ("osm_fr_new_zealand-south", "New Zealand South", "French", "Nouvelle-Zélande")
        ] {
            let label = StreetZimMapLabel(persistentID: name, archiveTitle: archiveTitle,
                                         languageCodes: "eng", regions: [], locale: locale)
            XCTAssertEqual(label.title, title)
            XCTAssertTrue(label.subtitle.contains(language))
            XCTAssertTrue(label.subtitle.contains(archiveTitle))
        }
    }

    func testSavedMapLabelsPreserveUnknownArchiveNamesAndMetadataLanguages() {
        for name in ["personal_map", "osm__iceland", "osm_ru_", "osm_ru_---"] {
            let label = StreetZimMapLabel(persistentID: name, archiveTitle: "My map",
                                         languageCodes: "deu,fra", regions: [], locale: Locale(identifier: "en"))
            XCTAssertEqual(label.title, "My map")
            XCTAssertEqual(label.subtitle, "German, French")
        }
    }

    func testSavedMapLabelsDoNotRepeatMatchingArchiveTitle() throws {
        let region = try catalogRegion(languages: ["en"])
        let locale = Locale(identifier: "en")
        let label = StreetZimMapLabel(persistentID: region.menu[0].name, archiveTitle: region.title,
                                     languageCodes: "eng", regions: [region], locale: locale)
        XCTAssertEqual(label.title, region.title)
        XCTAssertEqual(label.subtitle, region.menu[0].displayName(locale: locale))
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
        let offline = StreetZimAssembler(
            endpoint: endpoint, cache: folder.appendingPathComponent("cache"), readRange: { _, _, _, _ in
                XCTFail("Verified shared chunks should be reused")
                throw URLError(.notConnectedToInternet)
            }
        )
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
        let assembler = StreetZimAssembler(
            endpoint: endpoint, cache: folder.appendingPathComponent("cache"), readRange: { url, off, len, size in
                XCTAssertNotEqual(url, fixture.baseURL)
                return try await reader.read(url, off, len, size)
            }
        )
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

    func testDuplicateMasksAndManySegmentsNormalizeWithoutRejectingRecipe() async throws {
        // A per-segment mask scan would do ten billion comparisons here.
        let recipe = maskRecipe(masks: Array(repeating: [128, 64], count: 100_000),
                                reads: Array(repeating: 0..<1, count: 100_000))
        let masks = try recipe.validate()
        XCTAssertEqual(masks["base"]?.ranges, [128..<192])
        try await recipe.validateInBackground()
    }

    func testLargeUnorderedMaskIndexPreservesChunkHashBytes() throws {
        let masks = stride(from: 399_996, through: 0, by: -4).map { [Int64($0), 1] }
        let index = try maskRecipe(masks: masks, reads: [400_000..<400_001]).validate()["base"]!
        XCTAssertEqual(index.ranges.count, 100_000)
        for offset in stride(from: 0, to: 400_000, by: 256) {
            let count = min(256, 400_000 - offset)
            let raw = Data(repeating: 255, count: count)
            let masked = try index.masked(raw, at: Int64(offset))
            var expected = raw
            for byte in stride(from: 0, to: count, by: 4) { expected[byte] = 0 }
            XCTAssertEqual(masked, expected)
        }
    }

    func testMaskUnionAndHalfOpenOverlapBoundaries() throws {
        let masks: [[Int64]] = [[40, 10], [20, 10], [25, 10], [35, 5], [10, 0], [1_048_576, 0]]
        let recipe = maskRecipe(masks: masks, reads: [0..<20, 50..<60, 30..<30])
        let index = try XCTUnwrap(recipe.validate()["base"])
        XCTAssertEqual(index.ranges, [20..<50])
        let overlappingReads: [Range<Int64>] = [19..<21, 49..<51, 20..<50]
        for read in overlappingReads {
            XCTAssertThrowsError(try maskRecipe(masks: masks, reads: [read]).validate())
        }
        let raw = Data(repeating: 255, count: 40)
        var expected = raw
        expected.resetBytes(in: 10..<40)
        XCTAssertEqual(try index.masked(raw, at: 10), expected)
        XCTAssertEqual(try index.masked(raw, at: 50), raw)
    }

    func testInvalidMaskBoundsAndOverflowAreStillRejected() throws {
        let invalid: [[[Int64]]] = [
            [[-1, 1]], [[0, -1]], [[Int64.max, 1]], [[1, Int64.max]],
            [[1_048_576, 1]], [[0]], [[0, 1, 2]]
        ]
        for masks in invalid {
            XCTAssertThrowsError(try maskRecipe(masks: masks, reads: [0..<1]).validate())
        }
        let largest = try StreetZimRecipe.MaskIndex([[Int64.max - 1, 1], [Int64.max, 0]], size: Int64.max)
        XCTAssertTrue(largest.overlaps(Int64.max - 1..<Int64.max))
        XCTAssertFalse(largest.overlaps(0..<Int64.max - 1))
    }

    func testPackMaskOverlapIsRejectedBeforeAnyDownload() async throws {
        var fixture = try Fixture()
        var packs = fixture.document["packs"] as! [String: [String: Any]]
        let segments = fixture.document["segments"] as! [[String: Any]]
        let read = try XCTUnwrap(segments.first { $0["src"] as? String == "pack" })
        let key = try XCTUnwrap(read["pack"] as? String)
        packs[key]!["mask"] = [[read["off"]!, read["len"]!]]
        fixture.document["packs"] = packs
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let assembler = StreetZimAssembler(
            endpoint: endpoint, cache: folder.appendingPathComponent("cache"), readRange: { _, _, _, _ in
                XCTFail("A masked source range must fail before any download")
                return Data()
            }
        )
        do {
            _ = try await assembler.assemble(recipe: fixture.recipe(), baseURL: fixture.baseURL, destination: folder)
            XCTFail("Masked pack bytes must not enter the output")
        } catch StreetZimError.invalidRecipe { }
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
    }

    @MainActor
    func testBackgroundValidationPropagatesCallerCancellation() async throws {
        let recipe = maskRecipe(masks: Array(repeating: [128, 64], count: 100_000),
                                reads: Array(repeating: 0..<1, count: 100_000))
        let task = Task { @MainActor in
            // Already-cancelled callers must not start CPU-bound validation.
            withUnsafeCurrentTask { $0?.cancel() }
            try await recipe.validateInBackground()
        }
        do {
            try await task.value
            XCTFail("Validation must propagate cancellation rather than finish preparing a map")
        } catch is CancellationError { }
    }

    @MainActor
    func testMainActorCanCancelBackgroundValidation() async throws {
        let recipe = maskRecipe(masks: [[128, 64]], reads: [0..<1])
        let started = expectation(description: "Validation entered its worker")
        let cancelled = expectation(description: "Validation worker observed cancellation")
        let release = DispatchSemaphore(value: 0)
        let task = Task { @MainActor in
            try await StreetZimRecipe.runValidation {
                started.fulfill()
                guard release.wait(timeout: .now() + 5) == .success else {
                    throw StreetZimError.invalidRecipe
                }
                do {
                    _ = try recipe.validate()
                    XCTFail("The validation worker must observe caller cancellation")
                } catch is CancellationError {
                    cancelled.fulfill()
                    throw CancellationError()
                }
            }
        }
        await fulfillment(of: [started], timeout: 5)
        task.cancel()
        release.signal()
        do {
            try await task.value
            XCTFail("Cancelled validation must not succeed")
        } catch is CancellationError { }
        await fulfillment(of: [cancelled], timeout: 5)
    }

    private func maskRecipe(masks: [[Int64]], reads: [Range<Int64>]) -> StreetZimRecipe {
        let hash = String(repeating: "0", count: 64)
        let source = StreetZimRecipe.Source(file: "base.zim", size: 1_048_576, uuid: UUID().uuidString,
                                           chunk: 1_048_576, sha256: [hash], mask: masks, url: nil)
        let segments = reads.map {
            StreetZimRecipe.Segment(src: "base", pack: nil, off: $0.lowerBound,
                                    len: $0.upperBound - $0.lowerBound, data: nil, sha256: nil)
        } + [StreetZimRecipe.Segment(src: "md5", pack: nil, off: nil, len: nil, data: nil, sha256: nil)]
        return StreetZimRecipe(format: "streetzim-recipe/2", uuid: UUID().uuidString, name: "map",
                               fileName: nil, size: reads.reduce(16) { $0 + $1.upperBound - $1.lowerBound },
                               md5: String(repeating: "0", count: 32), fileMD5: nil,
                               base: source, packs: [:], segments: segments)
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

    func testInsufficientSpaceDoesNotStartDownloadOrPublishOutput() async throws {
        let fixture = try Fixture()
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let assembler = StreetZimAssembler(
            endpoint: endpoint, cache: folder.appendingPathComponent("cache"),
            capacity: { _ in .init(available: 0, volume: folder) },
            readRange: { _, _, _, _ in
                XCTFail("Insufficient capacity must fail before downloading")
                return Data()
            }
        )
        do {
            _ = try await assembler.assemble(recipe: fixture.recipe(), baseURL: fixture.baseURL, destination: folder)
            XCTFail("Insufficient capacity must reject assembly")
        } catch StreetZimError.insufficientSpace { }
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: folder.path).contains {
            $0.hasSuffix(".zim") || $0.hasSuffix(".part")
        })
    }

    func testInvalidLocalCandidateRechecksSpaceBeforeNetworkFallback() async throws {
        let fixture = try Fixture()
        let recipe = try fixture.recipe()
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let cache = folder.appendingPathComponent("cache")
        let reader = Reader(sources: fixture.sources)
        let first = StreetZimAssembler(endpoint: endpoint, cache: cache, readRange: {
            try await reader.read($0, $1, $2, $3)
        })
        let output = try await first.assemble(recipe: recipe, baseURL: fixture.baseURL, destination: folder)
        try FileManager.default.removeItem(at: output)
        let length = min(recipe.base.chunk, recipe.base.size)
        try FileManager.default.removeItem(at: cache.appendingPathComponent("\(recipe.base.sha256[0])-\(length)"))
        let candidate = folder.appendingPathComponent("candidate")
        try Data(repeating: 0, count: Int(recipe.base.size)).write(to: candidate)
        let assembler = StreetZimAssembler(
            endpoint: endpoint, cache: cache,
            capacity: { _ in .init(available: recipe.size, volume: folder) },
            readRange: { _, _, _, _ in
                XCTFail("A rejected local candidate must reserve network cache capacity first")
                return Data()
            }
        )
        do {
            _ = try await assembler.assemble(
                recipe: recipe, baseURL: fixture.baseURL, localBase: candidate, destination: folder
            )
            XCTFail("Fallback requires space for both output and the missing chunk")
        } catch StreetZimError.insufficientSpace { }
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: folder.path).contains {
            $0.hasSuffix(".zim") || $0.hasSuffix(".part")
        })
    }

    func testTransientFailureRecoversAfterBackoff() async throws {
        let fixture = try Fixture()
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let reader = FailingReader(sources: fixture.sources)
        let assembler = StreetZimAssembler(
            endpoint: endpoint, cache: folder.appendingPathComponent("cache"),
            retrySleep: { _ in try Task.checkCancellation() },
            readRange: { try await reader.read($0, $1, $2, $3) }
        )
        let output = try await assembler.assemble(
            recipe: fixture.recipe(), baseURL: fixture.baseURL, destination: folder
        )
        XCTAssertEqual(try Data(contentsOf: output), fixture.expected)
    }

    func testCancellationDuringBackoffRemovesPartialOutput() async throws {
        let fixture = try Fixture()
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let sleeping = expectation(description: "Retry backoff entered")
        let assembler = StreetZimAssembler(
            endpoint: endpoint, cache: folder.appendingPathComponent("cache"),
            retrySleep: { _ in
                sleeping.fulfill()
                try await Task.sleep(for: .seconds(60))
            },
            readRange: { _, _, _, _ in throw URLError(.networkConnectionLost) }
        )
        let task = Task {
            try await assembler.assemble(recipe: fixture.recipe(), baseURL: fixture.baseURL, destination: folder)
        }
        await fulfillment(of: [sleeping], timeout: 5)
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Cancellation must interrupt retry backoff")
        } catch is CancellationError { }
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: folder.path).contains {
            $0.hasSuffix(".zim") || $0.hasSuffix(".part")
        })
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

    private func catalogRegion(languages: [String] = ["de", "fr", "en"],
                               id: String = "test", title: String = "Test") throws -> StreetZimCatalog.Region {
        let menu = languages.map { lang in
            ["lang": lang, "label": lang, "name": "osm_\(lang)_\(id)", "recipe": "recipes/\(id)/\(lang).json", "size": 123,
             "download_bytes": 100, "md5": String(repeating: "0", count: 32)] as [String: Any]
        }
        let json: [String: Any] = ["id": id, "title": title, "menu": menu,
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

private actor FailingReader {
    private var failNext = true
    private let reader: Reader

    init(sources: [String: Data]) { reader = Reader(sources: sources) }

    func read(_ url: URL, _ offset: Int64, _ length: Int64, _ size: Int64) async throws -> Data {
        if failNext {
            failNext = false
            throw URLError(.networkConnectionLost)
        }
        return try await reader.read(url, offset, length, size)
    }
}
