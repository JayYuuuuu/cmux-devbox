import CmuxSettings
import CryptoKit
import Foundation

/// Where the DevBox team panel script comes from.
///
/// The app ships a copy (`Resources/devbox-sidebars/devbox.js`), but panel
/// changes are frequent and should not need an app release. The devbox the
/// panel's sessions connect to publishes the current script at
/// ``remotePath`` (scripts/devbox/publish-team-panel.sh). While the panel is
/// shown the app checks it every ``refreshInterval`` over a separate
/// non-interactive SSH connection with the session's own route and options,
/// the same way ``DevBoxCodexReset`` reaches the devbox.
///
/// Every copy starts with a header line
/// `// cmux-devbox-panel rev=<n> min-build=<CFBundleVersion>`. A fetched copy
/// is used only when its `min-build` is not newer than this app (it may rely on
/// data the app does not provide yet) and its `rev` is higher than the
/// bundled one's; otherwise the bundled copy is used. The chosen script is
/// written to one stable file (``activeScriptURL``), so the sidebar's file
/// watcher hot-reloads it in place when a newer copy arrives. Any I/O failure
/// falls back to the bundled script.
enum DevBoxTeamPanelSource {
    static let remotePath = ".local/share/cmux-devbox/panel/devbox.js"
    static let refreshInterval: TimeInterval = 300
    private static let retryInterval: TimeInterval = 60
    private static let timeout: TimeInterval = 20
    private static let maxScriptBytes = 2_000_000

    struct Header: Equatable {
        let rev: Int
        let minBuild: [Int]
    }

    /// Parses the first-line header; nil when it is missing or malformed.
    static func header(of script: String) -> Header? {
        guard let line = script.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first,
              line.hasPrefix("// cmux-devbox-panel ") else { return nil }
        var rev: Int?
        var minBuild: [Int]?
        for field in line.split(separator: " ") {
            let pair = field.split(separator: "=", maxSplits: 1).map(String.init)
            guard pair.count == 2 else { continue }
            if pair[0] == "rev" { rev = Int(pair[1]) }
            if pair[0] == "min-build" { minBuild = buildComponents(pair[1]) }
        }
        guard let rev, let minBuild, !minBuild.isEmpty else { return nil }
        return Header(rev: rev, minBuild: minBuild)
    }

    /// "112.41" → [112, 41]; nil when any component is not a number.
    static func buildComponents(_ text: String) -> [Int]? {
        let parts = text.split(separator: ".").map { Int($0) }
        guard !parts.isEmpty, !parts.contains(nil) else { return nil }
        return parts.compactMap { $0 }
    }

    static func isBuild(_ a: [Int], notNewerThan b: [Int]) -> Bool {
        for index in 0..<max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0
            let y = index < b.count ? b[index] : 0
            if x != y { return x < y }
        }
        return true
    }

    /// The script to run: `remote` when it is usable by `appBuild` and newer
    /// than `bundled`, else `bundled`.
    static func choose(bundled: String, remote: String?, appBuild: [Int]) -> String {
        guard let remote, let remoteHeader = header(of: remote),
              isBuild(remoteHeader.minBuild, notNewerThan: appBuild) else { return bundled }
        let bundledRev = header(of: bundled)?.rev ?? 0
        return remoteHeader.rev > bundledRev ? remote : bundled
    }

    // MARK: - Files

    private static var directory: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
              let bundleID = Bundle.main.bundleIdentifier else { return nil }
        return base.appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("devbox-panel", isDirectory: true)
    }

    private static var remoteCacheURL: URL? { directory?.appendingPathComponent("remote.js") }

    private static var appBuild: [Int] {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String)
            .flatMap(buildComponents) ?? [0]
    }

    /// The file the panel renders; resolved once, then kept current in place.
    static let activeScriptURL: URL? = prepareActiveScript()

    private static func prepareActiveScript() -> URL? {
        guard let bundledURL = DevBoxTeamPanel.bundledScriptURL else { return nil }
        guard let directory, let bundled = try? String(contentsOf: bundledURL, encoding: .utf8) else {
            return bundledURL
        }
        let active = directory.appendingPathComponent("devbox.js")
        let remote = remoteCacheURL.flatMap { try? String(contentsOf: $0, encoding: .utf8) }
        let chosen = choose(bundled: bundled, remote: remote, appBuild: appBuild)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if (try? String(contentsOf: active, encoding: .utf8)) != chosen {
                try chosen.write(to: active, atomically: true, encoding: .utf8)
            }
            return active
        } catch {
            return bundledURL
        }
    }

    /// Stores a freshly fetched copy and switches the active script to it
    /// when it wins ``choose(bundled:remote:appBuild:)``.
    @MainActor
    private static func adopt(remote: String) {
        guard let remoteCacheURL, let active = activeScriptURL,
              let bundledURL = DevBoxTeamPanel.bundledScriptURL, active != bundledURL,
              let bundled = try? String(contentsOf: bundledURL, encoding: .utf8) else { return }
        try? remote.write(to: remoteCacheURL, atomically: true, encoding: .utf8)
        let chosen = choose(bundled: bundled, remote: remote, appBuild: appBuild)
        if (try? String(contentsOf: active, encoding: .utf8)) != chosen {
            try? chosen.write(to: active, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Fetch

    @MainActor private static var nextAttempt = Date.distantPast
    @MainActor private static var inFlight = false

    /// Called while the panel builds its data; fetches at most once per
    /// interval and never blocks the caller.
    @MainActor
    static func refreshIfDue(tabManager: TabManager, actions: [CmuxResolvedConfigAction]) {
        guard CmuxDevBoxEdition.isActive, !inFlight, Date() >= nextAttempt,
              activeScriptURL != DevBoxTeamPanel.bundledScriptURL else { return }
        inFlight = true
        nextAttempt = Date().addingTimeInterval(retryInterval)
        let known = remoteCacheURL
            .flatMap { try? Data(contentsOf: $0) }
            .map { SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined() } ?? "none"
        let command = remoteCommand(knownSHA256: known)
        let limit = timeout
        let candidates = DevBoxTeamPanel.sessionForegroundProcesses(tabManager: tabManager, actions: actions)
        Task {
            defer { inFlight = false }
            guard let (_, session) = await DevBoxTeamPanel.firstSSHSession(in: candidates) else { return }
            let run = await Task.detached(priority: .utility) {
                try? session.runRemoteCommandSync(command, timeout: limit)
            }.value
            guard let run, run.status == 0 else { return }
            nextAttempt = Date().addingTimeInterval(refreshInterval)
            guard let newline = run.stdout.firstIndex(of: "\n") else { return }
            let marker = run.stdout[..<newline]
            guard marker == "new",
                  let script = decodeTransfer(String(run.stdout[run.stdout.index(after: newline)...])),
                  script.utf8.count <= maxScriptBytes, header(of: script) != nil else { return }
            adopt(remote: script)
        }
    }

    /// Prints `same` when the published file matches `knownSHA256`, else `new`
    /// followed by the file as base64 of `gzip -n`; exits 3 when nothing is
    /// published. Compressed because the SSH runner reads stdout only after
    /// the process exits, so the output must stay well under a pipe buffer.
    static func remoteCommand(knownSHA256: String) -> String {
        let script = """
        f="$HOME/\(remotePath)"; [ -f "$f" ] || exit 3; \
        h=$( (sha256sum "$f" 2>/dev/null || shasum -a 256 "$f") | cut -c1-64); \
        if [ "$h" = "\(knownSHA256)" ]; then echo same; else echo new; gzip -9 -n -c "$f" | base64; fi
        """
        return "sh -c '" + script.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Decodes ``remoteCommand(knownSHA256:)``'s payload: base64 of a gzip
    /// member with no optional header fields (`gzip -n` from a file sets
    /// none), i.e. a 10-byte header, raw DEFLATE data and an 8-byte trailer.
    static func decodeTransfer(_ base64: String) -> String? {
        guard let data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters),
              data.count > 18, data[data.startIndex] == 0x1f, data[data.startIndex + 1] == 0x8b,
              data[data.startIndex + 2] == 8, data[data.startIndex + 3] == 0 else { return nil }
        let deflate = data.subdata(in: (data.startIndex + 10)..<(data.endIndex - 8))
        guard let raw = try? (deflate as NSData).decompressed(using: .zlib) as Data else { return nil }
        return String(data: raw, encoding: .utf8)
    }
}
