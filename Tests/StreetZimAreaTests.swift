// This file is part of Kiwix for iOS & macOS.
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import Kiwix

final class StreetZimAreaTests: XCTestCase {
    private let english = Locale(identifier: "en_US")

    func testMixedAreasUseFixedGroupOrderAndAlphabeticalRows() {
        let regions = [
            region("europe", "Europe"), region("unknown-z", "Zulu"),
            region("japan", "Japan"), region("washington-dc", "Washington, D.C."),
            region("africa", "Africa"), region("canada", "Canada"),
            region("silicon-valley", "Silicon Valley"), region("unknown-a", "Alpha")
        ]
        let sections = StreetZimCatalog.areaSections(in: regions, locale: english)

        XCTAssertEqual(sections.map(\.group), [.local, .country, .region, .other])
        XCTAssertEqual(sections.map { $0.regions.map(\.id) }, [
            ["silicon-valley", "washington-dc"], ["canada", "japan"],
            ["africa", "europe"], ["unknown-a", "unknown-z"]
        ])
    }

    func testSortingUsesRequestedLocale() {
        let regions = [region("orebro", "Örebro"), region("zurich", "Zurich"),
                       region("aland", "Åland"), region("berlin", "Berlin")]
        let englishSections = StreetZimCatalog.areaSections(in: regions, locale: english)
        let swedishSections = StreetZimCatalog.areaSections(in: regions, locale: Locale(identifier: "sv_SE"))

        XCTAssertEqual(englishSections.flatMap(\.regions).map(\.id), ["aland", "berlin", "orebro", "zurich"])
        XCTAssertEqual(swedishSections.flatMap(\.regions).map(\.id), ["berlin", "zurich", "aland", "orebro"])
    }

    func testSearchIgnoresCaseAndDiacriticsInHumanTitles() {
        let regions = [region("quebec-test", "Québec City"), region("japan", "Japan")]
        let sections = StreetZimCatalog.areaSections(in: regions, matching: "QUEBEC", locale: english)

        XCTAssertEqual(sections.map(\.group), [.other])
        XCTAssertEqual(sections.flatMap(\.regions).map(\.id), ["quebec-test"])
    }

    func testSearchUsesRequestedLocaleForCaseMatching() {
        let regions = [region("turkish-city", "Isparta"), region("japan", "Japan")]
        let sections = StreetZimCatalog.areaSections(in: regions, matching: "ısparta",
                                                     locale: Locale(identifier: "tr_TR"))

        XCTAssertEqual(sections.flatMap(\.regions).map(\.id), ["turkish-city"])
    }

    func testSearchTrimsSurroundingWhitespaceAndNewlines() {
        let regions = [region("silicon-valley", "Silicon Valley"), region("japan", "Japan")]
        let sections = StreetZimCatalog.areaSections(in: regions, matching: " \n\tSilicon Valley \r\n", locale: english)

        XCTAssertEqual(sections.flatMap(\.regions).map(\.id), ["silicon-valley"])
        for query in ["", " \n\t\r "] {
            let unfiltered = StreetZimCatalog.areaSections(in: regions, matching: query, locale: english)
            XCTAssertEqual(unfiltered.flatMap(\.regions).map(\.id), ["silicon-valley", "japan"])
        }
    }

    func testSearchMatchesIdentifiersWithSpacesOrHyphens() {
        let regions = [region("greater-la", "Greater Los Angeles"), region("japan", "Japan")]
        for query in ["GREATER LA", "greater-la", "  greater-la\n"] {
            let sections = StreetZimCatalog.areaSections(in: regions, matching: query, locale: english)
            XCTAssertEqual(sections.flatMap(\.regions).map(\.id), ["greater-la"])
        }
        let hyphenatedTitle = region("new-title-test", "Saint-Étienne")
        let sections = StreetZimCatalog.areaSections(in: [hyphenatedTitle], matching: "saint etienne", locale: english)
        XCTAssertEqual(sections.flatMap(\.regions).map(\.id), ["new-title-test"])
    }

    func testUnknownIdentifiersRemainAvailableWithoutTitleGuessing() {
        let unknown = region("new-area", "France")
        let known = region("germany", "Silicon Valley")
        let sections = StreetZimCatalog.areaSections(in: [unknown, known], locale: english)

        XCTAssertEqual(sections.map(\.group), [.country, .other])
        XCTAssertEqual(sections.map { $0.regions.map(\.id) }, [["germany"], ["new-area"]])
        let filtered = StreetZimCatalog.areaSections(in: [unknown, known], matching: "new area", locale: english)
        XCTAssertEqual(filtered.flatMap(\.regions).map(\.id), [unknown.id])
    }

    func testEmptyInputsAndUnmatchedSearchReturnNoSections() {
        XCTAssertTrue(StreetZimCatalog.areaSections(in: [], locale: english).isEmpty)
        let sections = StreetZimCatalog.areaSections(in: [region("japan", "Japan")],
                                                     matching: "no matching area", locale: english)
        XCTAssertTrue(sections.isEmpty)
    }

    func testVariantsWithIdenticalTitlesKeepDistinctIDsAndStableOrder() {
        let identifiers = ["switzerland-nosat-z13", "switzerland-light", "switzerland-nosat", "switzerland"]
        let regions = identifiers.map { region($0, "Switzerland and the Alps") }
        let sections = StreetZimCatalog.areaSections(in: regions, matching: "switzerland", locale: english)

        XCTAssertEqual(sections.map(\.group), [.country])
        XCTAssertEqual(sections.flatMap(\.regions).map(\.id), identifiers.sorted())
    }

    func testBundledGeographicCategoriesCorrectBuildTiersAndIncludeVariants() {
        let classifications: [(String, StreetZimCatalog.AreaGroup)] = [
            ("silicon-valley", .local), ("washington-dc", .local), ("california", .local),
            ("canada", .country), ("china", .country), ("russia", .country), ("united-states", .country),
            ("japan", .country), ("taiwan", .country),
            ("ukraine", .region), ("hispaniola", .region), ("austria-czech", .region),
            ("central-us", .region), ("europe", .region),
            ("africa-light", .region), ("switzerland-light", .country)
        ]
        for (identifier, expectedGroup) in classifications {
            // Deliberately unrelated titles ensure classification comes from bundled IDs.
            let sections = StreetZimCatalog.areaSections(in: [region(identifier, "An area")], locale: english)
            XCTAssertEqual(sections.map(\.group), [expectedGroup], identifier)
            XCTAssertEqual(sections.flatMap(\.regions).map(\.id), [identifier], identifier)
        }
    }

    func testMetadataNeverAddsUnavailableAreas() {
        let sections = StreetZimCatalog.areaSections(in: [region("japan", "Japan")], locale: english)

        XCTAssertEqual(sections.map(\.group), [.country])
        XCTAssertEqual(sections.flatMap(\.regions).map(\.id), ["japan"])
    }

    private func region(_ identifier: String, _ title: String) -> StreetZimCatalog.Region {
        let base = StreetZimCatalog.Base(file: "\(identifier).zim", size: 1_000,
                                         download: "https://example.org/\(identifier).zim", url: nil)
        let version = StreetZimCatalog.LanguageVersion(lang: "en", label: "English", name: "osm_en_\(identifier)",
                                                        recipe: "recipes/\(identifier)/en.json", size: 1_100,
                                                        downloadBytes: 100, md5: String(repeating: "0", count: 32))
        return StreetZimCatalog.Region(id: identifier, title: title, base: base, menu: [version])
    }
}
