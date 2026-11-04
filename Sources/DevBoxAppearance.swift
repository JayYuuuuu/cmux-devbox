import AppKit
import CmuxFoundation
import CmuxSettings
import SwiftUI

// DevBox edition appearance: the terminal area drawn as an inset rounded card
// on a slightly darker canvas, and one-click color theme buttons at the bottom
// of the sidebar. Both are inert outside the edition.

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
        Theme(name: "Everforest Dark Hard", backgroundHex: "#272e33", accentHex: "#a7c080"),
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

/// Row of theme swatches shown above the sidebar footer buttons.
struct DevBoxThemeSwitcherRow: View {
    @State private var activeThemeName: String?

    var body: some View {
        HStack(spacing: 8) {
            ForEach(DevBoxThemeSwitcher.themes) { theme in
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
            Spacer(minLength: 0)
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
}

private struct DevBoxThemeSwatch: View {
    let theme: DevBoxThemeSwitcher.Theme
    let isActive: Bool
    @State private var isHovered = false

    var body: some View {
        let background = Color(nsColor: NSColor(hex: theme.backgroundHex) ?? .black)
        let accent = Color(nsColor: NSColor(hex: theme.accentHex) ?? .orange)
        ZStack {
            Circle().fill(background)
            Circle()
                .strokeBorder(Color.white.opacity(isHovered ? 0.45 : 0.22), lineWidth: 1)
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
