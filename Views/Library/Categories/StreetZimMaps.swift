// This file is part of Kiwix for iOS & macOS.
// SPDX-License-Identifier: GPL-3.0-or-later

import Defaults
import SwiftUI

struct StreetZimMaps: View {
    @ObservedObject private var model = StreetZimViewModel.shared
    @Default(.downloadUsingCellular) private var downloadUsingCellular
    let searchText: String
    let dismiss: (() -> Void)?

    private var matchingRegions: [StreetZimCatalog.Region] {
        model.regions.filter { searchText.isEmpty || $0.title.localizedStandardContains(searchText) }
    }

    var body: some View {
        Form {
            Section {
                Label(LocalString.maps_heading, systemImage: "map")
                    .font(.headline)
                Text(LocalString.maps_introduction)
                    .foregroundStyle(.secondary)
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
                    Picker(LocalString.maps_language, selection: Binding(get: { model.language }, set: { model.chooseLanguage($0) })) {
                        ForEach(model.region?.menu ?? []) { version in
                            Text(version.displayName()).tag(version.lang)
                        }
                    }
                    .accessibilityIdentifier("streetzim_language")
                    Text(LocalString.maps_language_hint)
                        .font(.caption).foregroundStyle(.secondary)
                    Toggle(LocalString.zim_file_action_toggle_cellular, isOn: $downloadUsingCellular)
                    if let version = model.version {
                        LabeledContent(LocalString.maps_size, value: size(version.size))
                        if let region = model.region {
                            LabeledContent(LocalString.maps_download_size, value: size(region.base.size + version.downloadBytes))
                        }
                        Text(LocalString.maps_reuse_hint)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .disabled(model.isRunning)
                Section {
                    if model.isRunning {
                        ProgressView(value: Double(model.written), total: Double(max(1, model.total)))
                        Text(LocalString.maps_progress(withArgs: size(model.written), size(model.total)))
                            .monospacedDigit()
                        Text(LocalString.maps_keep_open)
                            .font(.caption).foregroundStyle(.secondary)
                        Button(LocalString.maps_cancel, role: .cancel) { model.cancel() }
                    } else {
                        Button(LocalString.maps_download) { model.start() }
                            .buttonStyle(.borderedProminent)
                            .disabled(model.version == nil)
                            .accessibilityIdentifier("streetzim_download")
                    }
                    if !model.status.isEmpty { Text(model.status) }
                    if let fileID = model.completedID {
                        AsyncButton {
                            guard let url = await ZimFileService.shared.getMainPageURL(zimFileID: fileID) else { return }
                            NotificationCenter.openURL(url, inNewTab: true)
                            dismiss?()
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

    private func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
