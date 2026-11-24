import Foundation

/// Persists the in-progress session so it survives the app being killed.
public protocol ActiveSessionPersisting: Sendable {
    func load() -> ActiveSession?
    func save(_ session: ActiveSession) throws
    func clear() throws
}

/// Stores the active session as a small JSON file (atomic writes) in the App
/// Group container, so the app, widgets, intents and Live Activity share it.
public struct FileActiveSessionStore: ActiveSessionPersisting {
    public let fileURL: URL

    public init(directory: URL, fileName: String = "active-session.json") {
        self.fileURL = directory.appending(path: fileName, directoryHint: .notDirectory)
    }

    public func load() -> ActiveSession? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? Self.decoder.decode(ActiveSession.self, from: data)
    }

    public func save(_ session: ActiveSession) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try Self.encoder.encode(session)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    public func clear() throws {
        if FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .millisecondsSince1970
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .millisecondsSince1970
        return d
    }()
}

/// In-memory store for tests and previews.
public final class InMemoryActiveSessionStore: ActiveSessionPersisting, @unchecked Sendable {
    private let lock = NSLock()
    private var value: ActiveSession?

    public init(_ value: ActiveSession? = nil) { self.value = value }

    public func load() -> ActiveSession? { lock.withLock { value } }
    public func save(_ session: ActiveSession) throws { lock.withLock { value = session } }
    public func clear() throws { lock.withLock { value = nil } }
}
