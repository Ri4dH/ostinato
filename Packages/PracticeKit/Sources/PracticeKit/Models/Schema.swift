import Foundation
import SwiftData

/// Versioned schema so future model changes can migrate cleanly.
public enum PracticeSchemaV1: VersionedSchema {
    public static let versionIdentifier = Schema.Version(1, 0, 0)

    public static var models: [any PersistentModel.Type] {
        [
            Instrument.self,
            PracticeItem.self,
            PracticeSession.self,
            SessionSegment.self,
            PauseInterval.self,
            Recording.self,
            TempoEntry.self
        ]
    }
}

public enum PracticeMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [PracticeSchemaV1.self] }
    public static var stages: [MigrationStage] { [] }
}
