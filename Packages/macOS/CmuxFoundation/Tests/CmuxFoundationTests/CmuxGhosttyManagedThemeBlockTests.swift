import Foundation
import Testing
@testable import CmuxFoundation

/// Covers ``CmuxGhosttyManagedThemeBlock``, the single writer of the managed
/// theme block shared by `cmux themes set` and the DevBox sidebar switcher.
@Suite("Ghostty managed theme block")
struct CmuxGhosttyManagedThemeBlockTests {
    private let block = CmuxGhosttyManagedThemeBlock()

    @Test("Replacing the theme keeps the user's other settings and leaves one block")
    func replacesExistingBlock() {
        let original = """
        # cmux themes start
        theme = light:Everforest Dark Hard,dark:Everforest Dark Hard
        # cmux themes end
        font-family = ""
        window-padding-x = 12

        """
        let updated = block.applying(rawThemeValue: "DevBox Charcoal", to: original)

        #expect(updated == """
        font-family = ""
        window-padding-x = 12

        # cmux themes start
        theme = DevBox Charcoal
        # cmux themes end

        """)
        #expect(updated.components(separatedBy: CmuxGhosttyManagedThemeBlock.startMarker).count == 2)
        #expect(block.rawThemeValue(in: updated) == "DevBox Charcoal")
    }

    @Test("An empty config gets just the block")
    func writesBlockIntoEmptyConfig() {
        let updated = block.applying(rawThemeValue: "DevBox Cinder", to: "")
        #expect(updated == "# cmux themes start\ntheme = DevBox Cinder\n# cmux themes end\n")
    }

    @Test("A theme line outside the managed block is not reported as the managed theme")
    func ignoresUnmanagedThemeLine() {
        #expect(block.rawThemeValue(in: "theme = Dracula\nfont-size = 13\n") == nil)
        #expect(block.rawThemeValue(in: """
        theme = Dracula
        # cmux themes start
        theme = light:A,dark:B
        # cmux themes end
        """) == "light:A,dark:B")
    }

    @Test("Writing creates the config and round-trips the theme")
    func writesFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("managed-theme-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("config.ghostty")

        try block.write(rawThemeValue: "DevBox Cobalt", to: url)
        try block.write(rawThemeValue: "DevBox Charcoal", to: url)

        let contents = try String(contentsOf: url, encoding: .utf8)
        #expect(block.rawThemeValue(in: contents) == "DevBox Charcoal")
        #expect(!contents.contains("DevBox Cobalt"))
    }
}
