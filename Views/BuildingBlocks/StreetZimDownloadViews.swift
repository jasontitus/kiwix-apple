// This file is part of Kiwix for iOS & macOS.
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import SwiftUI

struct StreetZimSavedMapButton: View {
    @ObservedObject var zimFile: ZimFile
    let regions: [StreetZimCatalog.Region]
    let dismiss: (() -> Void)?

    var body: some View {
        let label = StreetZimMapLabel(
            persistentID: zimFile.persistentID, archiveTitle: zimFile.name,
            languageCodes: zimFile.languageCode, regions: regions
        )
        AsyncButton {
            guard let url = await ZimFileService.shared.getMainPageURL(zimFileID: zimFile.fileID) else { return }
            NotificationCenter.openURL(url, inNewTab: true)
            dismiss?()
        } label: {
            HStack {
                Label {
                    VStack(alignment: .leading) {
                        Text(label.title)
                        if !label.subtitle.isEmpty {
                            Text(label.subtitle)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } icon: {
                    Image(systemName: "map")
                }
                Spacer()
                Text(ByteCountFormatter.string(fromByteCount: zimFile.size, countStyle: .file))
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier("streetzim_installed_\(zimFile.fileID.uuidString)")
    }
}

struct StreetZimDownloadProgress: View {
    @ObservedObject var model: StreetZimViewModel

    var body: some View {
        ProgressView(value: Double(model.written), total: Double(max(1, model.total)))
        Text(LocalString.maps_progress(withArgs: size(model.written), size(model.total)))
            .monospacedDigit()
        if let transfer = model.transferProgress {
            Text(LocalString.maps_network_progress(withArgs: size(transfer.received), size(transfer.total)))
                .monospacedDigit()
        }
        if !model.status.isEmpty { Text(model.status) }
        Text(LocalString.maps_keep_open)
            .font(.caption).foregroundStyle(.secondary)
        Button(LocalString.maps_cancel, role: .cancel) { model.cancel() }
            .accessibilityIdentifier("streetzim_cancel")
    }

    private func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
