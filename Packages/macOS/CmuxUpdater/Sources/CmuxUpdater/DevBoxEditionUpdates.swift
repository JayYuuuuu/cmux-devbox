public import Foundation

/// Update channel of the self-use "cmux DevBox" edition.
///
/// The edition runs under a staging-prefixed bundle id for socket and state
/// isolation, but unlike real staging builds it ships its own Sparkle feed
/// (GitHub releases of the edition's fork, signed with the edition's EdDSA
/// key). Mirrors `CmuxDevBoxEdition.bundleIdentifier` in CmuxSettings; kept
/// here to avoid a `CmuxUpdater → CmuxSettings` dependency, like
/// ``UpdateController/isDevLikeBundleIdentifier(_:)``.
public enum DevBoxEditionUpdates {
    /// Bundle identifier of the DevBox edition.
    public static let bundleIdentifier = "com.cmuxterm.app.staging.devbox"

    /// The edition's appcast, published as an asset of its latest release.
    public static let feedURL = "https://github.com/JayYuuuuu/cmux-devbox/releases/latest/download/appcast.xml"

    /// Release page base for the edition's tags.
    public static let releasesURL = "https://github.com/JayYuuuuu/cmux-devbox/releases"

    /// Whether `bundleIdentifier` names the DevBox edition.
    public static func isEdition(_ bundleIdentifier: String?) -> Bool {
        bundleIdentifier == Self.bundleIdentifier
    }

    /// Whether the running process is the DevBox edition.
    public static let isRunning = isEdition(Bundle.main.bundleIdentifier)

    /// Marker that ``repairAutomaticChecks(in:)`` already ran.
    public static let automaticChecksRepairKey = "cmux.devbox.automaticChecksRepair.v1"

    /// Turns automatic update checks back on once.
    ///
    /// Edition builds up to 0.65.0-devbox.3 were classified as staging, and the staging gate
    /// persisted `SUEnableAutomaticChecks = false`. Without this repair those installs would
    /// never probe the edition's feed after updating. Runs once, so a user who later turns
    /// automatic checks off in Settings keeps that choice.
    public static func repairAutomaticChecks(in defaults: UserDefaults) {
        guard !defaults.bool(forKey: automaticChecksRepairKey) else { return }
        defaults.set(true, forKey: UpdateSettings.automaticChecksKey)
        defaults.set(true, forKey: automaticChecksRepairKey)
    }
}
