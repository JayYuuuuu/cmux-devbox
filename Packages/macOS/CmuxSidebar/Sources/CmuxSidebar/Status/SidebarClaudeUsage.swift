public import Foundation

/// Claude Code subscription usage reported by a remote statusline over the
/// terminal stream, rendered as a compact badge under the workspace row.
///
/// Transport: the remote statusline writes an OSC 777 desktop notification
/// whose title is ``notificationTitle`` and whose body is the ``encoded``
/// form (`v1 who=<name> lb=<label> em=<email> pe=<payer> ps=<yyyy-mm-dd>
/// pc=<m|y> h5=<pct> h5r=<epoch> d7=<pct> d7r=<epoch>`; `lb`/`pe` are
/// percent-encoded, everything but the windows is optional). The app
/// consumes it instead of showing a notification and stores it as a status
/// entry under ``statusKey`` so it rides the existing sidebar plumbing.
public struct SidebarClaudeUsage: Equatable, Sendable {
    /// One rate-limit window (five-hour or weekly).
    public struct Window: Equatable, Sendable {
        /// Used share of the window, clamped to 0...100.
        public let usedPercent: Int
        /// When the window resets, if reported.
        public let resetsAt: Date?

        public init(usedPercent: Int, resetsAt: Date?) {
            self.usedPercent = min(100, max(0, usedPercent))
            self.resetsAt = resetsAt
        }

        /// Usage as of `now`: a window whose reset time has passed is empty.
        public func effectivePercent(now: Date) -> Int {
            if let resetsAt, resetsAt <= now { return 0 }
            return usedPercent
        }

        /// Seconds until reset, nil when unknown or already past.
        public func secondsUntilReset(now: Date) -> TimeInterval? {
            guard let resetsAt else { return nil }
            let remaining = resetsAt.timeIntervalSince(now)
            return remaining > 0 ? remaining : nil
        }
    }

    /// Status-entry key that stores the encoded payload on a workspace.
    public static let statusKey = "devbox.claude_usage"
    /// OSC 777 notification title that marks a usage report.
    public static let notificationTitle = "cmux-devbox-claude-usage"
    private static let maxNameLength = 24
    private static let maxLabelLength = 24
    private static let maxEmailLength = 64
    private static let maxPayerLength = 40
    /// Characters a percent-encoded `lb` keeps literally.
    private static let labelAllowed = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    /// Account label (the remote `claude-as` name), possibly empty.
    public let who: String
    /// Display name for the account (may contain spaces), possibly empty.
    public let label: String
    /// Login email of the account, possibly empty.
    public let email: String
    /// The account (email or name) that pays for the subscription, possibly empty.
    public let payer: String
    /// Day the subscription started, `yyyy-mm-dd`, possibly empty.
    public let subscribedOn: String
    /// Billing cycle: `m` (monthly) or `y` (yearly); empty when unknown.
    public let cycle: String
    public let fiveHour: Window?
    public let sevenDay: Window?

    public init(
        who: String,
        label: String = "",
        email: String = "",
        payer: String = "",
        subscribedOn: String = "",
        cycle: String = "",
        fiveHour: Window?,
        sevenDay: Window?
    ) {
        self.who = Self.sanitizedName(who)
        self.label = Self.sanitizedLabel(label)
        self.email = Self.sanitizedName(email, limit: Self.maxEmailLength)
        self.payer = Self.sanitizedLabel(payer, limit: Self.maxPayerLength)
        self.subscribedOn = Self.isISODate(subscribedOn) ? subscribedOn : ""
        self.cycle = cycle == "m" || cycle == "y" ? cycle : ""
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
    }

    /// Canonical body; parsing it round-trips.
    public var encoded: String {
        var parts = ["v1"]
        if !who.isEmpty { parts.append("who=\(who)") }
        if !label.isEmpty, let encoded = label.addingPercentEncoding(withAllowedCharacters: Self.labelAllowed) {
            parts.append("lb=\(encoded)")
        }
        if !email.isEmpty { parts.append("em=\(email)") }
        if !payer.isEmpty, let encoded = payer.addingPercentEncoding(withAllowedCharacters: Self.labelAllowed) {
            parts.append("pe=\(encoded)")
        }
        if !subscribedOn.isEmpty { parts.append("ps=\(subscribedOn)") }
        if !cycle.isEmpty { parts.append("pc=\(cycle)") }
        if let fiveHour {
            parts.append("h5=\(fiveHour.usedPercent)")
            if let reset = fiveHour.resetsAt { parts.append("h5r=\(Int(reset.timeIntervalSince1970))") }
        }
        if let sevenDay {
            parts.append("d7=\(sevenDay.usedPercent)")
            if let reset = sevenDay.resetsAt { parts.append("d7r=\(Int(reset.timeIntervalSince1970))") }
        }
        return parts.joined(separator: " ")
    }

    /// Parses a notification body; nil for anything that is not a v1 report
    /// carrying at least one window.
    public static func parse(_ body: String) -> SidebarClaudeUsage? {
        let tokens = body.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" })
        guard tokens.first == "v1" else { return nil }
        var fields: [String: String] = [:]
        for token in tokens.dropFirst() {
            guard let eq = token.firstIndex(of: "=") else { continue }
            fields[String(token[..<eq])] = String(token[token.index(after: eq)...])
        }
        func window(_ pctKey: String, _ resetKey: String) -> Window? {
            guard let raw = fields[pctKey], let pct = Double(raw), pct.isFinite else { return nil }
            let reset = fields[resetKey]
                .flatMap { Double($0) }
                .flatMap { $0 > 0 && $0.isFinite ? $0 : nil }
            return Window(
                usedPercent: Int(pct.rounded()),
                resetsAt: reset.map { Date(timeIntervalSince1970: $0) }
            )
        }
        let fiveHour = window("h5", "h5r")
        let sevenDay = window("d7", "d7r")
        guard fiveHour != nil || sevenDay != nil else { return nil }
        return SidebarClaudeUsage(
            who: fields["who"] ?? "",
            label: fields["lb"].flatMap { $0.removingPercentEncoding } ?? "",
            email: fields["em"] ?? "",
            payer: fields["pe"].flatMap { $0.removingPercentEncoding } ?? "",
            subscribedOn: fields["ps"] ?? "",
            cycle: fields["pc"] ?? "",
            fiveHour: fiveHour,
            sevenDay: sevenDay
        )
    }

    /// `yyyy-mm-dd` with digits in place; the calendar check is the panel's job.
    private static func isISODate(_ raw: String) -> Bool {
        let chars = Array(raw.utf8)
        guard chars.count == 10 else { return false }
        for (i, c) in chars.enumerated() {
            if i == 4 || i == 7 { guard c == UInt8(ascii: "-") else { return false } }
            else { guard c >= UInt8(ascii: "0"), c <= UInt8(ascii: "9") else { return false } }
        }
        return true
    }

    /// Keeps inner single spaces; drops control characters and trims.
    private static func sanitizedLabel(_ raw: String, limit: Int = maxLabelLength) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in raw.unicodeScalars where scalars.count < limit {
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                if let last = scalars.last, last != " " { scalars.append(" ") }
                continue
            }
            guard !CharacterSet.controlCharacters.contains(scalar) else { continue }
            scalars.append(scalar)
        }
        return String(scalars).trimmingCharacters(in: .whitespaces)
    }

    private static func sanitizedName(_ raw: String, limit: Int = maxNameLength) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in raw.unicodeScalars where scalars.count < limit {
            guard !CharacterSet.controlCharacters.contains(scalar),
                  !CharacterSet.whitespacesAndNewlines.contains(scalar),
                  scalar != "=" else { continue }
            scalars.append(scalar)
        }
        return String(scalars)
    }
}

/// Severity band used to tint a usage gauge.
public enum SidebarClaudeUsageLevel: Equatable, Sendable {
    case normal, elevated, critical

    public init(percent: Int) {
        switch percent {
        case ..<60: self = .normal
        case ..<85: self = .elevated
        default: self = .critical
        }
    }
}
