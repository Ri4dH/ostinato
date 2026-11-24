import Foundation
import SwiftData

/// Identifiers shared by the app, widgets and watch. The values come from
/// Info.plist keys set by the build configuration, so the bundle prefix is
/// defined in exactly one place (`Config/Shared.xcconfig`).
public struct AppIdentifiers: Sendable {
    public let appGroup: String?
    public let cloudKitContainer: String?

    public init(appGroup: String?, cloudKitContainer: String?) {
        self.appGroup = appGroup
        self.cloudKitContainer = cloudKitContainer
    }

    public static var current: AppIdentifiers {
        let info = Bundle.main.infoDictionary ?? [:]
        func value(_ key: String) -> String? {
            guard let v = info[key] as? String, !v.isEmpty, !v.contains("$(") else { return nil }
            return v
        }
        return AppIdentifiers(
            appGroup: value("OstinatoAppGroup"),
            cloudKitContainer: value("OstinatoCloudKitContainer")
        )
    }

    /// The shared container, falling back to the app's own Application
    /// Support folder when the App Group isn't available (e.g. unsigned builds).
    public var sharedDirectory: URL {
        if let appGroup,
           let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) {
            return url.appending(path: "Library/Application Support", directoryHint: .isDirectory)
        }
        return URL.applicationSupportDirectory
    }

    public var sharedDefaults: UserDefaults {
        appGroup.flatMap { UserDefaults(suiteName: $0) } ?? .standard
    }
}

/// Builds the SwiftData container.
public enum PracticeStore {
    public static let storeFileName = "Ostinato.store"

    public static var schema: Schema { Schema(versionedSchema: PracticeSchemaV1.self) }

    /// - Parameters:
    ///   - syncEnabled: `.private` CloudKit database when true, local-only when false.
    ///   - inMemory: for tests and previews.
    /// Falls back to a local-only store if CloudKit can't be set up, so the app
    /// never blocks on sync.
    public static func makeContainer(
        identifiers: AppIdentifiers = .current,
        syncEnabled: Bool,
        inMemory: Bool = false
    ) throws -> ModelContainer {
        if inMemory {
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
            return try ModelContainer(for: schema, migrationPlan: PracticeMigrationPlan.self, configurations: config)
        }
        let directory = identifiers.sharedDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: storeFileName)

        if syncEnabled, let containerID = identifiers.cloudKitContainer {
            let config = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .private(containerID))
            if let container = try? ModelContainer(
                for: schema, migrationPlan: PracticeMigrationPlan.self, configurations: config) {
                return container
            }
        }
        let config = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, migrationPlan: PracticeMigrationPlan.self, configurations: config)
    }
}
