// This file is part of Kiwix for iOS & macOS.
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import WebKit
import XCTest
@testable import Kiwix

final class ZIMCameraPermissionTests: XCTestCase {
    private let fileID = "DC87AAC5-A366-4BD4-8045-A054A376DB03"
    private let otherID = "7EE0518E-585F-40A9-9671-3E1438BD3F44"

    func testCameraAsksRatherThanGrantsForTheCurrentArchive() throws {
        let page = try XCTUnwrap(URL(string: "zim://\(fileID)/a/page.html"))
        XCTAssertEqual(ZIMCameraPermission.decision(
            for: .camera, origin: ("ZIM", fileID.lowercased(), 0), pageURL: page
        ), .prompt)
    }

    func testDifferentArchivesAndOpaqueOriginsCannotAskForCamera() throws {
        let page = try XCTUnwrap(URL(string: "zim://\(fileID)/index.html"))
        for host in [otherID, "", "not-a-zim-uuid", fileID + ".example.com"] {
            XCTAssertEqual(ZIMCameraPermission.decision(
                for: .camera, origin: ("zim", host, 0), pageURL: page
            ), .deny, host)
        }
    }

    func testOtherSchemesCannotBorrowAnArchiveCameraPermission() throws {
        let page = try XCTUnwrap(URL(string: "zim://\(fileID)/index.html"))
        for scheme in ["https", "http", "file", "about", "kiwix", ""] {
            XCTAssertEqual(ZIMCameraPermission.decision(
                for: .camera, origin: (scheme, fileID, 0), pageURL: page
            ), .deny, scheme)
        }
    }

    func testCameraRequiresACurrentZIMPageWithAValidArchiveIdentity() throws {
        let pages: [URL?] = [nil, URL(string: "about:blank"), URL(string: "https://\(fileID)/"),
                             URL(string: "zim://not-an-archive/index.html")]
        for page in pages {
            XCTAssertEqual(ZIMCameraPermission.decision(
                for: .camera, origin: ("zim", fileID, 0), pageURL: page
            ), .deny)
        }
    }

    func testPermissionsAreSeparatedByPort() throws {
        let page = try XCTUnwrap(URL(string: "zim://\(fileID):1234/index.html"))
        XCTAssertEqual(ZIMCameraPermission.decision(
            for: .camera, origin: ("zim", fileID, 0), pageURL: page
        ), .deny)
        XCTAssertEqual(ZIMCameraPermission.decision(
            for: .camera, origin: ("zim", fileID, 1234), pageURL: page
        ), .prompt)
    }

    func testCameraSupportDoesNotEnableMicrophoneAccess() throws {
        let page = try XCTUnwrap(URL(string: "zim://\(fileID)/index.html"))
        for type in [WKMediaCaptureType.microphone, .cameraAndMicrophone] {
            XCTAssertEqual(ZIMCameraPermission.decision(
                for: type, origin: ("zim", fileID, 0), pageURL: page
            ), .deny)
        }
    }
}
