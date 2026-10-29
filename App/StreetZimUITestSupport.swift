// This file is part of Kiwix for iOS & macOS.
// SPDX-License-Identifier: GPL-3.0-or-later

#if DEBUG
import Foundation

@MainActor
enum StreetZimUITestSupport {
    static func prepare() async throws {
        guard let directory = try Database.uiTestStoreDirectory() else { return }
        guard let archive = Bundle.main.url(
            forResource: "streetzim-demo", withExtension: "zim", subdirectory: "StreetZimUITests"
        ), let index = Bundle.main.url(
            forResource: "streetzim-demo-index", withExtension: "json", subdirectory: "StreetZimUITests"
        ) else { throw CocoaError(.fileNoSuchFile) }
        let catalog = try JSONDecoder().decode(StreetZimCatalog.self, from: Data(contentsOf: index))
        try StreetZimViewModel.shared.setCatalog(catalog)

        // A marker separate from the map means relaunch exercises persistence,
        // and deleting the map cannot silently seed it again.
        let marker = directory.appendingPathComponent("fixture-seeded")
        guard !FileManager.default.fileExists(atPath: marker.path) else { return }
        #if os(macOS)
        let file = directory.appendingPathComponent("streetzim-ui-test.zim")
        #else
        let documents = try FileManager.default.url(
            for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        let file = documents.appendingPathComponent("streetzim-ui-test-\(directory.lastPathComponent).zim")
        #endif
        if !FileManager.default.fileExists(atPath: file.path) {
            try FileManager.default.copyItem(at: archive, to: file)
        }
        guard await LibraryOperations.open(url: file) != nil else { throw StreetZimError.importFailed }
        try Data().write(to: marker, options: .atomic)
    }
}
#endif
