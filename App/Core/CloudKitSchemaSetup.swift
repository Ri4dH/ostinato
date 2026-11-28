#if DEBUG
import CoreData
import Foundation
import PracticeKit
import SwiftData
import os

/// Debug-only: pushes every SwiftData model's record type to the CloudKit
/// *development* environment so it can be deployed to production in the
/// CloudKit Console. Run once from Xcode with the `-initCloudKitSchema`
/// launch argument on a device signed into iCloud.
enum CloudKitSchemaSetup {
    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("-initCloudKitSchema")
    }

    private static let log = Logger(subsystem: "Ostinato", category: "CloudKitSchema")

    static func run(containerID: String) {
        // A throwaway store, so the app's real store is never touched.
        let url = URL.temporaryDirectory.appending(path: "schema-init-\(UUID().uuidString).store")
        let description = NSPersistentStoreDescription(url: url)
        description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: containerID)
        description.shouldAddStoreAsynchronously = false

        guard let model = NSManagedObjectModel.makeManagedObjectModel(for: PracticeSchemaV1.models) else {
            log.error("Couldn't build a managed object model from the SwiftData schema")
            return
        }
        let container = NSPersistentCloudKitContainer(name: "OstinatoSchema", managedObjectModel: model)
        container.persistentStoreDescriptions = [description]

        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError {
            log.error("Schema store failed to load: \(loadError.localizedDescription, privacy: .public)")
            return
        }
        do {
            try container.initializeCloudKitSchema()
            log.notice("CloudKit schema initialized in \(containerID, privacy: .public)")
        } catch {
            log.error("initializeCloudKitSchema failed: \(String(describing: error), privacy: .public)")
        }
        for store in container.persistentStoreCoordinator.persistentStores {
            try? container.persistentStoreCoordinator.remove(store)
        }
        try? FileManager.default.removeItem(at: url)
    }
}
#endif
