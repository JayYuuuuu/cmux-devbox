public import Foundation

/// Codex subscription usage reported by the remote agent hooks over the same
/// OSC 777 channel as ``SidebarClaudeUsage`` (title
/// ``SidebarClaudeUsage/notificationTitle``).
///
/// Body: `cx1 plan=<plan> h5=<pct> h5r=<epoch> d7=<pct> d7r=<epoch> ob=<epoch>`.
/// Codex reports up to two windows and says how long each is; the reporter
/// maps the five-hour window to `h5` and the weekly one to `d7` (Pro plans
/// only have the weekly one). `ob` is when Codex observed the numbers, so the
/// newest report wins no matter which workspace delivered it. The distinct
/// `cx1` version keeps older DevBox builds, which only know `v1`, from reading
/// it as a Claude report.
public struct SidebarCodexUsage: Equatable, Sendable {
    /// Status-entry key that stores the encoded payload on a workspace.
    public static let statusKey = "devbox.codex_usage"
    private static let version = "cx1"
    private static let maxPlanLength = 16

    /// Codex plan id as reported (`pro`, `plus`, `prolite`, ...), possibly empty.
    public let plan: String
    public let fiveHour: SidebarClaudeUsage.Window?
    public let sevenDay: SidebarClaudeUsage.Window?
    /// When Codex recorded these numbers, if reported.
    public let observedAt: Date?

    public init(
        plan: String,
        fiveHour: SidebarClaudeUsage.Window?,
        sevenDay: SidebarClaudeUsage.Window?,
        observedAt: Date?
    ) {
        self.plan = Self.sanitizedPlan(plan)
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
        self.observedAt = observedAt
    }

    /// Canonical body; parsing it round-trips.
    public var encoded: String {
        var parts = [Self.version]
        if !plan.isEmpty { parts.append("plan=\(plan)") }
        if let fiveHour {
            parts.append("h5=\(fiveHour.usedPercent)")
            if let reset = fiveHour.resetsAt { parts.append("h5r=\(Int(reset.timeIntervalSince1970))") }
        }
        if let sevenDay {
            parts.append("d7=\(sevenDay.usedPercent)")
            if let reset = sevenDay.resetsAt { parts.append("d7r=\(Int(reset.timeIntervalSince1970))") }
        }
        if let observedAt { parts.append("ob=\(Int(observedAt.timeIntervalSince1970))") }
        return parts.joined(separator: " ")
    }

    /// Parses a notification body; nil for anything that is not a cx1 report
    /// carrying at least one window.
    public static func parse(_ body: String) -> SidebarCodexUsage? {
        let tokens = body.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" })
        guard tokens.first.map(String.init) == version else { return nil }
        var fields: [String: String] = [:]
        for token in tokens.dropFirst() {
            guard let eq = token.firstIndex(of: "=") else { continue }
            fields[String(token[..<eq])] = String(token[token.index(after: eq)...])
        }
        func epoch(_ key: String) -> Date? {
            fields[key]
                .flatMap { Double($0) }
                .flatMap { $0 > 0 && $0.isFinite ? Date(timeIntervalSince1970: $0) : nil }
        }
        func window(_ pctKey: String, _ resetKey: String) -> SidebarClaudeUsage.Window? {
            guard let raw = fields[pctKey], let pct = Double(raw), pct.isFinite else { return nil }
            return SidebarClaudeUsage.Window(usedPercent: Int(pct.rounded()), resetsAt: epoch(resetKey))
        }
        let fiveHour = window("h5", "h5r")
        let sevenDay = window("d7", "d7r")
        guard fiveHour != nil || sevenDay != nil else { return nil }
        return SidebarCodexUsage(
            plan: fields["plan"] ?? "",
            fiveHour: fiveHour,
            sevenDay: sevenDay,
            observedAt: epoch("ob")
        )
    }

    private static func sanitizedPlan(_ raw: String) -> String {
        String(String.UnicodeScalarView(
            raw.unicodeScalars
                .filter { CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_" }
                .prefix(maxPlanLength)
        ))
    }
}
