// This file is part of Kiwix for iOS & macOS.
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct StreetZimAreaPicker: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var query: String
    @Binding private var selection: String
    let regions: [StreetZimCatalog.Region]

    init(regions: [StreetZimCatalog.Region], selection: Binding<String>, initialQuery: String) {
        self.regions = regions
        _selection = selection
        _query = State(initialValue: initialQuery)
    }

    var body: some View {
        let sections = StreetZimCatalog.areaSections(in: regions, matching: query, locale: locale)
        NavigationStack {
            List {
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ForEach(sections) { section in
                        NavigationLink {
                            StreetZimAreaGroupPicker(
                                section: section, selectedID: selection,
                                choose: choose, cancel: { dismiss() }
                            )
                        } label: {
                            HStack {
                                Label(section.group.title, systemImage: section.group.systemImage)
                                Spacer()
                                Text(section.regions.count, format: .number)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityIdentifier("streetzim_area_group_\(section.group.rawValue)")
                    }
                } else {
                    ForEach(sections) { section in
                        Section(section.group.title) {
                            ForEach(section.regions) { region in
                                StreetZimAreaRow(region: region, isSelected: region.id == selection) { choose(region) }
                            }
                        }
                    }
                }
            }
            .listStyle(.inset)
            .overlay {
                if sections.isEmpty {
                    ContentUnavailableView.search(text: query)
                        .accessibilityIdentifier("streetzim_area_empty")
                }
            }
            .searchable(text: $query, prompt: LocalString.common_search)
            .navigationTitle(LocalString.maps_region)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(LocalString.common_button_cancel) { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 440, idealWidth: 520, minHeight: 460, idealHeight: 560)
        #endif
    }

    private func choose(_ region: StreetZimCatalog.Region) {
        selection = region.id
        dismiss()
    }
}

private struct StreetZimAreaGroupPicker: View {
    @Environment(\.locale) private var locale
    @State private var query = ""
    let section: StreetZimCatalog.AreaSection
    let selectedID: String
    let choose: (StreetZimCatalog.Region) -> Void
    let cancel: () -> Void

    var body: some View {
        let matches = StreetZimCatalog.areaSections(in: section.regions, matching: query, locale: locale)
        List {
            ForEach(matches) { section in
                ForEach(section.regions) { region in
                    StreetZimAreaRow(region: region, isSelected: region.id == selectedID) { choose(region) }
                }
            }
        }
        .listStyle(.inset)
        .overlay {
            if matches.isEmpty {
                ContentUnavailableView.search(text: query)
                    .accessibilityIdentifier("streetzim_area_empty")
            }
        }
        .searchable(text: $query, prompt: LocalString.common_search)
        .navigationTitle(section.group.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(LocalString.common_button_cancel, action: cancel)
            }
        }
    }
}

private struct StreetZimAreaRow: View {
    let region: StreetZimCatalog.Region
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(region.title).foregroundStyle(.primary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark").foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("streetzim_area_\(region.id)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
