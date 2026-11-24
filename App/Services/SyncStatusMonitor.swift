import CloudKit
import CoreData
import Foundation
import Observation

/// Reports iCloud sync state for Settings. Never blocks the app.
@MainActor
@Observable
final class SyncStatusMonitor {
    enum Status: Equatable {
        case off, signedOut, syncing, upToDate, storageFull, unavailable
    }

    private(set) var status: Status = .off
    @ObservationIgnored private var observer: NSObjectProtocol?

    var isSignedIn: Bool { FileManager.default.ubiquityIdentityToken != nil }

    func start(syncEnabled: Bool) {
        guard syncEnabled else { status = isSignedIn ? .off : .signedOut; return }
        guard isSignedIn else { status = .signedOut; return }
        status = .upToDate
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: .main
        ) { note in
            guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event else { return }
            let finished = event.endDate != nil
            let quota = (event.error as? CKError)?.code == .quotaExceeded
            let failed = event.error != nil
            MainActor.assumeIsolated {
                if quota { self.status = .storageFull } else if failed { self.status = .unavailable }
                else { self.status = finished ? .upToDate : .syncing }
            }
        }
    }

    var text: String {
        switch status {
        case .off: String(localized: "Off. Your data stays on this device.")
        case .signedOut: String(localized: "iCloud unavailable. You're signed out.")
        case .syncing: String(localized: "Syncing…")
        case .upToDate: String(localized: "Up to date")
        case .storageFull: String(localized: "iCloud storage full. New changes stay on this device.")
        case .unavailable: String(localized: "iCloud unavailable right now. Changes will sync later.")
        }
    }

    var symbol: String {
        switch status {
        case .off: "icloud.slash"
        case .signedOut, .unavailable: "exclamationmark.icloud"
        case .syncing: "arrow.triangle.2.circlepath.icloud"
        case .upToDate: "checkmark.icloud"
        case .storageFull: "xmark.icloud"
        }
    }
}
