import AppKit
import Bonsplit
import CmuxAppKitSupportUI
import CmuxFoundation
import CmuxSettings
import CmuxSwiftRender
import SwiftUI

// DevBox edition appearance: the terminal area drawn as an inset rounded card
// on a slightly darker canvas, and one-click color theme buttons at the bottom
// of the sidebar. Both are inert outside the edition.

/// DevBox sidebar width: a little wider than upstream's 240 so the team
/// panel's quota gauges and session lines fit without truncating.
enum DevBoxSidebarWidth {
    static let defaultWidth: Double = 280
    /// One-time bump of windows still at upstream's untouched default.
    static let migrationKey = "cmux.devbox.sidebarWidth280.v1"
    private static let upstreamDefaultWidth: Double = 240

    /// Whether this launch is the one that migrates; decided on the first
    /// restored window so every window of the launch gets the same answer.
    @MainActor private static var migratesThisLaunch: Bool?

    /// The width to restore: a window saved at exactly the old default
    /// (never dragged) moves to ``defaultWidth`` on the first launch of this
    /// version; any width the user chose is kept.
    @MainActor
    static func restoredWidth(_ width: Double, defaults: UserDefaults = .standard) -> Double {
        guard CmuxDevBoxEdition.isActive else { return width }
        let migrates: Bool
        if let decided = migratesThisLaunch {
            migrates = decided
        } else {
            migrates = !defaults.bool(forKey: migrationKey)
            migratesThisLaunch = migrates
            defaults.set(true, forKey: migrationKey)
        }
        return migrates && width == upstreamDefaultWidth ? defaultWidth : width
    }
}

/// Geometry and colors of the DevBox terminal card.
enum DevBoxCardChrome {
    /// `UserDefaults` switch; on by default in the edition
    /// (`defaults write com.cmuxterm.app.staging.devbox devbox.cardChrome -bool false` turns it off).
    static let enabledKey = "devbox.cardChrome"
    /// Gap between the card and the window edges, sidebar and titlebar.
    static let canvasInset: CGFloat = 8
    /// Card padding around its content. Must stay at least
    /// `cornerRadius * (1 - 1/sqrt(2))` so square, portal-hosted terminal
    /// corners never poke past the rounded card corners.
    static let contentInset: CGFloat = 4
    static let cornerRadius: CGFloat = 12

    /// Surface tabs: capsules in the edition, upstream's classic tabs elsewhere.
    static var tabStyle: BonsplitConfiguration.Appearance.TabStyle {
        CmuxDevBoxEdition.isActive ? .capsule : .classic
    }

    /// Rim colors from top to bottom: lit from above on dark cards (a faint
    /// white edge fading out), a slightly firmer hairline at the bottom on
    /// light cards so the card stays separated from a pale canvas.
    static func rimColors(forCard card: NSColor) -> [Color] {
        isDark(card)
            ? [Color.white.opacity(0.16), Color.white.opacity(0.05)]
            : [Color.black.opacity(0.08), Color.black.opacity(0.13)]
    }

    /// Card fill: the opaque composited terminal color, or the translucent
    /// terminal color when terminals are see-through over chrome glass.
    static func cardColor(for appearance: WindowAppearanceSnapshot) -> NSColor {
        guard appearance.chromeGlassTint != nil, appearance.terminalBackgroundOpacity < 0.999 else {
            return appearance.resolvedChromeBackgroundColor
        }
        return appearance.terminalBackgroundColor.withAlphaComponent(appearance.terminalBackgroundOpacity)
    }

    static func shadowColor(forCard card: NSColor) -> Color {
        Color.black.opacity(isDark(card) ? 0.35 : 0.10)
    }

    static func isEnabled(storedValue: Bool) -> Bool {
        CmuxDevBoxEdition.isActive && storedValue
    }

    static func isDark(_ color: NSColor) -> Bool {
        guard let rgb = color.usingColorSpace(.sRGB) else { return true }
        let luminance = 0.2126 * rgb.redComponent + 0.7152 * rgb.greenComponent + 0.0722 * rgb.blueComponent
        return luminance < 0.5
    }

    /// Canvas behind the card: a step darker than the card on dark themes.
    static func canvasColor(forCard card: NSColor) -> NSColor {
        card.blended(withFraction: isDark(card) ? 0.22 : 0.06, of: .black) ?? card
    }

    /// Hairline around the card: a little lighter than the card on dark themes.
    static func borderColor(forCard card: NSColor) -> NSColor {
        isDark(card)
            ? card.blended(withFraction: 0.10, of: .white) ?? card
            : card.blended(withFraction: 0.12, of: .black) ?? card
    }
}

extension DevBoxCardChrome {
    /// Selected-workspace fill that follows the terminal theme while the card
    /// layout is on and no explicit `workspaceColors.selectionColor` is set:
    /// a lifted step of the terminal background instead of the blue accent.
    static func sidebarSelectionColor(defaults: UserDefaults = .standard) -> NSColor? {
        let stored = defaults.object(forKey: enabledKey) as? Bool ?? true
        guard isEnabled(storedValue: stored) else { return nil }
        let background = GhosttyApp.shared.defaultBackgroundColor
        return isDark(background)
            ? background.blended(withFraction: 0.12, of: .white)
            : background.blended(withFraction: 0.10, of: .black)
    }
}

/// Draws the card around the workspace content. Branchless: when disabled the
/// insets are zero and the fills clear, so toggling never changes the identity
/// of the (portal-anchoring) content subtree.
struct DevBoxCardChromeModifier: ViewModifier {
    let isEnabled: Bool
    let cardColor: NSColor

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(
            cornerRadius: isEnabled ? DevBoxCardChrome.cornerRadius : 0,
            style: .continuous
        )
        content
            .padding(isEnabled ? DevBoxCardChrome.contentInset : 0)
            .background(
                shape
                    .fill(isEnabled ? Color(nsColor: cardColor) : .clear)
                    // Soft drop shadow lifts the card off the canvas.
                    .shadow(
                        color: isEnabled ? DevBoxCardChrome.shadowColor(forCard: cardColor) : .clear,
                        radius: isEnabled ? 10 : 0,
                        x: 0,
                        y: isEnabled ? 3 : 0
                    )
            )
            .overlay(
                shape
                    .strokeBorder(
                        LinearGradient(
                            colors: isEnabled
                                ? DevBoxCardChrome.rimColors(forCard: cardColor)
                                : [.clear, .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: isEnabled ? 1 : 0
                    )
                    .allowsHitTesting(false)
            )
            .padding(isEnabled ? DevBoxCardChrome.canvasInset : 0)
    }
}

/// DevBox command palette chrome: a rounded floating card in the terminal
/// theme's colors with a lit rim and a soft shadow, a recessed search field
/// and solid accent pills for the selected row. Upstream drawing elsewhere.
enum DevBoxPaletteChrome {
    static var isActive: Bool { CmuxDevBoxEdition.isActive }

    static let cornerRadius: CGFloat = 14
    static let rowHeight: CGFloat = 28
    static let rowCornerRadius: CGFloat = 8
    static let rowOuterInset: CGFloat = 6

    @MainActor
    private static var terminalBackground: NSColor { GhosttyApp.shared.defaultBackgroundColor }

    @MainActor
    static var isDark: Bool { DevBoxCardChrome.isDark(terminalBackground) }

    /// Panel fill: a lifted step of the terminal on dark themes, near paper
    /// white (keeping the theme's warmth) on light ones.
    @MainActor
    static var panelFill: Color {
        let bg = terminalBackground
        let fill = isDark
            ? bg.blended(withFraction: 0.07, of: .white) ?? bg
            : bg.blended(withFraction: 0.60, of: .white) ?? bg
        return Color(nsColor: fill)
    }

    @MainActor
    static var rimColors: [Color] {
        isDark
            ? [Color.white.opacity(0.16), Color.white.opacity(0.05)]
            : [Color.black.opacity(0.06), Color.black.opacity(0.12)]
    }

    @MainActor
    static var shadowColor: Color { Color.black.opacity(isDark ? 0.45 : 0.16) }

    @MainActor
    static var searchFieldFill: Color {
        isDark ? Color.white.opacity(0.07) : Color.black.opacity(0.05)
    }

    @MainActor
    static var hoverFill: Color {
        isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.045)
    }
}

/// The edition's quick-switch color themes. The non-Ghostty ones ship in the
/// app bundle (`Resources/devbox-themes`, copied by `scripts/build-devbox.sh`).
enum DevBoxThemeSwitcher {
    struct Theme: Identifiable, Equatable {
        let name: String
        let backgroundHex: String
        let accentHex: String
        var id: String { name }
    }

    static let themes: [Theme] = [
        Theme(name: "DevBox Mocha", backgroundHex: "#1e1e2e", accentHex: "#cba6f7"),
        Theme(name: "DevBox Tokyo Night", backgroundHex: "#1a1b26", accentHex: "#7aa2f7"),
        Theme(name: "DevBox Dracula", backgroundHex: "#282a36", accentHex: "#ff79c6"),
        Theme(name: "DevBox Forest", backgroundHex: "#1e2326", accentHex: "#a7c080"),
    ]

    /// Light counterparts for daytime: tinted paper backgrounds (never pure
    /// white), softened ink foregrounds (about 10-12:1) and ANSI colors kept
    /// at 5:1 (normal) / 4:1 (bright) so syntax colors stay distinct and legible.
    static let lightThemes: [Theme] = [
        Theme(name: "DevBox Paper", backgroundHex: "#f3ede1", accentHex: "#c15627"),
        Theme(name: "DevBox Sepia", backgroundHex: "#f1e6cf", accentHex: "#b5562b"),
        Theme(name: "DevBox Mist", backgroundHex: "#e9edf0", accentHex: "#2f6fd6"),
        Theme(name: "DevBox Ivory", backgroundHex: "#f2f0ed", accentHex: "#e0a030"),
    ]

    // Old theme resources contain the replacement palettes too, so existing
    // configurations update without rewriting a user's config on launch.
    // Normalize their names here to keep the selected swatch accurate.
    private static let legacyThemeNames: [String: String] = [
        "DevBox Charcoal": "DevBox Mocha",
        "DevBox Cinder": "DevBox Tokyo Night",
        "DevBox Cobalt": "DevBox Dracula",
    ]

    static func editableConfigURL() -> URL? {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return CmuxGhosttyConfigPathResolver().editableConfigURL(
            currentBundleIdentifier: Bundle.main.bundleIdentifier,
            appSupportDirectory: appSupport
        )
    }

    /// Name of the theme the managed block selects for dark appearance (the
    /// edition runs dark), or its single theme.
    static func currentThemeName() -> String? {
        guard let url = editableConfigURL(),
              let contents = try? String(contentsOf: url, encoding: .utf8),
              let raw = CmuxGhosttyManagedThemeBlock().rawThemeValue(in: contents) else {
            return nil
        }
        let parts = raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        if let dark = parts.first(where: { $0.hasPrefix("dark:") }) {
            let name = String(dark.dropFirst("dark:".count))
            return legacyThemeNames[name] ?? name
        }
        guard parts.count == 1 && !raw.contains(":") else { return nil }
        return legacyThemeNames[raw] ?? raw
    }

    /// Selects `theme` for both appearances through the same managed block as
    /// `cmux themes set`, then requests the same reload the CLI does.
    static func apply(_ theme: Theme) {
        guard let url = editableConfigURL() else { return }
        do {
            try CmuxGhosttyManagedThemeBlock().write(
                rawThemeValue: "light:\(theme.name),dark:\(theme.name)",
                to: url
            )
        } catch {
            NSSound.beep()
            return
        }
        requestConfigReload()
    }

    /// Same reload request `cmux themes set` sends; the app's observer
    /// filters on the bundle id and runs the final-phase reload.
    static func requestConfigReload() {
        DistributedNotificationCenter.default().post(
            name: Notification.Name("com.cmuxterm.themes.reload-config"),
            object: nil,
            userInfo: [
                "bundleIdentifier": Bundle.main.bundleIdentifier ?? "",
                "phase": "final",
            ]
        )
    }
}

/// See-through terminals: a managed block at the end of the edition's
/// `config.ghostty` lowers `background-opacity`, so terminals show the window
/// glass behind them. Off by default: every redraw then recomposites the
/// glass (more GPU while output scrolls) and text contrast drops.
enum DevBoxTerminalGlass {
    static let opacity = 0.80
    private static let startMarker = "# cmux devbox glass start"
    private static let endMarker = "# cmux devbox glass end"

    static func isOn() -> Bool {
        guard let url = DevBoxThemeSwitcher.editableConfigURL(),
              let contents = try? String(contentsOf: url, encoding: .utf8) else { return false }
        return contents.contains(startMarker)
    }

    /// Config text with the block removed, then appended when `on`; later
    /// lines win in Ghostty, so the block overrides the file's own opacity.
    static func contents(_ contents: String, settingOn on: Bool) -> String {
        var lines = contents.components(separatedBy: "\n")
        if let start = lines.firstIndex(of: startMarker),
           let end = lines[start...].firstIndex(of: endMarker) {
            lines.removeSubrange(start...end)
        }
        var text = lines.joined(separator: "\n")
        if on {
            if !text.isEmpty && !text.hasSuffix("\n") { text += "\n" }
            text += "\(startMarker)\nbackground-opacity = \(opacity)\n\(endMarker)\n"
        }
        return text
    }

    static func set(_ on: Bool) {
        guard let url = DevBoxThemeSwitcher.editableConfigURL() else { return }
        let current = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try contents(current, settingOn: on).write(to: url, atomically: true, encoding: .utf8)
        } catch {
            NSSound.beep()
            return
        }
        DevBoxThemeSwitcher.requestConfigReload()
    }
}

/// Theme swatches shown above the sidebar footer buttons: dark themes, a
/// wider gap, then light themes on one row; two rows when the sidebar is too
/// narrow for one.
struct DevBoxThemeSwitcherRow: View {
    @State private var activeThemeName: String?
    @State private var terminalGlassOn = false

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                swatchRow(DevBoxThemeSwitcher.themes).fixedSize()
                swatchRow(DevBoxThemeSwitcher.lightThemes).fixedSize()
                glassToggle
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 4) {
                swatchRow(DevBoxThemeSwitcher.themes)
                HStack(spacing: 8) {
                    swatchRow(DevBoxThemeSwitcher.lightThemes)
                    glassToggle
                }
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 10)
        .onAppear {
            activeThemeName = DevBoxThemeSwitcher.currentThemeName()
            terminalGlassOn = DevBoxTerminalGlass.isOn()
        }
        // A theme picked elsewhere (Settings, `cmux themes set`) changes the
        // terminal background; re-read the selection then.
        .onReceive(NotificationCenter.default.publisher(for: .ghosttyDefaultBackgroundDidChange)) { _ in
            activeThemeName = DevBoxThemeSwitcher.currentThemeName()
            terminalGlassOn = DevBoxTerminalGlass.isOn()
        }
    }

    private var glassToggle: some View {
        let help = terminalGlassOn
            ? String(localized: "devbox.glassTerminal.turnOff", defaultValue: "Make the terminal opaque again")
            : String(localized: "devbox.glassTerminal.turnOn", defaultValue: "Make the terminal see-through glass (uses more GPU while output scrolls)")
        return Button {
            DevBoxTerminalGlass.set(!terminalGlassOn)
            terminalGlassOn = DevBoxTerminalGlass.isOn()
        } label: {
            DevBoxGlassToggleLabel(isOn: terminalGlassOn)
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(Text(help))
        .accessibilityAddTraits(terminalGlassOn ? .isSelected : [])
    }

    private func swatchRow(_ themes: [DevBoxThemeSwitcher.Theme]) -> some View {
        HStack(spacing: 8) {
            ForEach(themes) { theme in
                let isActive = theme.name == activeThemeName
                Button {
                    DevBoxThemeSwitcher.apply(theme)
                    activeThemeName = DevBoxThemeSwitcher.currentThemeName()
                } label: {
                    DevBoxThemeSwatch(theme: theme, isActive: isActive)
                }
                .buttonStyle(.plain)
                .help(Text(verbatim: theme.name))
                .accessibilityLabel(Text(verbatim: theme.name))
                .accessibilityAddTraits(isActive ? .isSelected : [])
            }
        }
    }
}

/// Same footprint as a theme swatch: a glassy disc with a half-filled drop;
/// an accent ring while terminal glass is on.
private struct DevBoxGlassToggleLabel: View {
    let isOn: Bool
    @State private var isHovered = false

    var body: some View {
        ZStack {
            Circle().fill(.ultraThinMaterial)
            Circle().strokeBorder(Color.primary.opacity(isHovered ? 0.40 : 0.20), lineWidth: 1)
            Image(systemName: isOn ? "drop.fill" : "drop.halffull")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(isOn ? 0.9 : 0.6))
        }
        .frame(width: 18, height: 18)
        .padding(3)
        .overlay(
            Circle()
                .strokeBorder(Color.accentColor, lineWidth: 2)
                .opacity(isOn ? 1 : 0)
        )
        .contentShape(Circle())
        .onHover { isHovered = $0 }
    }
}

private struct DevBoxThemeSwatch: View {
    let theme: DevBoxThemeSwitcher.Theme
    let isActive: Bool
    @State private var isHovered = false

    var body: some View {
        let background = Color(nsColor: NSColor(hex: theme.backgroundHex) ?? .black)
        let accent = Color(nsColor: NSColor(hex: theme.accentHex) ?? .orange)
        // Rim contrasts with the swatch itself, so dark and light swatches
        // both read on either sidebar appearance.
        let isDarkSwatch = DevBoxCardChrome.isDark(NSColor(hex: theme.backgroundHex) ?? .black)
        let rim = isDarkSwatch
            ? Color.white.opacity(isHovered ? 0.45 : 0.22)
            : Color.black.opacity(isHovered ? 0.40 : 0.18)
        ZStack {
            Circle().fill(background)
            Circle()
                .strokeBorder(rim, lineWidth: 1)
            Circle()
                .fill(accent)
                .frame(width: 7, height: 7)
        }
        .frame(width: 18, height: 18)
        .padding(3)
        .overlay(
            Circle()
                .strokeBorder(accent, lineWidth: 2)
                .opacity(isActive ? 1 : 0)
        )
        .contentShape(Circle())
        .onHover { isHovered = $0 }
    }
}

/// The DevBox team panel ships inside the app (`Resources/devbox-sidebars`)
/// instead of being installed per Mac, so it must not carry any machine
/// specifics. It reads the session list from the user's own `cmux.json`
/// quick-entry actions instead: every workspace action tagged with the
/// `devbox` keyword whose layout is a single terminal command.
enum DevBoxTeamPanel {
    /// Custom-sidebar name; the provider id is `cmux.sidebar.custom.devbox`.
    static let sidebarName = "devbox"
    /// Top-level custom-sidebar data key holding the session list.
    static let sessionsDataKey = "devboxSessions"
    /// Top-level custom-sidebar data key: "light" or "dark".
    static let schemeDataKey = "devboxScheme"
    static let keyword = "devbox"

    /// The bundled panel script. ``DevBoxTeamPanelSource`` renders it, or a
    /// newer copy published on the devbox, for ``sidebarName`` in the edition;
    /// either takes precedence over a same-named user file: older installs
    /// wrote a per-machine copy there, which would otherwise shadow updates.
    static var bundledScriptURL: URL? {
        guard CmuxDevBoxEdition.isActive else { return nil }
        return Bundle.main.url(forResource: sidebarName, withExtension: "js", subdirectory: "devbox-sidebars")
    }

    struct Session: Equatable {
        /// cmux.json action id; the panel opens a session by running it, the
        /// same path as its keyboard shortcut.
        let actionID: String
        let title: String
        let group: String
        let command: String
        let order: String
    }

    /// Sessions in shortcut order (⌃⌥1, ⌃⌥2, …), then title order.
    static func sessions(from actions: [CmuxResolvedConfigAction]) -> [Session] {
        actions.compactMap { action -> Session? in
            guard action.keywords.contains(keyword),
                  case let .workspace(definition, _) = action.action,
                  case let .pane(pane)? = definition.layout,
                  pane.surfaces.count == 1,
                  pane.surfaces[0].type == .terminal,
                  let command = pane.surfaces[0].command?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !command.isEmpty else { return nil }
            let title = (definition.name ?? action.title).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }
            return Session(
                actionID: action.id,
                title: title,
                group: groupName(for: title),
                command: command,
                order: action.shortcut.map { "0" + $0.key } ?? "1" + title
            )
        }
        .sorted { ($0.order, $0.title) < ($1.order, $1.title) }
    }

    /// "主号 2" → "主号"; a title without a trailing number is its own group.
    static func groupName(for title: String) -> String {
        let parts = title.split(separator: " ")
        guard parts.count > 1, let last = parts.last, last.allSatisfy(\.isNumber) else { return title }
        return parts.dropLast().joined(separator: " ")
    }

    /// Whether `actionID` names one of the panel's session entries; the
    /// `devbox.session.open` socket method runs nothing else.
    static func isSessionAction(_ actionID: String, in actions: [CmuxResolvedConfigAction]) -> Bool {
        sessions(from: actions).contains { $0.actionID == actionID }
    }

    /// Live terminals of open panel sessions with their foreground process,
    /// the candidates for reaching the devbox over a separate SSH connection.
    @MainActor
    static func sessionForegroundProcesses(
        tabManager: TabManager,
        actions: [CmuxResolvedConfigAction]
    ) -> [(workspace: Workspace, pid: Int32)] {
        let titles = Set(sessions(from: actions).map(\.title))
        var candidates: [(workspace: Workspace, pid: Int32)] = []
        for workspace in tabManager.tabs where titles.contains(workspace.title) {
            for case let terminal as TerminalPanel in workspace.panels.values {
                guard terminal.surface.hasLiveSurface,
                      let pid = terminal.surface.foregroundProcessID().flatMap(Int32.init(exactly:)) else { continue }
                candidates.append((workspace, pid))
            }
        }
        return candidates
    }

    /// The first candidate whose foreground process is a plain `ssh`, with
    /// its detected route; detection runs off the main actor.
    @MainActor
    static func firstSSHSession(
        in candidates: [(workspace: Workspace, pid: Int32)]
    ) async -> (workspace: Workspace, session: DetectedSSHSession)? {
        let pids = candidates.map(\.pid)
        let found = await Task.detached(priority: .utility) { () -> (Int, DetectedSSHSession)? in
            for (index, pid) in pids.enumerated() {
                if let session = TerminalSSHSessionDetector.detect(foregroundPID: pid) {
                    return (index, session)
                }
            }
            return nil
        }.value
        guard let (index, session) = found else { return nil }
        return (candidates[index].workspace, session)
    }

    /// Adds ``sessionsDataKey`` and ``schemeDataKey`` to a custom-sidebar data context.
    @MainActor
    static func addSessions(
        to context: inout [String: SwiftValue],
        actions: [CmuxResolvedConfigAction]
    ) {
        guard CmuxDevBoxEdition.isActive else { return }
        // Sidebar content follows the terminal theme's light/dark scheme; the
        // panel picks its hard-coded accents (outline, badges) from it.
        context[schemeDataKey] = .string(
            GhosttyApp.shared.effectiveTerminalColorSchemePreference == .light ? "light" : "dark"
        )
        DevBoxCodexReset.add(to: &context)
        context[sessionsDataKey] = .array(sessions(from: actions).map { session in
            .object([
                "action": .string(session.actionID),
                "title": .string(session.title),
                "group": .string(session.group),
                "command": .string(session.command),
            ])
        })
    }
}
