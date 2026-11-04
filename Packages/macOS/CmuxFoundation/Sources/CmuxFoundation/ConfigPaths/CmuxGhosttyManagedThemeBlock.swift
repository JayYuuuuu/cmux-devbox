public import Foundation

/// The `# cmux themes start` … `# cmux themes end` block cmux owns inside the
/// editable Ghostty config.
///
/// Every writer of the managed theme (the `cmux themes set` CLI and the DevBox
/// sidebar theme switcher) goes through this type so the block format and the
/// replacement rule stay identical.
public struct CmuxGhosttyManagedThemeBlock {
    /// First line of the managed block.
    public static let startMarker = "# cmux themes start"
    /// Last line of the managed block.
    public static let endMarker = "# cmux themes end"

    private static let blockPattern = #"(?ms)\n?# cmux themes start\n.*?\n# cmux themes end\n?"#

    /// Creates the block editor.
    public init() {}

    /// Returns `contents` with every managed theme block removed.
    public func removing(from contents: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: Self.blockPattern) else {
            return contents
        }
        let fullRange = NSRange(contents.startIndex..<contents.endIndex, in: contents)
        return regex.stringByReplacingMatches(in: contents, options: [], range: fullRange, withTemplate: "")
    }

    /// Returns `contents` with its managed block replaced by one selecting
    /// `rawThemeValue`, appended after the remaining config.
    public func applying(rawThemeValue: String, to contents: String) -> String {
        let stripped = removing(from: contents).trimmingCharacters(in: .whitespacesAndNewlines)
        let block = """
        \(Self.startMarker)
        theme = \(rawThemeValue)
        \(Self.endMarker)
        """
        return stripped.isEmpty ? "\(block)\n" : "\(stripped)\n\n\(block)\n"
    }

    /// The `theme` value inside the managed block of `contents`, if any.
    public func rawThemeValue(in contents: String) -> String? {
        var insideBlock = false
        var value: String?
        for line in contents.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == Self.startMarker {
                insideBlock = true
            } else if trimmed == Self.endMarker {
                insideBlock = false
            } else if insideBlock,
                      let separator = trimmed.firstIndex(of: "="),
                      trimmed[..<separator].trimmingCharacters(in: .whitespaces) == "theme" {
                value = trimmed[trimmed.index(after: separator)...]
                    .trimmingCharacters(in: .whitespaces)
            }
        }
        return value
    }

    /// Writes a managed block selecting `rawThemeValue` into the config at
    /// `configURL`, creating the file and its directory when missing.
    public func write(rawThemeValue: String, to configURL: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: configURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
        let existing: String
        if fileManager.fileExists(atPath: configURL.path) {
            existing = try String(contentsOf: configURL, encoding: .utf8)
        } else {
            existing = ""
        }
        try applying(rawThemeValue: rawThemeValue, to: existing)
            .write(to: configURL, atomically: true, encoding: .utf8)
    }
}
