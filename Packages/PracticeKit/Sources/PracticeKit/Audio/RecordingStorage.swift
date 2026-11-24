import Foundation

/// Where recording audio files live on disk. Metadata stays in SwiftData.
public struct RecordingStorage: Sendable {
    public let localBase: URL
    public let iCloudBase: URL?

    public init(localBase: URL, iCloudBase: URL?) {
        self.localBase = localBase
        self.iCloudBase = iCloudBase
    }

    /// `Application Support/Recordings` in the App Group, plus the iCloud
    /// Drive ubiquity container's `Recordings` folder when available.
    /// Call `ubiquityBase` off the main thread; it can block.
    public static func standard(identifiers: AppIdentifiers = .current, ubiquityBase: URL? = nil) -> RecordingStorage {
        RecordingStorage(
            localBase: identifiers.sharedDirectory.appending(path: "Recordings", directoryHint: .isDirectory),
            iCloudBase: ubiquityBase?.appending(path: "Documents/Recordings", directoryHint: .isDirectory)
        )
    }

    public static func newFileName() -> String { "\(UUID().uuidString).m4a" }

    /// Only plain file names (no separators, no "..", no hidden files).
    public static func isValidFileName(_ name: String) -> Bool {
        guard !name.isEmpty, name.count <= 128 else { return false }
        guard !name.contains("/"), !name.contains("\\"), !name.contains(":"), !name.hasPrefix(".") else { return false }
        guard !name.contains("\0"), name != "..", !name.contains("..") else { return false }
        return name.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) || "-_.".unicodeScalars.contains($0) }
    }

    public func baseDirectory(for location: FileLocation) -> URL? {
        switch location {
        case .local: localBase
        case .iCloud: iCloudBase
        }
    }

    /// `baseDirectory(for:)/audioFileName`, or nil if the name is unsafe or
    /// the location is unavailable.
    public func url(for fileName: String, at location: FileLocation) -> URL? {
        guard Self.isValidFileName(fileName), let base = baseDirectory(for: location) else { return nil }
        let url = base.appending(path: fileName, directoryHint: .notDirectory).standardizedFileURL
        guard url.deletingLastPathComponent().standardizedFileURL.path == base.standardizedFileURL.path else { return nil }
        return url
    }

    /// Total bytes used by files in a location.
    public func bytesUsed(at location: FileLocation) -> Int64 {
        guard let base = baseDirectory(for: location),
              let files = try? FileManager.default.contentsOfDirectory(
                at: base, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles])
        else { return 0 }
        return files.reduce(0) { sum, url in
            sum + Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }

    public func ensureDirectories() throws {
        try FileManager.default.createDirectory(at: localBase, withIntermediateDirectories: true)
        if let iCloudBase { try FileManager.default.createDirectory(at: iCloudBase, withIntermediateDirectories: true) }
    }
}
