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

        // Snapshot of StreetZim's cloud/region-languages.tsv; only offered
        // versions are promoted, never inferred from catalog insertion order.
        private static let localLanguageCodes: [String: Set<String>] = {
            guard let url = Bundle.main.url(forResource: "StreetZimRegionLanguages", withExtension: "plist"),
                  let data = try? Data(contentsOf: url),
                  let regions = try? PropertyListDecoder().decode([String: [String]].self, from: data) else {
                return [:]
            }
            return regions.mapValues { Set($0.map(languageCode)) }
        }()

        private static func languageCode(_ identifier: String) -> String {
            let language = Locale.Language(identifier: identifier)
            return language.languageCode?.identifier(.alpha3)
                ?? identifier.replacingOccurrences(of: "_", with: "-").lowercased().split(separator: "-")
                    .first.map(String.init) ?? identifier.lowercased()
        }

        func languageGroups(locale: Locale = .current) -> (local: [LanguageVersion], other: [LanguageVersion]) {
            let localCodes = Self.localLanguageCodes[id] ?? []
            let versions = menu.map { (version: $0, title: $0.displayName(locale: locale)) }.sorted {
                let order = $0.title.compare($1.title, options: .caseInsensitive, locale: locale)
                return order == .orderedSame ? $0.version.lang < $1.version.lang : order == .orderedAscending
            }
            var local: [LanguageVersion] = []
            var other: [LanguageVersion] = []
            for entry in versions {
                if localCodes.contains(Self.languageCode(entry.version.lang)) {
                    local.append(entry.version)
                } else {
                    other.append(entry.version)
                }
            }
            return (local, other)
        }

        func preferredLanguage(_ preferences: [String]) -> String? {
            for preference in preferences {
                let requested = Locale.Language(identifier: preference)
                let tag = preference.replacingOccurrences(of: "_", with: "-").lowercased()
                let code = requested.languageCode?.identifier(.alpha3)
                    ?? requested.minimalIdentifier.split(separator: "-").first.map(String.init)
                var best: LanguageVersion?
                var bestScore = 0
                for version in menu {
                    if version.lang.replacingOccurrences(of: "_", with: "-").lowercased() == tag {
                        return version.lang
                    }
                    let candidate = Locale.Language(identifier: version.lang)
                    let candidateCode = candidate.languageCode?.identifier(.alpha3)
                        ?? candidate.minimalIdentifier.split(separator: "-").first.map(String.init)
                    guard let code, code == candidateCode else { continue }
                    let score: Int
                    if candidate.minimalIdentifier == requested.minimalIdentifier {
                        score = 4
                    } else if candidate.maximalIdentifier == requested.maximalIdentifier {
                        score = 3
                    } else if candidate.script == requested.script {
                        score = 2
                    } else {
                        score = 1
                    }
                    if score > bestScore {
                        best = version
                        bestScore = score
                    }
                }
                if let best { return best.lang }
            }
            return menu.first(where: {
                Locale.Language(identifier: $0.lang).languageCode?.identifier(.alpha3) == "eng"
            })?.lang ?? menu.first?.lang
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

/// Presentation only: keep the archive's original title and other metadata intact.
struct StreetZimMapLabel {
    let title: String
    let subtitle: String

    init(persistentID: String, archiveTitle: String, languageCodes: String,
         regions: [StreetZimCatalog.Region], locale: Locale = .current) {
        var regionTitle: String?
        var language: String?
        for region in regions {
            if let version = region.menu.first(where: { $0.name == persistentID }) {
                regionTitle = region.title
                language = version.displayName(locale: locale)
                break
            }
        }
        if regionTitle == nil {
            // StreetZim's Name is osm_<language>_<region>, even without a catalog.
            let parts = persistentID.split(separator: "_", maxSplits: 2, omittingEmptySubsequences: false)
            if parts.count == 3, parts[0] == "osm", !parts[1].isEmpty {
                let words = parts[2].split(whereSeparator: { $0 == "_" || $0 == "-" })
                if !words.isEmpty {
                    regionTitle = words.joined(separator: " ").capitalized(with: locale)
                    let code = String(parts[1])
                    language = locale.localizedString(forLanguageCode: code) ?? code
                }
            }
        }
        let localizedLanguage = language ?? languageCodes.split(separator: ",").map {
            let code = String($0)
            return locale.localizedString(forLanguageCode: code) ?? code
        }.joined(separator: ", ")
        title = regionTitle ?? archiveTitle
        subtitle = [localizedLanguage, title == archiveTitle ? "" : archiveTitle]
            .filter { !$0.isEmpty }.joined(separator: " · ")
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
            proxyURL: configuredURL(proxy, fallback: "https://streetzim-build-proxy.tiltastech.workers.dev")
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
