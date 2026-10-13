import Foundation

/// The single switch for the self-use "cmux DevBox" edition: a build for
/// plain-SSH development against one remote box, with no Cloud Machines, no
/// cmux account, and no iPhone/iPad pairing.
///
/// The edition is identified by its bundle identifier (set by
/// `scripts/build-devbox.sh`), so tests, debug builds and the official app are
/// unaffected. Everything the edition turns off flows from the sets below:
///
/// - ``forcedPolicyKeys`` are reported as enforced by ``ManagedDevicePolicy``,
///   which already hides and stops Cloud, remote control, Iroh networking and
///   everywhere the app consults MDM policy.
/// - `CmuxFeatureFlags.devBoxEditionPinnedOffKeys` (app target) are pinned off
///   regardless of the remote flag service, for UI the policy does not cover
///   (account button, phone connect button, Pro upsell).
/// - ``isActive`` gates the few remaining entry points directly (sign-in,
///   Settings sections, phone notification forwarding).
///
/// `.disableRemoteConnections` is intentionally absent: it would block plain
/// SSH, which is the point of this edition.
public enum CmuxDevBoxEdition {
    /// Bundle identifier of the DevBox edition.
    public static let bundleIdentifier = "com.cmuxterm.app.staging.devbox"

    /// Whether the running process is the DevBox edition.
    public static let isActive: Bool = isEdition(bundleIdentifier: Bundle.main.bundleIdentifier)

    /// Whether `bundleIdentifier` names the DevBox edition.
    public static func isEdition(bundleIdentifier: String?) -> Bool {
        bundleIdentifier == Self.bundleIdentifier
    }

    /// Policy keys the edition enforces as if an MDM profile set them to `true`.
    public static let forcedPolicyKeys: Set<ManagedDevicePolicyKey> = [
        .disableCloud,
        .disableRemoteControl,
        .disableIrohNetworking,
        .disableAICredentialUpload,
    ]

    /// The edition's out-of-box settings, so every new install starts from the
    /// same setup. Registered defaults only: anything the user has set, or that
    /// `cmux.json` writes, still wins.
    public static var defaultSettings: [String: Any] { [
        "appearanceMode": "dark",
        "confirmQuit": "never",
        "warnBeforeClosingWorkspace": false,
        "terminal.copyOnSelect": true,
        "terminal.reflowHardWrapOnCopy": true,
        "terminal.showCopyConfirmation": true,
    ] }

    /// The edition's starting Ghostty config, written once when the edition has
    /// no `config.ghostty` of its own yet. The theme block is the one the
    /// Settings theme picker manages.
    public static let defaultGhosttyConfig = """
        # cmux themes start
        theme = light:Everforest Dark Hard,dark:Everforest Dark Hard
        # cmux themes end
        surface-tab-bar-font-size = 11
        background-blur = false
        background-opacity = 1
        window-padding-y = 2
        cursor-style-blink = false
        cursor-style = block

        """

    /// Applies ``defaultSettings`` and seeds ``defaultGhosttyConfig``. Call it
    /// before any setting or Ghostty config is read; it does nothing outside
    /// the edition.
    public static func applyDefaults(
        bundleIdentifier: String? = Bundle.main.bundleIdentifier,
        defaults: UserDefaults = .standard,
        appSupportDirectory: URL? = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
    ) {
        guard isEdition(bundleIdentifier: bundleIdentifier) else { return }
        // The registration domain is process-wide, so this is the only caller.
        defaults.register(defaults: defaultSettings)
        if let appSupportDirectory {
            seedGhosttyConfigIfMissing(appSupportDirectory: appSupportDirectory)
        }
    }

    /// Writes ``defaultGhosttyConfig`` to the edition's `config.ghostty` unless
    /// that file already exists.
    public static func seedGhosttyConfigIfMissing(
        appSupportDirectory: URL,
        fileManager: FileManager = .default
    ) {
        let directory = appSupportDirectory.appendingPathComponent(bundleIdentifier, isDirectory: true)
        let config = directory.appendingPathComponent("config.ghostty", isDirectory: false)
        guard !fileManager.fileExists(atPath: config.path) else { return }
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try? Data(defaultGhosttyConfig.utf8).write(to: config, options: .withoutOverwriting)
    }
}
