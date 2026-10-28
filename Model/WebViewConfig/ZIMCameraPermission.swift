// This file is part of Kiwix for iOS & macOS.
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import WebKit

/// Camera permission belongs to one archive origin, not every page in the app.
@MainActor
final class ZIMCameraPermission: NSObject, WKUIDelegate {
    static let shared = ZIMCameraPermission()

    private override init() { super.init() }

    func webView(
        _ webView: WKWebView,
        decideMediaCapturePermissionsFor origin: WKSecurityOrigin,
        initiatedBy _: WKFrameInfo,
        type: WKMediaCaptureType
    ) async -> WKPermissionDecision {
        Self.decision(
            for: type,
            origin: (origin.protocol, origin.host, origin.port),
            pageURL: webView.url
        )
    }

    nonisolated static func decision(
        for type: WKMediaCaptureType,
        origin: (scheme: String, host: String, port: Int),
        pageURL: URL?
    ) -> WKPermissionDecision {
        guard type == .camera,
              let pageURL, pageURL.isZIMURL,
              let fileID = pageURL.zimFileID,
              URLSchemeType(scheme: origin.scheme) == .zim,
              UUID(uuidString: origin.host) == fileID,
              origin.port == (pageURL.port ?? 0) else {
            return .deny
        }
        // WebKit still asks the user; never silently grant access to ZIM code.
        return .prompt
    }
}
