import CmuxSettings
import Foundation
import Testing

/// The DevBox edition's out-of-box settings decode through the real catalog
/// keys, and its starting Ghostty config is seeded only when missing.
/// `applyDefaults` itself registers into the process-wide registration domain,
/// so it is not called here.
struct CmuxDevBoxEditionDefaultsTests {
    @Test func catalogReadsTheEditionDefaults() throws {
        let suiteName = "CmuxDevBoxEditionDefaultsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        for (key, value) in CmuxDevBoxEdition.defaultSettings {
            defaults.set(value, forKey: key)
        }

        let app = AppCatalogSection()
        let terminal = TerminalCatalogSection()
        #expect(app.appearance.value(in: defaults) == .dark)
        #expect(app.confirmQuitMode.value(in: defaults) == .never)
        #expect(terminal.copyOnSelect.value(in: defaults) == true)
    }

    @Test func seedsGhosttyConfigOnlyWhenMissing() throws {
        let appSupport = FileManager.default.temporaryDirectory
            .appendingPathComponent("devbox-defaults-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: appSupport) }
        let config = appSupport
            .appendingPathComponent(CmuxDevBoxEdition.bundleIdentifier, isDirectory: true)
            .appendingPathComponent("config.ghostty", isDirectory: false)

        CmuxDevBoxEdition.seedGhosttyConfigIfMissing(appSupportDirectory: appSupport)
        #expect(try String(contentsOf: config, encoding: .utf8) == CmuxDevBoxEdition.defaultGhosttyConfig)

        try Data("theme = Nord\n".utf8).write(to: config)
        CmuxDevBoxEdition.seedGhosttyConfigIfMissing(appSupportDirectory: appSupport)
        #expect(try String(contentsOf: config, encoding: .utf8) == "theme = Nord\n")
    }

    @Test func otherBundlesAreUntouched() throws {
        let appSupport = FileManager.default.temporaryDirectory
            .appendingPathComponent("devbox-defaults-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: appSupport) }
        let suiteName = "CmuxDevBoxEditionDefaultsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        CmuxDevBoxEdition.applyDefaults(
            bundleIdentifier: "com.cmuxterm.app",
            defaults: defaults,
            appSupportDirectory: appSupport
        )

        #expect(defaults.object(forKey: "appearanceMode") == nil)
        #expect(!FileManager.default.fileExists(atPath: appSupport.path))
    }

    @Test func adoptsMinimalModeOnceAndKeepsLaterChoices() throws {
        let suiteName = "CmuxDevBoxEditionDefaultsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        // An install that already stored standard mode moves to minimal once.
        defaults.set("standard", forKey: CmuxDevBoxEdition.presentationModeKey)

        CmuxDevBoxEdition.adoptMinimalModeOnce(in: defaults)
        #expect(defaults.string(forKey: CmuxDevBoxEdition.presentationModeKey) == "minimal")

        // Switching back later in Settings survives every following launch.
        defaults.set("standard", forKey: CmuxDevBoxEdition.presentationModeKey)
        CmuxDevBoxEdition.adoptMinimalModeOnce(in: defaults)
        #expect(defaults.string(forKey: CmuxDevBoxEdition.presentationModeKey) == "standard")
    }

    @Test func minimalModeIsTheRegisteredDefault() {
        #expect(CmuxDevBoxEdition.defaultSettings[CmuxDevBoxEdition.presentationModeKey] as? String == "minimal")
        #expect(CmuxDevBoxEdition.defaultSettings[CmuxDevBoxEdition.sidebarProviderKey] as? String == "cmux.sidebar.custom.devbox")
    }
}
