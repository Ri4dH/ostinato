import Foundation

/// One CSV row: one segment of one session (what teachers ask for).
public struct CSVRow: Sendable, Hashable {
    public var start: Date
    public var end: Date
    public var minutes: Double
    public var instrument: String
    public var item: String
    public var category: String
    public var rating: Int?
    public var focus: Int?
    public var tags: [String]
    public var notes: String
}

public enum CSVExporter {
    public static let header = ["date", "start", "end", "minutes", "instrument", "item", "category",
                                "session_rating", "focus", "tags", "notes"]

    @MainActor
    public static func rows(from sessions: [PracticeSession]) -> [CSVRow] {
        sessions.sorted { $0.startDate < $1.startDate }.flatMap { session -> [CSVRow] in
            let segments = session.sortedSegments
            let base = CSVRow(
                start: session.startDate, end: session.endDate ?? session.startDate,
                minutes: session.activeDuration / 60, instrument: session.instrument?.name ?? "",
                item: "", category: "", rating: session.rating, focus: session.focus,
                tags: session.tags, notes: session.notes
            )
            guard !segments.isEmpty else { return [base] }
            return segments.map { seg in
                var row = base
                row.start = seg.startDate
                row.end = seg.endDate ?? seg.startDate.addingTimeInterval(seg.activeDuration)
                row.minutes = seg.activeDuration / 60
                row.item = seg.displayTitle
                row.category = seg.item?.category.rawValue ?? ""
                return row
            }
        }
    }

    public static func csv(_ rows: [CSVRow], timeZone: TimeZone = .current) -> String {
        let day = Date.ISO8601FormatStyle(timeZone: timeZone).year().month().day()
        let time = Date.ISO8601FormatStyle(timeZone: timeZone).time(includingFractionalSeconds: false)
        var lines = [header.joined(separator: ",")]
        for r in rows {
            let fields: [String] = [
                r.start.formatted(day),
                String(r.start.formatted(time).prefix(5)),
                String(r.end.formatted(time).prefix(5)),
                String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), r.minutes),
                r.instrument, r.item, r.category,
                r.rating.map(String.init) ?? "", r.focus.map(String.init) ?? "",
                r.tags.joined(separator: "; "), r.notes
            ]
            lines.append(fields.map(escape).joined(separator: ","))
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    /// RFC 4180 quoting, plus a guard against spreadsheet formula injection
    /// (cells starting with = + - @ are prefixed with an apostrophe).
    static func escape(_ field: String) -> String {
        var value = field
        if let first = value.first, "=+-@\t\r".contains(first), Double(value) == nil {
            value = "'" + value
        }
        if value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }
}
