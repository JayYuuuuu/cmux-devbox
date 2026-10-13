import CmuxSettings
import Foundation
import Testing

/// The DevBox edition's out-of-box settings: registered as defaults (so user
/// choices still win), read back through the real catalog keys, and a starting
/// Ghostty config seeded only when the edition has none.
struct CmuxDevBoxEditionDefaultsTests {
    private func makeSuite() throws -> (UserDefaults, URL, () -> Void) {
        let suiteName = "CmuxDevBoxEditionDefaultsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let appSupport = FileManager.default.temporaryDirectory
            .appendingPathComponent("devbox-defaults-\(UUID().uuidString)", isDirectory: true)
        return (defaults, appSupport, {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: appSupport)
        })
    }

    private func seededConfig(in appSupport: URL) -> URL {
        appSupport
            .appendingPathComponent(CmuxDevBoxEdition.bundleIdentifier, isDirectory: true)
            .appendingPathComponent("config.ghostty", isDirectory: false)
    }

    @Test func catalogReadsTheEditionDefaults() throws {
        let (defaults, appSupport, cleanup) = try makeSuite()
        defer { cleanup() }

        CmuxDevBoxEdition.applyDefaults(
            bundleIdentifier: CmuxDevBoxEdition.bundleIdentifier,
            defaults: defaults,
            appSupportDirectory: appSupport
        )

        let app = AppCatalogSection()
        let terminal = TerminalCatalogSection()
        #expect(app.appearance.value(in: defaults) == .dark)
        #expect(app.confirmQuitMode.value(in: defaults) == .never)
        #expect(app.warnBeforeClosingWorkspace.value(in: defaults) == false)
        #expect(terminal.copyOnSelect.value(in: defaults) == true)
        #expect(terminal.reflowHardWrapOnCopy.value(in: defaults) == true)
        #expect(terminal.showCopyConfirmation.value(in: defaults) == true)
    }

    @Test func userChoicesWinOverEditionDefaults() throws {
        let (defaults, appSupport, cleanup) = try makeSuite()
        defer { cleanup() }
        defaults.set("light", forKey: "appearanceMode")

        CmuxDevBoxEdition.applyDefaults(
            bundleIdentifier: CmuxDevBoxEdition.bundleIdentifier,
            defaults: defaults,
            appSupportDirectory: appSupport
        )

        #expect(AppCatalogSection().appearance.value(in: defaults) == .light)
    }

    @Test func seedsGhosttyConfigOnlyWhenMissing() throws {
        let (defaults, appSupport, cleanup) = try makeSuite()
        defer { cleanup() }
        let config = seededConfig(in: appSupport)

        CmuxDevBoxEdition.applyDefaults(
            bundleIdentifier: CmuxDevBoxEdition.bundleIdentifier,
            defaults: defaults,
            appSupportDirectory: appSupport
        )
        #expect(try String(contentsOf: config, encoding: .utf8) == CmuxDevBoxEdition.defaultGhosttyConfig)

        try Data("theme = Nord\n".utf8).write(to: config)
        CmuxDevBoxEdition.applyDefaults(
            bundleIdentifier: CmuxDevBoxEdition.bundleIdentifier,
            defaults: defaults,
            appSupportDirectory: appSupport
        )
        #expect(try String(contentsOf: config, encoding: .utf8) == "theme = Nord\n")
    }

    @Test func otherBundlesAreUntouched() throws {
        let (defaults, appSupport, cleanup) = try makeSuite()
        defer { cleanup() }

        CmuxDevBoxEdition.applyDefaults(
            bundleIdentifier: "com.cmuxterm.app",
            defaults: defaults,
            appSupportDirectory: appSupport
        )

        #expect(defaults.object(forKey: "appearanceMode") == nil)
        #expect(!FileManager.default.fileExists(atPath: seededConfig(in: appSupport).path))
    }
}
