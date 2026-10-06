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
///   device discovery everywhere the app consults MDM policy.
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
        .disableDeviceDiscovery,
        .disableIncomingDeviceAccess,
        .disableAICredentialUpload,
    ]
}
