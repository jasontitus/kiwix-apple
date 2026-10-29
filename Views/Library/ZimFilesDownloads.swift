// This file is part of Kiwix for iOS & macOS.
//
// Kiwix is free software; you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by
// the Free Software Foundation; either version 3 of the License, or
// any later version.
//
// Kiwix is distributed in the hope that it will be useful, but
// WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
// General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with Kiwix; If not, see https://www.gnu.org/licenses/.

import CoreData
import SwiftUI

/// Active book/map downloads and locally available maps.
struct ZimFilesDownloads: View {
    @EnvironmentObject var selection: SelectedZimFileViewModel
    @ObservedObject private var mapModel = StreetZimViewModel.shared
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \DownloadTask.created, ascending: false)],
        predicate: NSPredicate(format: "zimFile != NULL"),
        animation: .easeInOut
    ) private var downloadTasks: FetchedResults<DownloadTask>
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \ZimFile.name, ascending: true)],
        predicate: ZimFile.downloadedMapsPredicate(),
        animation: .easeInOut
    ) private var downloadedMaps: FetchedResults<ZimFile>
    private let dismiss: (() -> Void)?

    init(dismiss: (() -> Void)?) {
        self.dismiss = dismiss
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if mapModel.isRunning {
                VStack(alignment: .leading, spacing: 8) {
                    Label(mapModel.region?.title ?? LocalString.maps_heading, systemImage: "map")
                        .font(.headline)
                    if let version = mapModel.version {
                        Text(version.displayName()).foregroundStyle(.secondary)
                    }
                    StreetZimDownloadProgress(model: mapModel)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(CellBackground.colorFor(isHovering: false, isSelected: false))
                .clipShape(CellBackground.clipShapeRectangle)
            }
            if !downloadTasks.isEmpty {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 250, maximum: 500), spacing: 12)],
                    alignment: .leading, spacing: 12
                ) {
                    ForEach(downloadTasks, id: \.fileID) { downloadTask in
                        if let zimFile = downloadTask.zimFile, zimFile.downloadTask != nil {
                            LibraryZimFileContext(
                                content: { DownloadTaskCell(zimFile) },
                                zimFile: zimFile,
                                selection: selection,
                                dismiss: dismiss)
                        }
                    }
                }
            }
            if !downloadedMaps.isEmpty {
                Text(LocalString.maps_downloaded).font(.headline)
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 250, maximum: 500), spacing: 12)],
                    alignment: .leading, spacing: 12
                ) {
                    ForEach(downloadedMaps, id: \.fileID) { zimFile in
                        StreetZimSavedMapButton(zimFile: zimFile, regions: mapModel.regions, dismiss: dismiss)
                            .buttonStyle(.plain)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(CellBackground.colorFor(isHovering: false, isSelected: false))
                            .clipShape(CellBackground.clipShapeRectangle)
                    }
                }
            }
        }
        .modifier(GridCommon())
        .modifier(ToolbarRoleBrowser())
        .navigationTitle(MenuItem.downloads.name)
        .overlay {
            if downloadTasks.isEmpty, downloadedMaps.isEmpty, !mapModel.isRunning {
                Message(text: LocalString.zim_file_downloads_overlay_empty_message)
            }
        }
    }
}
