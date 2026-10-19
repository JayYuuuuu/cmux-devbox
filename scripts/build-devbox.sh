#!/usr/bin/env bash
# Builds the self-use "cmux DevBox" edition: a Release app with its own name,
# bundle id, sockets, state and Sparkle feed, plus a ZIP.
#
# It never launches, quits or replaces any running cmux (official or DevBox).
# Install by copying the printed .app into /Applications while DevBox is quit.
#
# Identity: com.cmuxterm.app.staging.devbox. The staging prefix is deliberate:
# the app and the bundled CLI already give staging ids their own control socket
# (/tmp/cmux-staging-devbox.sock), last-socket markers, session files and
# Ghostty config dir. UpdateController exempts this one id from the staging
# "no updates" rule: it reads the edition's own feed (DevBoxEditionUpdates),
# verified with the edition's EdDSA key, so official updates can never apply.
# It is not the stable id com.cmuxterm.app and never collides with it.
#
# Signing: with the edition's signing keychain present (see
# docs/devbox-edition.md) every Mach-O is signed with the stable
# "cmux DevBox Code Signing" identity, so updates keep TCC grants and pass
# Sparkle's code signature check; otherwise ad-hoc (local builds only).
set -euo pipefail

APP_NAME="cmux DevBox"
BUNDLE_ID="com.cmuxterm.app.staging.devbox"
STAGING_SLUG="devbox"
UPSTREAM_TAG="v0.64.25"
SPARKLE_FEED_URL="https://github.com/JayYuuuuu/cmux-devbox/releases/latest/download/appcast.xml"
SPARKLE_PUBLIC_ED_KEY="GGisbyyaEckq0hn9j95M8VRWzfVpddZFZTssLqfz4qU="
SIGN_IDENTITY_NAME="cmux DevBox Code Signing"
SIGN_KEYCHAIN="$HOME/Library/Keychains/cmux-devbox-signing.keychain-db"
SIGN_KEYCHAIN_PASSWORD_FILE="$HOME/.config/cmux-devbox/signing-keychain-password"
RELEASE_NUMBER=""
WORK_ROOT="${CMUX_DEVBOX_WORK_ROOT:-$HOME/cmux-devbox-build}"
DERIVED_DATA="${WORK_ROOT}/DerivedData"
OUT_DIR="${WORK_ROOT}/out"

usage() {
  cat <<'EOF'
Usage: ./scripts/build-devbox.sh [--universal] [--release <n>] [--derived-data <path>] [--out <dir>]

Builds "cmux DevBox.app" (Release configuration) and a ZIP.
Host CPU only by default (releases are arm64); --universal builds arm64 + x86_64.
--release <n> stamps version <upstream>-devbox.<n> (build <upstream build>.<n>)
and requires the stable signing identity; without it the build is a local
"-devbox.dev" build that never looks newer than a published release.
Defaults: DerivedData and output under ~/cmux-devbox-build.
EOF
}

ARCH="${CMUX_DEVBOX_ARCH:-$(uname -m)}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --universal) ARCH="arm64 x86_64"; shift ;;
    --release) RELEASE_NUMBER="${2:?--release requires a number}"; shift 2 ;;
    --derived-data) DERIVED_DATA="${2:?--derived-data requires a value}"; shift 2 ;;
    --out) OUT_DIR="${2:?--out requires a value}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "error: unknown option $1" >&2; usage; exit 1 ;;
  esac
done

cd "$(dirname "${BASH_SOURCE[0]}")/.."
export PATH="${CARGO_HOME:-$HOME/.cargo}/bin:/opt/homebrew/bin:/usr/local/bin:${PATH}"
# A build Mac may keep the Command Line Tools selected for other projects;
# this build needs the full Xcode, so use it when one is installed.
if [[ -z "${DEVELOPER_DIR:-}" && "$(xcode-select -p 2>/dev/null)" == /Library/Developer/CommandLineTools* \
      && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

if [[ -n "$RELEASE_NUMBER" && ! "$RELEASE_NUMBER" =~ ^[1-9][0-9]*$ ]]; then
  echo "error: --release takes a positive integer" >&2
  exit 1
fi
COMMIT="$(git rev-parse --short=9 HEAD)"
UPSTREAM_COMMIT="$(git rev-parse --short=9 "${UPSTREAM_TAG}^{commit}")"
UPSTREAM_BASE="${UPSTREAM_TAG} (${UPSTREAM_COMMIT})"

SIGN_ARGS=(--sign -)
if [[ -f "$SIGN_KEYCHAIN" && -f "$SIGN_KEYCHAIN_PASSWORD_FILE" ]]; then
  security unlock-keychain -p "$(cat "$SIGN_KEYCHAIN_PASSWORD_FILE")" "$SIGN_KEYCHAIN"
  SIGN_ARGS=(--keychain "$SIGN_KEYCHAIN" --sign "$SIGN_IDENTITY_NAME")
elif [[ -n "$RELEASE_NUMBER" ]]; then
  echo "error: --release needs the signing keychain $SIGN_KEYCHAIN" >&2
  exit 1
fi

# `-packageAuthorizationProvider netrc`: SwiftPM otherwise asks the login
# keychain for download credentials, which blocks forever over SSH.
#
# --universal (arm64 + x86_64) compiles every Swift file twice; releases and
# local builds only need arm64.
if [[ "$ARCH" == *" "* ]]; then
  ONLY_ACTIVE_ARCH=NO
  ARCH_LABEL="universal"
else
  ONLY_ACTIVE_ARCH=YES
  ARCH_LABEL="$ARCH"
fi

# Published bundles must not carry the build machine's paths (they name its
# user account). Compilers embed source paths for #file, assertions, panics
# and debug info; map the home directory to /build everywhere, keep object
# file paths out of the linked binaries, and strip debug symbols below.
PATH_MAP_FROM="$HOME"
PATH_MAP_TO="/build"
export RUSTFLAGS="${RUSTFLAGS:+$RUSTFLAGS }--remap-path-prefix=${PATH_MAP_FROM}=${PATH_MAP_TO}"

# The WireGuard bridge only serves the Cloud tunnel extension, which this
# edition never enables; a stub keeps the Release build free of a Go toolchain.
export CMUX_WIREGUARD_GO_REQUIRE=0

# GhosttyKit is a local binary target keyed to the ghostty submodule; a fresh
# build Mac (or a new upstream base) has no xcframework yet.
./scripts/ensure-ghosttykit.sh

xcodebuild \
  -project cmux.xcodeproj \
  -scheme cmux \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  -packageAuthorizationProvider netrc \
  ARCHS="$ARCH" \
  ONLY_ACTIVE_ARCH="$ONLY_ACTIVE_ARCH" \
  PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
  CMUX_SIDEBAR_EXTENSION_POINT_ID="${BUNDLE_ID}.cmux.sidebar" \
  CMUX_AUTH_CALLBACK_SCHEME="cmux-devbox" \
  CODE_SIGNING_ALLOWED=NO \
  OTHER_SWIFT_FLAGS="\$(inherited) -file-prefix-map ${PATH_MAP_FROM}=${PATH_MAP_TO}" \
  OTHER_CFLAGS="\$(inherited) -ffile-prefix-map=${PATH_MAP_FROM}=${PATH_MAP_TO}" \
  OTHER_LDFLAGS="\$(inherited) -Wl,-oso_prefix,${PATH_MAP_FROM}/" \
  build

BUILT_APP="${DERIVED_DATA}/Build/Products/Release/cmux.app"
if [[ ! -d "$BUILT_APP" ]]; then
  echo "error: cmux.app not found at $BUILT_APP" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"
APP_PATH="${OUT_DIR}/${APP_NAME}.app"
rm -rf "$APP_PATH"
ditto "$BUILT_APP" "$APP_PATH"

# Incremental builds keep icons from earlier icon settings; ship only AppIcon.
rm -f "$APP_PATH"/Contents/Resources/AppIcon-{Nightly,Debug,RC}.icns

PLIST="$APP_PATH/Contents/Info.plist"
pb() { /usr/libexec/PlistBuddy -c "$1" "$PLIST"; }
pb_set() { # key type value
  pb "Set :$1 $3" 2>/dev/null || pb "Add :$1 $2 $3"
}

pb_set CFBundleName string "$APP_NAME"
pb_set CFBundleDisplayName string "$APP_NAME"
pb_set CFBundleIdentifier string "$BUNDLE_ID"
# Versions: <upstream>-devbox.<n> / <upstream build>.<n>. Sparkle compares
# CFBundleVersion, independent of the displayed upstream version. Keep the
# rollback floor above every previously published edition build.
UPSTREAM_SHORT_VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PLIST")"
UPSTREAM_BUILD="$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$PLIST")"
# v0.65.2 shipped as build 111.2. This v0.64 recovery release must sort
# above it so existing installations can recover through Sparkle.
DEVBOX_MIN_UPSTREAM_BUILD=112
if (( UPSTREAM_BUILD < DEVBOX_MIN_UPSTREAM_BUILD )); then
  UPSTREAM_BUILD=$DEVBOX_MIN_UPSTREAM_BUILD
fi
if [[ -n "$RELEASE_NUMBER" ]]; then
  SHORT_VERSION="${UPSTREAM_SHORT_VERSION}-devbox.${RELEASE_NUMBER}"
  BUNDLE_VERSION="${UPSTREAM_BUILD}.${RELEASE_NUMBER}"
else
  SHORT_VERSION="${UPSTREAM_SHORT_VERSION}-devbox.dev"
  BUNDLE_VERSION="${UPSTREAM_BUILD}"
fi
EDITION_VERSION="${SHORT_VERSION} (${COMMIT})"
pb_set CFBundleShortVersionString string "$SHORT_VERSION"
pb_set CFBundleVersion string "$BUNDLE_VERSION"
pb_set CMUXEditionName string "$APP_NAME"
pb_set CMUXEditionVersion string "$EDITION_VERSION"
pb_set CMUXUpstreamBase string "$UPSTREAM_BASE"

# The edition's own update feed and key; Sparkle rejects anything not signed
# with the matching private key, including official cmux updates.
pb_set SUFeedURL string "$SPARKLE_FEED_URL"
pb_set SUPublicEDKey string "$SPARKLE_PUBLIC_ED_KEY"
pb_set SUEnableAutomaticChecks bool true
pb_set SUAutomaticallyUpdate bool false

# No CMUXD_UNIX_PATH: the app no longer reads it, and a value baked from the
# build machine's $HOME would leak its user name into a published bundle.
pb "Add :LSEnvironment dict" 2>/dev/null || true
pb_set LSEnvironment:CMUX_BUNDLE_ID string "$BUNDLE_ID"
pb_set LSEnvironment:CMUX_SOCKET_PATH string "/tmp/cmux-staging-${STAGING_SLUG}.sock"

# Every Mach-O in the bundle (executables and dylibs). Bundle main
# executables (*/Contents/MacOS/*) are re-signed with their bundle by the
# --deep signature below; signing one directly would require its whole bundle
# to be signed already. Every other Mach-O is signed on its own here.
MACHO_FILES=()
LOOSE_MACHO_FILES=()
while IFS= read -r -d '' file; do
  if lipo -archs "$file" >/dev/null 2>&1; then
    MACHO_FILES+=("$file")
    case "$file" in
      */Contents/MacOS/*) ;;
      *) LOOSE_MACHO_FILES+=("$file") ;;
    esac
  fi
done < <(find "$APP_PATH" -type f \( -perm -111 -o -name '*.dylib' -o -name '*.so' \) -print0 | sort -rz)

# Debug symbols only (the binaries keep working); they hold object paths.
# Stripping invalidates each file's own signature, and executables under
# Contents/Resources/bin are not re-signed by `codesign --deep` (macOS kills
# them with "Code Signature Invalid"), so each one is re-signed right away.
for file in "${MACHO_FILES[@]}"; do
  xcrun strip -S "$file" 2>/dev/null || true
done
for file in "${LOOSE_MACHO_FILES[@]}"; do
  /usr/bin/codesign --force "${SIGN_ARGS[@]}" --timestamp=none \
    --preserve-metadata=identifier,entitlements,flags,runtime "$file"
done

if leaks="$(grep -rlaF "${PATH_MAP_FROM}/" "$APP_PATH")"; then
  echo "error: build machine paths (${PATH_MAP_FROM}/) remain in:" >&2
  echo "$leaks" >&2
  exit 1
fi

# Nested bundles, deepest first. `codesign --deep` skips some locations
# (Contents/Library/SystemExtensions), so sign each one explicitly.
NESTED_BUNDLES=()
while IFS= read -r -d '' bundle; do
  NESTED_BUNDLES+=("$bundle")
done < <(find "$APP_PATH" -mindepth 1 -type d \( -name '*.app' -o -name '*.appex' \
  -o -name '*.plugin' -o -name '*.systemextension' -o -name '*.xpc' -o -name '*.framework' \) \
  -print0 | sort -rz)
for bundle in "${NESTED_BUNDLES[@]}"; do
  /usr/bin/codesign --force "${SIGN_ARGS[@]}" --timestamp=none \
    --preserve-metadata=identifier,entitlements,flags,runtime "$bundle"
done

# Signature over the whole bundle. CODE_SIGNING_ALLOWED=NO leaves nested
# plug-ins and helpers unsigned, so sign them too (--deep). Fail loudly
# instead of shipping an unsigned app.
/usr/bin/codesign --force --deep "${SIGN_ARGS[@]}" --timestamp=none --generate-entitlement-der "$APP_PATH"
/usr/bin/codesign --verify --deep --strict "$APP_PATH"
# --deep verification does not cover loose executables in Resources/bin.
for file in "${MACHO_FILES[@]}"; do
  /usr/bin/codesign --verify --strict "$file"
done

# Release ZIPs keep one stable name so releases/latest/download links never break.
if [[ -n "$RELEASE_NUMBER" ]]; then
  ZIP_PATH="${OUT_DIR}/cmux-DevBox.zip"
else
  ZIP_PATH="${OUT_DIR}/cmux-DevBox-dev-${ARCH_LABEL}.zip"
fi
rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

echo "App path: $APP_PATH"
echo "ZIP: $ZIP_PATH"
echo "Edition: $EDITION_VERSION (upstream $UPSTREAM_BASE), arch $(lipo -archs "$APP_PATH/Contents/MacOS/cmux")"
echo "Version: $SHORT_VERSION build $BUNDLE_VERSION"
echo "Signed: $(/usr/bin/codesign -d -r- "$APP_PATH" 2>&1 | sed -n 's/^designated => //p')"
