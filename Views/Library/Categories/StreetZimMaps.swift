// This file is part of Kiwix for iOS & macOS.
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreData
import Defaults
import SwiftUI

struct StreetZimMaps: View {
    @ObservedObject private var model = StreetZimViewModel.shared
    @Environment(\.locale) private var locale
    @Default(.downloadUsingCellular) private var downloadUsingCellular
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \ZimFile.name, ascending: true)],
        predicate: ZimFile.downloadedMapsPredicate(),
        animation: .default
    ) private var downloadedMaps: FetchedResults<ZimFile>
    let searchText: String
    let dismiss: (() -> Void)?

    private var matchingRegions: [StreetZimCatalog.Region] {
        model.regions.filter { searchText.isEmpty || $0.title.localizedStandardContains(searchText) }
    }

    var body: some View {
        Form {
            if !downloadedMaps.isEmpty {
                Section(LocalString.maps_downloaded) {
                    ForEach(downloadedMaps, id: \.fileID) { zimFile in
                        StreetZimSavedMapButton(zimFile: zimFile, regions: model.regions, dismiss: dismiss)
                    }
                }
            }
            Section {
                Label(LocalString.maps_heading, systemImage: "map")
                    .font(.headline)
                Text(LocalString.maps_introduction)
                    .foregroundStyle(.secondary)
                if StreetZimLocalization.showsMachineTranslationNotice {
                    Text(LocalString.maps_translation_notice)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("streetzim_translation_notice")
                }
            }
            if model.isLoading {
                ProgressView(LocalString.maps_loading)
            } else if model.regions.isEmpty {
                Section {
                    Text(LocalString.maps_empty)
                    Button(LocalString.maps_reload) { Task { await model.load() } }
                }
            } else {
                Section {
                    Picker(LocalString.maps_region, selection: $model.regionID) {
                        // Preserve the current selection while narrowing the list.
                        if let selected = model.region, !matchingRegions.contains(where: { $0.id == selected.id }) {
                            Text(selected.title).tag(selected.id)
                        }
                        ForEach(matchingRegions) { region in
                            Text(region.title).tag(region.id)
                        }
                    }
                    .accessibilityIdentifier("streetzim_region")
                    .onChange(of: model.regionID) { model.selectLanguage() }
                    Picker(LocalString.maps_language, selection: Binding(
                        get: { model.language }, set: { model.chooseLanguage($0) }
                    )) {
                        if let region = model.region {
                            let languages = region.languageGroups(locale: locale)
                            if !languages.local.isEmpty {
                                Section(LocalString.maps_local_languages) {
                                    ForEach(languages.local) { version in
                                        Text(version.displayName(locale: locale)).tag(version.lang)
                                    }
                                }
                            }
                            if languages.local.isEmpty {
                                ForEach(languages.other) { version in
                                    Text(version.displayName(locale: locale)).tag(version.lang)
                                }
                            } else if !languages.other.isEmpty {
                                Section(LocalString.maps_other_languages) {
                                    ForEach(languages.other) { version in
                                        Text(version.displayName(locale: locale)).tag(version.lang)
                                    }
                                }
                            }
                        }
                    }
                    .accessibilityIdentifier("streetzim_language")
                    Text(LocalString.maps_language_hint)
                        .font(.caption).foregroundStyle(.secondary)
                    Toggle(LocalString.zim_file_action_toggle_cellular, isOn: $downloadUsingCellular)
                    if let version = model.version {
                        LabeledContent(LocalString.maps_size, value: size(version.size))
                    }
                }
                .disabled(model.isRunning)
                Section {
                    if model.isRunning {
                        StreetZimDownloadProgress(model: model)
                    } else {
                        Button(LocalString.maps_download) { model.start() }
                            .buttonStyle(.borderedProminent)
                            .disabled(model.version == nil)
                            .accessibilityIdentifier("streetzim_download")
                    }
                    if !model.isRunning, !model.status.isEmpty { Text(model.status) }
                    if let fileID = model.completedID {
                        AsyncButton {
                            await openMap(fileID)
                        } label: {
                            Label(LocalString.maps_open, systemImage: "map")
                        }
                    }
                }
            }
            if let error = model.errorMessage {
                Section {
                    Text(error).foregroundStyle(.red).accessibilityIdentifier("streetzim_error")
                    if !model.regions.isEmpty {
                        Button(LocalString.maps_reload) { Task { await model.load() } }
                            .disabled(model.isRunning)
                    }
                }
            }
            Section {
                Button(LocalString.maps_clear_parts, role: .destructive) { model.clearCache() }
                    .disabled(model.isRunning)
            } footer: {
                Text(LocalString.maps_clear_hint)
            }
        }
        .formStyle(.grouped)
        .task { if model.regions.isEmpty { await model.load() } }
    }
    private func openMap(_ fileID: UUID) async {
        guard let url = await ZimFileService.shared.getMainPageURL(zimFileID: fileID) else { return }
        NotificationCenter.openURL(url, inNewTab: true)
        dismiss?()
    }

    private func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
