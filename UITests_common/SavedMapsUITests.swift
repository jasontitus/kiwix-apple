// This file is part of Kiwix for iOS & macOS.
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
import UIKit

@MainActor
final class SavedMapsUITests: XCTestCase {
    func testSavedMapSurvivesNavigationRelaunchAndDeletion() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = isPad ? .landscapeLeft : .portrait
        let app = XCUIApplication()
        app.launchArguments = [
            "testing", "-streetzim-ui-test-store", UUID().uuidString,
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US"
        ]
        app.launch()
        navigate(to: "Maps", in: app)
        let map = savedMap(in: app)
        XCTAssertTrue(map.waitForExistence(timeout: 15))
        XCTAssertTrue(map.label.contains("English"))

        let language = app.buttons["streetzim_language"]
        reveal(language, in: app)
        language.tap()
        let french = app.buttons["French (Français)"]
        XCTAssertTrue(french.waitForExistence(timeout: 5))
        french.tap()
        XCTAssertTrue(map.exists)
        XCTAssertTrue(map.label.contains("English"))
        navigate(to: "Downloads", in: app)
        XCTAssertTrue(map.waitForExistence(timeout: 5))
        record(app, name: "Saved map in Downloads")
        map.tap()
        let mainPage = app.webViews.staticTexts["StreetZim test map"].firstMatch
        XCTAssertTrue(mainPage.waitForExistence(timeout: 15))
        app.webViews.links["Fixture detail"].firstMatch.tap()
        XCTAssertTrue(app.webViews.staticTexts["StreetZim fixture detail"].firstMatch.waitForExistence(timeout: 5))

        app.terminate()
        app.launch()
        navigate(to: "Downloads", in: app)
        XCTAssertTrue(map.waitForExistence(timeout: 15))
        map.tap()
        XCTAssertTrue(mainPage.waitForExistence(timeout: 15))
        record(app, name: "Real offline map opened after relaunch")

        navigate(to: "Opened", in: app)
        let entry = app.buttons[isPad ? "Open: StreetZim Demo" : "StreetZim Demo"].firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.tap()
        let delete = app.buttons["Delete"].firstMatch
        reveal(delete, in: app)
        delete.tap()
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertTrue(alert.staticTexts["Delete StreetZim Demo"].exists)
        alert.buttons["Delete"].tap()
        navigate(to: "Downloads", in: app)
        XCTAssertFalse(map.waitForExistence(timeout: 2))

        // Relaunch must not reseed a deleted map from the bundled fixture.
        app.terminate()
        app.launch()
        navigate(to: "Downloads", in: app)
        XCTAssertFalse(map.waitForExistence(timeout: 2))
    }

    func testAreaBrowserGroupsSearchAndCancellationPreserveLanguage() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = isPad ? .landscapeLeft : .portrait
        let app = XCUIApplication()
        app.launchArguments = [
            "testing", "-streetzim-ui-test-store", UUID().uuidString,
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US"
        ]
        app.launch()
        navigate(to: "Maps", in: app)
        let language = app.buttons["streetzim_language"]
        reveal(language, in: app)
        language.tap()
        let french = app.buttons["French (Français)"]
        XCTAssertTrue(french.waitForExistence(timeout: 5))
        french.tap()

        let area = app.buttons["streetzim_region"]
        area.tap()
        let countries = app.buttons["streetzim_area_group_country"]
        XCTAssertTrue(countries.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["streetzim_area_group_local"].exists)
        XCTAssertTrue(app.buttons["streetzim_area_group_region"].exists)
        XCTAssertTrue(app.buttons["streetzim_area_group_other"].exists)
        record(app, name: "Map areas grouped by geographic scope")
        countries.tap()
        let iceland = app.buttons["streetzim_area_iceland"]
        XCTAssertTrue(iceland.waitForExistence(timeout: 5))
        iceland.tap()
        XCTAssertTrue(area.label.contains("Iceland"))
        XCTAssertTrue(language.label.contains("French"))

        area.tap()
        let cities = app.buttons["streetzim_area_group_local"]
        XCTAssertTrue(cities.waitForExistence(timeout: 5))
        cities.tap()
        XCTAssertTrue(app.buttons["streetzim_area_washington-dc"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].firstMatch.tap()
        XCTAssertTrue(area.label.contains("Iceland"))

        area.tap()
        let search = try XCTUnwrap(app.searchFields.allElementsBoundByIndex.first { $0.isHittable })
        search.tap()
        search.typeText("WASHINGTON")
        let washington = app.buttons["streetzim_area_washington-dc"]
        XCTAssertTrue(washington.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["streetzim_area_iceland"].exists)
        record(app, name: "Search across geographic groups")
        washington.tap()
        XCTAssertTrue(area.label.contains("Washington"))
        XCTAssertTrue(language.label.contains("French"))
        XCTAssertTrue(savedMap(in: app).label.contains("English"))

        area.tap()
        let other = app.buttons["streetzim_area_group_other"]
        XCTAssertTrue(other.waitForExistence(timeout: 5))
        other.tap()
        let unknown = app.buttons["streetzim_area_testland"]
        XCTAssertTrue(unknown.waitForExistence(timeout: 5))
        unknown.tap()
        XCTAssertTrue(area.label.contains("Testland"))
        XCTAssertTrue(language.label.contains("French"))
    }

    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    private func savedMap(in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
            "streetzim_installed_", "StreetZim Demo"
        )).firstMatch
    }

    private func navigate(to title: String, in app: XCUIApplication) {
        if isPad {
            let destination = app.buttons[title.lowercased()]
            if !destination.isHittable { app.navigationBars.buttons.firstMatch.tap() }
            XCTAssertTrue(destination.waitForExistence(timeout: 10))
            destination.tap()
        } else {
            if !app.buttons["Done"].exists {
                let library = app.buttons["Library"]
                XCTAssertTrue(library.waitForExistence(timeout: 10))
                library.tap()
            }
            let tab = app.tabBars.buttons[title]
            if tab.exists {
                tab.tap()
            } else {
                app.tabBars.buttons["More"].tap()
                let destination = app.staticTexts[title].firstMatch
                XCTAssertTrue(destination.waitForExistence(timeout: 5))
                destination.tap()
            }
        }
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<6 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.exists && element.isHittable)
    }

    private func record(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
