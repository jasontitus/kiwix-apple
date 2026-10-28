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
import os

struct Database {
    static let shared: Database = {
        do {
            return try Database()
        } catch {
            fatalError("Unable to open the library database: \(error)")
        }
    }()

    private let container: NSPersistentContainer

    init(storeURL: URL? = nil, model: NSManagedObjectModel? = nil) throws {
        if let model {
            container = NSPersistentContainer(name: "DataModel", managedObjectModel: model)
        } else {
            container = NSPersistentContainer(name: "DataModel")
        }
        guard let description = container.persistentStoreDescriptions.first else {
            throw CocoaError(.fileReadUnknown)
        }
        if let storeURL {
            description.url = storeURL
        } else if ProcessInfo.processInfo.arguments.contains("testing") {
            description.url = URL(fileURLWithPath: "/dev/null")
        }
        #if DEBUG
        if storeURL == nil, let directory = try Self.uiTestStoreDirectory() {
            description.url = directory.appendingPathComponent("DataModel.sqlite")
        }
        #endif
        if let url = description.url {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
        }
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        var options = description.options
        options[NSMigratePersistentStoresAutomaticallyOption] = description.shouldMigrateStoreAutomatically as NSNumber
        options[NSInferMappingModelAutomaticallyOption] = description.shouldInferMappingModelAutomatically as NSNumber
        try container.persistentStoreCoordinator.addPersistentStore(
            ofType: description.type,
            configurationName: description.configuration,
            at: description.url,
            options: options
        )
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.name = "viewContext"
        container.viewContext.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
        container.viewContext.undoManager = nil
        container.viewContext.shouldDeleteInaccessibleFaults = true
    }

    var viewContext: NSManagedObjectContext { container.viewContext }

    func newBackgroundContext() -> NSManagedObjectContext {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
        return context
    }

    /// Close an isolated store before reopening it or removing its directory.
    func close() throws {
        container.viewContext.performAndWait {
            container.viewContext.automaticallyMergesChangesFromParent = false
            container.viewContext.reset()
        }
        for store in container.persistentStoreCoordinator.persistentStores {
            try container.persistentStoreCoordinator.remove(store)
        }
    }

    #if DEBUG
    static func uiTestStoreDirectory() throws -> URL? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-streetzim-ui-test-store") else { return nil }
        guard arguments.indices.contains(index + 1),
              let identifier = UUID(uuidString: arguments[index + 1]) else {
            throw CocoaError(.fileReadInvalidFileName)
        }
        return try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ).appendingPathComponent("StreetZimUITests", isDirectory: true)
            .appendingPathComponent(identifier.uuidString, isDirectory: true)
    }
    #endif
}
