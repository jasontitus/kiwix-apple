// This file is part of Kiwix for iOS & macOS.
// SPDX-License-Identifier: GPL-3.0-or-later

import Combine
import XCTest
@testable import Kiwix

final class LaunchViewModelTests: XCTestCase {
    @MainActor
    func testCachedCatalogDoesNotWaitForFirstVisit() {
        let library = LibraryProcess(defaultState: .complete)
        var browserLoading = Published<Bool?>(initialValue: nil)
        let model = CatalogLaunchViewModel(
            libraryState: library.$state,
            browserIsLoading: browserLoading.projectedValue
        )

        model.updateWith(hasZimFiles: false, hasSeenCategories: false)

        XCTAssertEqual(model.state, .catalog(.welcome(.complete)))
    }

    @MainActor
    func testFirstCatalogRefreshLeavesFetchingState() {
        let library = LibraryProcess(defaultState: .inProgress)
        var browserLoading = Published<Bool?>(initialValue: nil)
        let model = CatalogLaunchViewModel(
            libraryState: library.$state,
            browserIsLoading: browserLoading.projectedValue
        )
        model.updateWith(hasZimFiles: false, hasSeenCategories: false)
        XCTAssertEqual(model.state, .catalog(.fetching))

        library.state = .complete

        XCTAssertEqual(model.state, .catalog(.welcome(.complete)))
    }
}
