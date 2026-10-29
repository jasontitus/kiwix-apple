// This file is part of Kiwix for iOS & macOS.
// SPDX-License-Identifier: GPL-3.0-or-later

import CoreData
#if os(iOS)
import UIKit
#endif
import Combine
import Defaults
import Foundation

@MainActor
final class StreetZimViewModel: ObservableObject {
    // Keep a composition alive when the user navigates between library tabs.
    static let shared = StreetZimViewModel()
    typealias RangeReader = @Sendable (
        URL, Int64, Int64, Int64, Bool, (@Sendable (Int64, Int64) -> Void)?
    ) async throws -> Data
    @Published private(set) var regions: [StreetZimCatalog.Region] = []
    @Published var regionID = ""
    @Published var language = ""
    @Published private(set) var isLoading = false
    @Published private(set) var isRunning = false
    @Published private(set) var written: Int64 = 0
    @Published private(set) var total: Int64 = 0
    @Published private(set) var transferProgress: (received: Int64, total: Int64)?
    @Published private(set) var status = ""
    @Published private(set) var errorMessage: String?
    @Published private(set) var completedID: UUID?
    private var preferredLanguage: String?
    private var job: Task<Void, Never>?
    private var activeOperationID: UUID?
    private let endpoint: StreetZimEndpoint
    private let cache: URL
    private let session: URLSession
    private let destination: URL?
    private let database: Database
    private let readRange: RangeReader

    init(
        endpoint: StreetZimEndpoint = .current,
        session: URLSession = .shared,
        cache: URL? = nil,
        destination: URL? = nil,
        database: Database = .shared,
        readRange: RangeReader? = nil
    ) {
        self.endpoint = endpoint
        self.session = session
        self.destination = destination
        self.database = database
        self.cache = cache ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("StreetZimChunks", isDirectory: true)
        self.readRange = readRange ?? { url, offset, length, size, cellular, progress in
            try await StreetZimHTTP.range(
                url, offset: offset, length: length, size: size,
                cellular: cellular, session: session, progress: progress
            )
        }
    }

    var region: StreetZimCatalog.Region? { regions.first { $0.id == regionID } }
    var version: StreetZimCatalog.LanguageVersion? { region?.menu.first { $0.lang == language } }
    var appLanguages: [String] { Bundle.main.preferredLocalizations + Locale.preferredLanguages }

    func load() async {
        guard !isLoading, !isRunning else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let catalog = try await StreetZimHTTP.json(
                endpoint.indexURL, as: StreetZimCatalog.self, session: session
            )
            try setCatalog(catalog)
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setCatalog(_ catalog: StreetZimCatalog) throws {
        try catalog.validate()
        regions = catalog.regions.filter { !$0.menu.isEmpty }.sorted {
            $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
        if region == nil { regionID = regions.first?.id ?? "" }
        selectLanguage()
    }

    func selectLanguage() {
        language = region?.preferredLanguage(([preferredLanguage].compactMap { $0 }) + appLanguages) ?? ""
        completedID = nil
        if !isRunning {
            status = ""
            errorMessage = nil
        }
    }

    func start() {
        guard !isRunning, let region, let version else { return }
        let operationID = UUID()
        activeOperationID = operationID
        let rangeReader = readRange
        isRunning = true
        errorMessage = nil
        completedID = nil
        written = 0
        total = version.size
        transferProgress = nil
        status = LocalString.maps_preparing
        let cellular = Defaults[.downloadUsingCellular]
        job = Task { [self] in
            #if os(iOS)
            let wasIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
            UIApplication.shared.isIdleTimerDisabled = true
            defer { UIApplication.shared.isIdleTimerDisabled = wasIdleTimerDisabled }
            #endif
            #if os(macOS)
            let directory = destination ?? DownloadLocationMac.load().directory
            #else
            let directory = destination ?? DownloadDestination.downloadLocalFolder()
            #endif
            let access = directory?.startAccessingSecurityScopedResource() ?? false
            defer {
                if access { directory?.stopAccessingSecurityScopedResource() }
                activeOperationID = nil
                isRunning = false
                transferProgress = nil
                job = nil
            }
            do {
                guard let directory else { throw CocoaError(.fileNoSuchFile) }
                let recipeURL = try endpoint.recipeURL(version.recipe)
                let recipe = try await StreetZimHTTP.json(
                    recipeURL, as: StreetZimRecipe.self, cellular: cellular, session: session
                )
                try await recipe.validateInBackground()
                // A catalog/recipe deployment changing between requests must not
                // silently download a different map from the one selected.
                guard recipe.md5 == version.md5, recipe.size == version.size,
                      recipe.base.file == region.base.file, recipe.base.size == region.base.size else {
                    throw StreetZimError.invalidRecipe
                }
                if let id = UUID(uuidString: recipe.uuid),
                   let existing = await ZimFileService.shared.getFileURL(zimFileID: id) {
                    let scope = existing.startAccessingSecurityScopedResource()
                    let exists = FileManager.default.fileExists(atPath: existing.path)
                    if scope { existing.stopAccessingSecurityScopedResource() }
                    if exists {
                        if let metadata = await LibraryOperations.open(url: existing, database: database) {
                            completedID = metadata.fileID
                            written = recipe.size
                            status = LocalString.maps_existing
                            return
                        }
                        // An unreadable archive is a reuse miss, not a permanent
                        // download failure. A readable archive's failed import
                        // still reports the persistence/access failure.
                        if await ZimFileService.getMetaData(url: existing) != nil {
                            throw StreetZimError.importFailed
                        }
                    }
                }
                let baseURL = try endpoint.sourceURL(region.base.url ?? region.base.download)
                let localBase = await reusableMap(for: region, recipe: recipe)
                status = LocalString.maps_composing
                let assembler = StreetZimAssembler(
                    endpoint: endpoint, cache: cache,
                    readRange: { [weak self] url, offset, length, size in
                        try await rangeReader(url, offset, length, size, cellular, { [weak self] received, total in
                            Task { @MainActor [weak self] in
                                guard let self, self.activeOperationID == operationID else { return }
                                self.transferProgress = (received, total)
                            }
                        })
                    }
                )
                let file = try await assembler.assemble(
                    recipe: recipe, baseURL: baseURL, localBase: localBase, destination: directory
                ) { [weak self] written, total in
                    await self?.updateProgress(written: written, total: total, operationID: operationID)
                }
                // Once the verified file is published, finish importing even if
                // Cancel was tapped at this boundary; never leave a half import.
                status = LocalString.maps_importing
                guard let metadata = await LibraryOperations.open(url: file, database: database) else {
                    throw StreetZimError.importFailed
                }
                completedID = metadata.fileID
                status = LocalString.maps_completed
            } catch {
                if Task.isCancelled {
                    status = LocalString.maps_cancelled
                } else {
                    errorMessage = error.localizedDescription
                    status = ""
                }
            }
        }
    }

    private func reusableMap(for region: StreetZimCatalog.Region, recipe: StreetZimRecipe) async -> URL? {
        if let baseID = UUID(uuidString: recipe.base.normalizedUUID),
           let url = await ZimFileService.shared.getFileURL(zimFileID: baseID) { return url }
        // A language version preserves the base's map bytes at their original
        // offsets. Try one already in the library; hashes decide what is reusable,
        // even across rebuilds. Different headers/tails fall back to the network.
        let request = ZimFile.fetchRequest(predicate: NSCompoundPredicate(andPredicateWithSubpredicates: [
            ZimFile.Predicate.isDownloaded(), NSPredicate(format: "isMissing == false"),
            NSPredicate(format: "persistentID IN %@", region.menu.map(\.name))
        ]))
        request.sortDescriptors = [NSSortDescriptor(keyPath: \ZimFile.created, ascending: false)]
        let ids = (try? database.viewContext.fetch(request).map(\.fileID)) ?? []
        for id in ids {
            if let url = await ZimFileService.shared.getFileURL(zimFileID: id) { return url }
        }
        return nil
    }

    func chooseLanguage(_ language: String) {
        self.language = language
        preferredLanguage = language
        completedID = nil
        if !isRunning {
            status = ""
            errorMessage = nil
        }
    }

    func cancel() {
        activeOperationID = nil
        job?.cancel()
    }

    func clearCache() {
        guard !isRunning else { return }
        do {
            if FileManager.default.fileExists(atPath: cache.path) {
                try FileManager.default.removeItem(at: cache)
            }
            status = LocalString.maps_cleared
        } catch { errorMessage = error.localizedDescription }
    }

    private func updateProgress(written: Int64, total: Int64, operationID: UUID) {
        guard activeOperationID == operationID else { return }
        self.written = written
        self.total = total
    }
}
