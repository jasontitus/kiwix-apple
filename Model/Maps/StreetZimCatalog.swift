// This file is part of Kiwix for iOS & macOS.
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

struct StreetZimCatalog: Decodable, Sendable {
    let format: String
    let regions: [Region]

    func validate() throws {
        guard format == "streetzim-build-index/1", Set(regions.map(\.id)).count == regions.count else {
            throw StreetZimError.invalidRecipe
        }
        for region in regions {
            guard !region.id.isEmpty, !region.title.isEmpty, region.base.size > 0,
                  Set(region.menu.map(\.lang)).count == region.menu.count else {
                throw StreetZimError.invalidRecipe
            }
            for version in region.menu {
                let (_, overflow) = region.base.size.addingReportingOverflow(version.downloadBytes)
                guard !overflow, version.size > 16, version.downloadBytes >= 0, !version.lang.isEmpty,
                      !version.name.isEmpty, StreetZimRecipe.isHex(version.md5, count: 32) else {
                    throw StreetZimError.invalidRecipe
                }
            }
        }
    }

    struct Region: Decodable, Identifiable, Sendable {
        let id: String
        let title: String
        let base: Base
        let menu: [LanguageVersion]

        func preferredLanguage(_ preferences: [String]) -> String? {
            for preference in preferences {
                let language = Locale.Language(identifier: preference).languageCode?.identifier(.alpha3)
                if let match = menu.first(where: {
                    $0.lang == preference || language != nil && Locale.Language(identifier: $0.lang).languageCode?.identifier(.alpha3) == language
                }) { return match.lang }
            }
            return menu.first(where: { $0.lang == "en" })?.lang ?? menu.first?.lang
        }
    }

    struct Base: Decodable, Sendable {
        let file: String
        let size: Int64
        let download: String
        let url: String?
    }

    struct LanguageVersion: Decodable, Identifiable, Sendable {
        let lang: String
        let label: String
        let name: String
        let recipe: String
        let size: Int64
        let downloadBytes: Int64
        let md5: String
        var id: String { lang }

        enum CodingKeys: String, CodingKey {
            case lang, label, name, recipe, size, md5
            case downloadBytes = "download_bytes"
        }

        func displayName(locale: Locale = .current) -> String {
            let translated = locale.localizedString(forLanguageCode: lang) ?? label
            return translated == label ? label : "\(translated) (\(label))"
        }
    }
}

struct StreetZimEndpoint: Sendable {
    // Same index and relative recipe paths as StreetZim's browser builder.
    let indexURL: URL
    let proxyURL: URL

    static var current: Self {
        let index = Bundle.main.object(forInfoDictionaryKey: "StreetZimCatalogURL") as? String
        let proxy = Bundle.main.object(forInfoDictionaryKey: "StreetZimProxyURL") as? String
        func configuredURL(_ value: String?, fallback: String) -> URL {
            if let value, let url = URL(string: value), url.scheme == "https", url.host != nil { return url }
            return URL(string: fallback)!
        }
        return Self(
            indexURL: configuredURL(index, fallback: "https://streetzim.web.app/build/recipes/index.json"),
            proxyURL: configuredURL(proxy, fallback: "https://streetzim-preview-proxy.tiltastech.workers.dev")
        )
    }

    func recipeURL(_ path: String) throws -> URL {
        // The index's paths are relative to /build/, not /build/recipes/.
        let root = indexURL.deletingLastPathComponent().deletingLastPathComponent()
        return try checkedURL(path, relativeTo: root)
    }

    func sourceURL(_ address: String) throws -> URL {
        try checkedURL(address.replacingOccurrences(of: "{proxy}", with: proxyURL.absoluteString))
    }

    private func checkedURL(_ address: String, relativeTo base: URL? = nil) throws -> URL {
        guard let url = URL(string: address, relativeTo: base)?.absoluteURL,
              url.scheme == "https", url.host != nil, url.user == nil, url.password == nil else {
            throw StreetZimError.invalidRecipe
        }
        return url
    }
}

enum StreetZimError: LocalizedError {
    case catalogUnavailable
    case invalidRecipe
    case invalidResponse
    case integrity
    case insufficientSpace
    case importFailed

    var errorDescription: String? {
        switch self {
        case .catalogUnavailable:
            return LocalString.maps_error_catalog
        case .invalidRecipe:
            return LocalString.maps_error_recipe
        case .invalidResponse:
            return LocalString.maps_error_response
        case .integrity:
            return LocalString.maps_error_integrity
        case .insufficientSpace:
            return LocalString.maps_error_space
        case .importFailed:
            return LocalString.maps_error_import
        }
    }
}
