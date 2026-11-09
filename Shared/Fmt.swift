import Foundation

enum Fmt {
    /// "2h 30m"
    static func hm(_ seconds: TimeInterval) -> String {
        let total = Int((seconds / 60).rounded())
        let h = total / 60, m = total % 60
        if h == 0 { return "\(m)m" }
        if m == 0 { return "\(h)h" }
        return "\(h)h \(m)m"
    }

    /// "2:30"
    static func colonHM(_ seconds: TimeInterval) -> String {
        let total = Int((seconds / 60).rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// "2.50"
    static func decimal(_ seconds: TimeInterval) -> String {
        String(format: "%.2f", seconds / 3600)
    }

    /// "01:02:03"
    static func clock(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        return String(format: "%02d:%02d:%02d", s / 3600, (s / 60) % 60, s % 60)
    }

    static func date(_ d: Date) -> String {
        d.formatted(date: .abbreviated, time: .omitted)
    }

    private static let isoFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// "2026-11-08" in the user's time zone.
    static func isoDate(_ d: Date) -> String { isoFormatter.string(from: d) }
}
