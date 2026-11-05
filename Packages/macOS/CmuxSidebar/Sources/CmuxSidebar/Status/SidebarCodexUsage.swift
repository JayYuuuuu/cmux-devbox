public import Foundation

/// Codex subscription usage reported by the remote agent hooks over the same
/// OSC 777 channel as ``SidebarClaudeUsage`` (title
/// ``SidebarClaudeUsage/notificationTitle``).
///
/// Body: `cx1 plan=<plan> h5=<pct> h5r=<epoch> d7=<pct> d7r=<epoch> ob=<epoch>
/// rs=<n> rx=<epoch>,<epoch>,...`.
/// Codex reports up to two windows and says how long each is; the reporter
/// maps the five-hour window to `h5` and the weekly one to `d7` (Pro plans
/// only have the weekly one). `ob` is when Codex observed the numbers, so the
/// newest report wins no matter which workspace delivered it. The distinct
/// `cx1` version keeps older DevBox builds, which only know `v1`, from reading
/// it as a Claude report.
///
/// `rs` is how many usage limit resets ("reset cards") the account holds and
/// `rx` when each of them expires (0 when Codex gave no expiry); both are
/// omitted when the reporter could not ask. Builds before devbox.34 ignore them.
public struct SidebarCodexUsage: Equatable, Sendable {
    /// Status-entry key that stores the encoded payload on a workspace.
    public static let statusKey = "devbox.codex_usage"
    private static let version = "cx1"
    private static let maxPlanLength = 16
    private static let maxResetCredits = 16

    /// The account's unused usage limit resets, as last asked.
    public struct ResetCredits: Equatable, Sendable {
        /// How many resets were available when asked.
        public let count: Int
        /// When each of them expires, earliest first; resets without an
        /// expiry are counted but not listed.
        public let expiries: [Date]

        public init(count: Int, expiries: [Date]) {
            self.count = max(0, count)
            self.expiries = expiries.sorted()
        }

        /// Resets still usable at `now`: listed ones past their expiry are gone.
        public func available(now: Date) -> Int {
            max(0, count - expiries.filter { $0 <= now }.count)
        }
    }

    /// Codex plan id as reported (`pro`, `plus`, `prolite`, ...), possibly empty.
    public let plan: String
    public let fiveHour: SidebarClaudeUsage.Window?
    public let sevenDay: SidebarClaudeUsage.Window?
    /// When Codex recorded these numbers, if reported.
    public let observedAt: Date?
    /// Usage limit resets, nil when the reporter could not ask.
    public let resetCredits: ResetCredits?

    public init(
        plan: String,
        fiveHour: SidebarClaudeUsage.Window?,
        sevenDay: SidebarClaudeUsage.Window?,
        observedAt: Date?,
        resetCredits: ResetCredits? = nil
    ) {
        self.plan = Self.sanitizedPlan(plan)
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
        self.observedAt = observedAt
        self.resetCredits = resetCredits
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
        if let resetCredits {
            parts.append("rs=\(resetCredits.count)")
            if !resetCredits.expiries.isEmpty {
                parts.append("rx=" + resetCredits.expiries.map { String(Int($0.timeIntervalSince1970)) }.joined(separator: ","))
            }
        }
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
        var resetCredits: ResetCredits?
        if let raw = fields["rs"], let count = Int(raw), count >= 0 {
            let clamped = min(count, maxResetCredits)
            let expiries = (fields["rx"] ?? "")
                .split(separator: ",")
                .compactMap { Double($0) }
                .filter { $0 > 0 && $0.isFinite }
                .prefix(clamped)
                .map { Date(timeIntervalSince1970: $0) }
            resetCredits = ResetCredits(count: clamped, expiries: Array(expiries))
        }
        return SidebarCodexUsage(
            plan: fields["plan"] ?? "",
            fiveHour: fiveHour,
            sevenDay: sevenDay,
            observedAt: epoch("ob"),
            resetCredits: resetCredits
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
