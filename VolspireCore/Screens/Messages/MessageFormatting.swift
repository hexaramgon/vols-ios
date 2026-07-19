//
//  MessageFormatting.swift
//  Volspire
//
//  Date/time helpers for the messages UI, mirroring the web app's
//  `timeAgo` / `dividerLabel` formatting.
//

import Foundation

enum MessageTime {
    // Cached: parse() runs for every row of every message batch (50 per load /
    // poll), and allocating formatters + compiling the regex per call is real
    // main-thread cost. Both types are documented thread-safe once configured.
    nonisolated(unsafe) private static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    nonisolated(unsafe) private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    private static let tzSuffix =
        try! NSRegularExpression(pattern: #"[+-]\d\d:?\d\d$"#)

    /// ISO-8601 "now" for OUTPUT (optimistic comment inserts, analytics
    /// timestamps) — reuses the cached formatter instead of allocating an
    /// `ISO8601DateFormatter` per call. Same format as a fresh formatter's
    /// default (`.withInternetDateTime`, UTC).
    static func isoNow() -> String {
        plain.string(from: Date())
    }

    /// Parse a Postgres/ISO timestamp that may lack a timezone (treated as UTC,
    /// matching the web's `parseUtc`).
    static func parse(_ iso: String?) -> Date? {
        guard let iso, !iso.isEmpty else { return nil }
        let hasTZ = iso.contains("Z") || iso.contains("z")
            || tzSuffix.firstMatch(in: iso, range: NSRange(iso.startIndex..., in: iso)) != nil
        let normalized = hasTZ ? iso : iso + "Z"

        if let d = withFraction.date(from: normalized) { return d }
        return plain.date(from: normalized)
    }

    /// "now", "5m", "3h", "2d", "1w", "3mo", "2y" — mirrors the web's `timeAgo`.
    static func ago(_ date: Date?) -> String {
        guard let date else { return "" }
        let s = max(0, Int(Date().timeIntervalSince(date)))
        switch s {
        case ..<60: return "now"
        case ..<3600: return "\(s / 60)m"
        case ..<86400: return "\(s / 3600)h"
        case ..<604800: return "\(s / 86400)d"
        case ..<2592000: return "\(s / 604800)w"
        case ..<31536000: return "\(s / 2592000)mo"
        default: return "\(s / 31536000)y"
        }
    }

    /// "just now", "5m ago", "3h ago", "2d ago", "4w ago" — the long-suffix
    /// relative-time voice used by listing/marketplace surfaces (was re-rolled
    /// verbatim at two of them).
    static func agoLong(iso: String?) -> String {
        guard let iso, let date = parse(iso) else { return "" }
        let s = max(0, Int(Date().timeIntervalSince(date)))
        switch s {
        case ..<60: return "just now"
        case ..<3600: return "\(s / 60)m ago"
        case ..<86400: return "\(s / 3600)h ago"
        case ..<604800: return "\(s / 86400)d ago"
        default: return "\(s / 604800)w ago"
        }
    }

    /// Centered divider label between message groups: time today, "Yesterday HH:MM",
    /// weekday + time within a week, otherwise "Mon D · HH:MM" (mirrors `dividerLabel`).
    static func divider(_ date: Date) -> String {
        let cal = Calendar.current
        let time = date.formatted(date: .omitted, time: .shortened)
        if cal.isDateInToday(date) { return time }
        if cal.isDateInYesterday(date) { return "Yesterday \(time)" }
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: date), to: cal.startOfDay(for: Date())).day ?? 0
        if days < 7 {
            let weekday = date.formatted(.dateTime.weekday(.abbreviated))
            return "\(weekday) \(time)"
        }
        let monthDay = date.formatted(.dateTime.month(.abbreviated).day())
        return "\(monthDay) · \(time)"
    }
}
