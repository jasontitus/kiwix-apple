// This file is part of Kiwix for iOS & macOS.
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest

@MainActor
final class AreaPickerUITests: XCTestCase {
    func testBrowseAndSearchMapAreas() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [
            "testing", "-streetzim-ui-test-store", UUID().uuidString,
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US"
        ]
        app.launch()
        let maps = app.staticTexts["Maps"].firstMatch
        XCTAssertTrue(maps.waitForExistence(timeout: 15))
        maps.click()
        let area = app.buttons["streetzim_region"]
        XCTAssertTrue(area.waitForExistence(timeout: 10))
        area.click()
        let countries = app.buttons["streetzim_area_group_country"]
        XCTAssertTrue(countries.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["streetzim_area_group_local"].exists)
        XCTAssertTrue(app.buttons["streetzim_area_group_region"].exists)
        record(app, name: "Mac map area categories")
        countries.click()
        let iceland = app.buttons["streetzim_area_iceland"]
        XCTAssertTrue(iceland.waitForExistence(timeout: 5))
        iceland.click()
        XCTAssertTrue(area.label.contains("Iceland"))

        area.click()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.click()
        search.typeText("washington")
        let washington = app.buttons["streetzim_area_washington-dc"]
        XCTAssertTrue(washington.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["streetzim_area_iceland"].exists)
        record(app, name: "Mac map area search")
        washington.click()
        XCTAssertTrue(area.label.contains("Washington"))

        area.click()
        let cities = app.buttons["streetzim_area_group_local"]
        XCTAssertTrue(cities.waitForExistence(timeout: 5))
        cities.click()
        app.buttons["Cancel"].firstMatch.click()
        XCTAssertTrue(area.label.contains("Washington"))
    }

    private func record(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
