import AppKit
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
    static let cornerRadius: CGFloat = 10

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
            .background(shape.fill(isEnabled ? Color(nsColor: cardColor) : .clear))
            .overlay(
                shape
                    .strokeBorder(
                        isEnabled ? Color(nsColor: DevBoxCardChrome.borderColor(forCard: cardColor)) : .clear,
                        lineWidth: isEnabled ? 1 : 0
                    )
                    .allowsHitTesting(false)
            )
            .padding(isEnabled ? DevBoxCardChrome.canvasInset : 0)
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
        Theme(name: "DevBox Charcoal", backgroundHex: "#252423", accentHex: "#e05d3a"),
        Theme(name: "DevBox Cinder", backgroundHex: "#271e1f", accentHex: "#ff6b4a"),
        Theme(name: "DevBox Cobalt", backgroundHex: "#10151c", accentHex: "#4fa8ff"),
        Theme(name: "DevBox Forest", backgroundHex: "#1e2326", accentHex: "#a7c080"),
    ]

    /// Light counterparts for daytime: tinted paper backgrounds (never pure
    /// white), softened ink foregrounds (about 10-12:1) and ANSI colors kept
    /// at 5:1 (normal) / 4:1 (bright) so syntax colors stay distinct and legible.
    static let lightThemes: [Theme] = [
        Theme(name: "DevBox Paper", backgroundHex: "#f3ede1", accentHex: "#c15627"),
        Theme(name: "DevBox Sepia", backgroundHex: "#f1e6cf", accentHex: "#b5562b"),
        Theme(name: "DevBox Sage", backgroundHex: "#ebeddf", accentHex: "#5f8a2e"),
        Theme(name: "DevBox Mist", backgroundHex: "#e9edf0", accentHex: "#2f6fd6"),
    ]

    private static func editableConfigURL() -> URL? {
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
            return String(dark.dropFirst("dark:".count))
        }
        return parts.count == 1 && !raw.contains(":") ? raw : nil
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
        // Same reload request `cmux themes set` sends; the app's observer
        // filters on the bundle id and runs the final-phase reload.
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

/// Theme swatches shown above the sidebar footer buttons: dark themes, a
/// wider gap, then light themes on one row; two rows when the sidebar is too
/// narrow for one.
struct DevBoxThemeSwitcherRow: View {
    @State private var activeThemeName: String?

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                swatchRow(DevBoxThemeSwitcher.themes).fixedSize()
                swatchRow(DevBoxThemeSwitcher.lightThemes).fixedSize()
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 4) {
                swatchRow(DevBoxThemeSwitcher.themes)
                swatchRow(DevBoxThemeSwitcher.lightThemes)
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 10)
        .onAppear { activeThemeName = DevBoxThemeSwitcher.currentThemeName() }
        // A theme picked elsewhere (Settings, `cmux themes set`) changes the
        // terminal background; re-read the selection then.
        .onReceive(NotificationCenter.default.publisher(for: .ghosttyDefaultBackgroundDidChange)) { _ in
            activeThemeName = DevBoxThemeSwitcher.currentThemeName()
        }
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

    /// The bundled panel script, used for ``sidebarName`` in the edition. It
    /// takes precedence over a same-named user file: older installs wrote a
    /// per-machine copy there, which would otherwise shadow app updates.
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
