#!/usr/bin/env bash
# Builds the self-use "cmux DevBox" edition: a Release app with its own name,
# bundle id, sockets and state, no Sparkle feed, ad-hoc signed, plus a ZIP.
#
# It never launches, quits or replaces any running cmux (official or DevBox).
# Install by copying the printed .app into /Applications while DevBox is quit.
#
# Identity: com.cmuxterm.app.staging.devbox. The staging prefix is deliberate:
# the app and the bundled CLI already give staging ids their own control socket
# (/tmp/cmux-staging-devbox.sock), last-socket markers, session files and
# Ghostty config dir, and UpdateController treats them as dev-like, so Sparkle
# never checks or installs official updates. It is not the stable id
# com.cmuxterm.app and never collides with it.
set -euo pipefail

APP_NAME="cmux DevBox"
BUNDLE_ID="com.cmuxterm.app.staging.devbox"
STAGING_SLUG="devbox"
UPSTREAM_BASE="v0.65.0 (dda24fbd2)"
WORK_ROOT="${CMUX_DEVBOX_WORK_ROOT:-$HOME/cmux-devbox-build}"
DERIVED_DATA="${WORK_ROOT}/DerivedData"
OUT_DIR="${WORK_ROOT}/out"

usage() {
  cat <<'EOF'
Usage: ./scripts/build-devbox.sh [--universal] [--derived-data <path>] [--out <dir>]

Builds "cmux DevBox.app" (Release, ad-hoc signed) and a ZIP.
Host CPU only by default; --universal builds arm64 + x86_64 for release assets.
Defaults: DerivedData and output under ~/cmux-devbox-build.
EOF
}

ARCH="${CMUX_DEVBOX_ARCH:-$(uname -m)}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --universal) ARCH="arm64 x86_64"; shift ;;
    --derived-data) DERIVED_DATA="${2:?--derived-data requires a value}"; shift 2 ;;
    --out) OUT_DIR="${2:?--out requires a value}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "error: unknown option $1" >&2; usage; exit 1 ;;
  esac
done

cd "$(dirname "${BASH_SOURCE[0]}")/.."
export PATH="${CARGO_HOME:-$HOME/.cargo}/bin:/opt/homebrew/bin:/usr/local/bin:${PATH}"

COMMIT="$(git rev-parse --short=9 HEAD)"
EDITION_VERSION="devbox-$(git rev-list --count dda24fbd2250dfacf41bf5e8e3d20d488acf6182..HEAD 2>/dev/null || echo 0)-${COMMIT}"

# `-packageAuthorizationProvider netrc`: SwiftPM otherwise asks the login
# keychain for download credentials, which blocks forever over SSH.
#
# Release is universal (arm64 + x86_64) by default, which compiles every
# Swift file twice; a local build only needs the host CPU (see --universal).
if [[ "$ARCH" == *" "* ]]; then
  ONLY_ACTIVE_ARCH=NO
  ARCH_LABEL="universal"
else
  ONLY_ACTIVE_ARCH=YES
  ARCH_LABEL="$ARCH"
fi

# The WireGuard bridge only serves the Cloud tunnel extension, which this
# edition never enables; a stub keeps the Release build free of a Go toolchain.
export CMUX_WIREGUARD_GO_REQUIRE=0

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
  ASSETCATALOG_COMPILER_APPICON_NAME=AppIcon-Nightly \
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

PLIST="$APP_PATH/Contents/Info.plist"
pb() { /usr/libexec/PlistBuddy -c "$1" "$PLIST"; }
pb_set() { # key type value
  pb "Set :$1 $3" 2>/dev/null || pb "Add :$1 $2 $3"
}

pb_set CFBundleName string "$APP_NAME"
pb_set CFBundleDisplayName string "$APP_NAME"
pb_set CFBundleIdentifier string "$BUNDLE_ID"
pb_set CMUXEditionName string "$APP_NAME"
pb_set CMUXEditionVersion string "$EDITION_VERSION"
pb_set CMUXUpstreamBase string "$UPSTREAM_BASE"

# Belt and braces on top of the dev-like bundle id: no feed, no key, no checks.
pb "Delete :SUFeedURL" 2>/dev/null || true
pb "Delete :SUPublicEDKey" 2>/dev/null || true
pb_set SUEnableAutomaticChecks bool false
pb_set SUAutomaticallyUpdate bool false

# No CMUXD_UNIX_PATH: the app no longer reads it, and a value baked from the
# build machine's $HOME would leak its user name into a published bundle.
pb "Add :LSEnvironment dict" 2>/dev/null || true
pb_set LSEnvironment:CMUX_BUNDLE_ID string "$BUNDLE_ID"
pb_set LSEnvironment:CMUX_SOCKET_PATH string "/tmp/cmux-staging-${STAGING_SLUG}.sock"

# Ad-hoc signature over the whole bundle. CODE_SIGNING_ALLOWED=NO leaves
# nested plug-ins and helpers unsigned, so sign them too (--deep). Fail loudly
# instead of shipping an unsigned app.
/usr/bin/codesign --force --deep --sign - --timestamp=none --generate-entitlement-der "$APP_PATH"
/usr/bin/codesign --verify --deep --strict "$APP_PATH"

ZIP_PATH="${OUT_DIR}/cmux-DevBox-${EDITION_VERSION}-${ARCH_LABEL}.zip"
rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

echo "App path: $APP_PATH"
echo "ZIP: $ZIP_PATH"
echo "Edition: $EDITION_VERSION (upstream $UPSTREAM_BASE), arch $(lipo -archs "$APP_PATH/Contents/MacOS/cmux")"
