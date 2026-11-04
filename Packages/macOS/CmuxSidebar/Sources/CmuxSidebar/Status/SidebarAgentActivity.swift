public import Foundation

/// What a remote coding agent (Claude Code, Codex) is doing, reported by its
/// hooks over the terminal stream.
///
/// Transport: the same OSC 777 channel as ``SidebarClaudeUsage`` (title
/// ``SidebarClaudeUsage/notificationTitle``), with a body of the form
/// `v1 ev=agent st=<state> at=<epoch> agent=<kind> who=<name> bg=<n> cx=<n> cxs=<epoch> d=<dir> t=<title>`
/// where `d` and `t` are percent-encoded. Reusing the title keeps older DevBox
/// builds quiet: they consume every report with that title and drop bodies
/// that are not usage reports, so this never surfaces as a notification. The
/// app stores the canonical form under ``statusKey``.
public struct SidebarAgentActivity: Equatable, Sendable {
    /// Lifecycle state of the agent's current turn.
    public enum State: String, Sendable, CaseIterable {
        /// Working on a prompt (thinking or running tools).
        case working
        /// Blocked on the user, e.g. a permission prompt.
        case waiting
        /// Finished its turn; the next prompt is up to the user.
        case done
        /// The agent session exited.
        case ended
    }

    /// Status-entry key that stores the encoded payload on a workspace.
    public static let statusKey = "devbox.agent_activity"
    private static let maxNameLength = 24
    private static let maxTextLength = 120

    public let state: State
    /// When the agent entered ``state``.
    public let since: Date
    /// Agent kind as reported (`claude`, `codex`), possibly empty.
    public let agent: String
    /// Account label (the remote `claude-as` name), possibly empty.
    public let who: String
    /// Last path component of the agent's working directory, possibly empty.
    public let directory: String
    /// The prompt that started the current turn, possibly empty.
    public let title: String
    /// Background shells the agent still has running (0 when not reported).
    public let backgroundShells: Int
    /// Codex runs the agent started and that are still going (`codex exec`
    /// from a Claude Code tool call), 0 when none.
    public let codexRuns: Int
    /// When the earliest of ``codexRuns`` started; nil when none or unknown.
    public let codexSince: Date?

    public init(
        state: State,
        since: Date,
        agent: String,
        who: String,
        directory: String,
        title: String,
        backgroundShells: Int = 0,
        codexRuns: Int = 0,
        codexSince: Date? = nil
    ) {
        self.state = state
        self.since = Date(timeIntervalSince1970: max(0, since.timeIntervalSince1970.rounded(.down)))
        self.agent = Self.sanitizedName(agent)
        self.who = Self.sanitizedName(who)
        self.directory = Self.sanitizedText(directory)
        self.title = Self.sanitizedText(title)
        self.backgroundShells = min(99, max(0, backgroundShells))
        self.codexRuns = min(99, max(0, codexRuns))
        self.codexSince = self.codexRuns > 0
            ? codexSince.flatMap { $0.timeIntervalSince1970 > 0 ? Date(timeIntervalSince1970: $0.timeIntervalSince1970.rounded(.down)) : nil }
            : nil
    }

    /// Canonical body; parsing it round-trips.
    public var encoded: String {
        var parts = ["v1", "ev=agent", "st=\(state.rawValue)", "at=\(Int(since.timeIntervalSince1970))"]
        if !agent.isEmpty { parts.append("agent=\(agent)") }
        if !who.isEmpty { parts.append("who=\(who)") }
        if backgroundShells > 0 { parts.append("bg=\(backgroundShells)") }
        if codexRuns > 0 {
            parts.append("cx=\(codexRuns)")
            if let codexSince { parts.append("cxs=\(Int(codexSince.timeIntervalSince1970))") }
        }
        if !directory.isEmpty { parts.append("d=\(Self.percentEncoded(directory))") }
        if !title.isEmpty { parts.append("t=\(Self.percentEncoded(title))") }
        return parts.joined(separator: " ")
    }

    /// Parses a notification body; nil for anything that is not a v1 agent report.
    public static func parse(_ body: String) -> SidebarAgentActivity? {
        let tokens = body.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" })
        guard tokens.first == "v1" else { return nil }
        var fields: [String: String] = [:]
        for token in tokens.dropFirst() {
            guard let eq = token.firstIndex(of: "=") else { continue }
            fields[String(token[..<eq])] = String(token[token.index(after: eq)...])
        }
        guard fields["ev"] == "agent",
              let state = fields["st"].flatMap(State.init(rawValue:)),
              let at = fields["at"].flatMap(Double.init), at.isFinite, at > 0 else {
            return nil
        }
        func text(_ key: String) -> String {
            guard let raw = fields[key] else { return "" }
            return decodedText(raw)
        }
        return SidebarAgentActivity(
            state: state,
            since: Date(timeIntervalSince1970: at),
            agent: fields["agent"] ?? "",
            who: fields["who"] ?? "",
            directory: text("d"),
            title: text("t"),
            backgroundShells: fields["bg"].flatMap { Int($0) } ?? 0,
            codexRuns: fields["cx"].flatMap { Int($0) } ?? 0,
            codexSince: fields["cxs"].flatMap { Double($0) }.flatMap { $0.isFinite ? Date(timeIntervalSince1970: $0) : nil }
        )
    }

    /// Percent-decodes `raw`. A body cut by the terminal's notification size
    /// limit can end in a partial escape or a partial UTF-8 sequence; drop the
    /// incomplete tail instead of showing the raw escapes.
    static func decodedText(_ raw: String) -> String {
        var candidate = Substring(raw)
        for _ in 0..<12 {
            if let decoded = String(candidate).removingPercentEncoding { return decoded }
            guard !candidate.isEmpty else { break }
            candidate = candidate.dropLast()
        }
        return ""
    }

    private static func percentEncoded(_ text: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }

    private static func sanitizedName(_ raw: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in raw.unicodeScalars where scalars.count < maxNameLength {
            guard !CharacterSet.controlCharacters.contains(scalar),
                  !CharacterSet.whitespacesAndNewlines.contains(scalar),
                  scalar != "=" else { continue }
            scalars.append(scalar)
        }
        return String(scalars)
    }

    /// Single line, control characters dropped, whitespace collapsed, capped.
    private static func sanitizedText(_ raw: String) -> String {
        var out = ""
        var pendingSpace = false
        for character in raw {
            if character.isWhitespace || character.isNewline {
                pendingSpace = !out.isEmpty
                continue
            }
            if character.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) {
                continue
            }
            if out.count >= maxTextLength { break }
            if pendingSpace {
                out.append(" ")
                pendingSpace = false
            }
            out.append(character)
        }
        return out
    }
}
