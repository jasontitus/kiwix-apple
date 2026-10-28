// This file is part of Kiwix for iOS & macOS.
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Provenance applies to the new Maps controls, not Kiwix's existing translations.
enum StreetZimLocalization {
    static let showsMachineTranslationNotice: Bool = {
        guard let localization = Bundle.main.preferredLocalizations.first,
              let url = Bundle.main.url(forResource: "MapsMachineTranslatedLocales", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let locales = try? PropertyListDecoder().decode([String].self, from: data) else { return false }
        return locales.contains(localization.lowercased())
    }()
}
