#!/usr/bin/env bash
# Publishes one cmux DevBox release to GitHub so installed copies update
# themselves through Sparkle.
#
#   ./scripts/release-devbox.sh <n> <notes.md>
#
# Builds an Apple silicon (arm64), stably signed app as <upstream>-devbox.<n>, EdDSA-signs
# the ZIP, writes appcast.xml, creates release tag v<upstream>-devbox.<n> on
# the pushed HEAD of devbox-custom, uploads ZIP + appcast + SHA256SUMS, then
# reads the published appcast back and checks it.
#
# Needs (on the build Mac): the signing keychain and Sparkle private key under
# ~/.config/cmux-devbox (see docs/devbox-edition.md), gh logged in, and HEAD
# already pushed to the fork. Installed copies poll
# releases/latest/download/appcast.xml, so the newest release must carry it.
set -euo pipefail

REPO="JayYuuuuu/cmux-devbox"
BRANCH="devbox-custom"
ED_KEY_FILE="$HOME/.config/cmux-devbox/sparkle-ed25519-private.key"
WORK_ROOT="${CMUX_DEVBOX_WORK_ROOT:-$HOME/cmux-devbox-build}"
MIN_SYSTEM_VERSION="14.0"

RELEASE_NUMBER="${1:?usage: release-devbox.sh <n> <notes.md>}"
NOTES_FILE="${2:?usage: release-devbox.sh <n> <notes.md>}"
[[ -f "$NOTES_FILE" ]] || { echo "error: notes file $NOTES_FILE not found" >&2; exit 1; }
[[ -f "$ED_KEY_FILE" ]] || { echo "error: Sparkle key $ED_KEY_FILE not found" >&2; exit 1; }

cd "$(dirname "${BASH_SOURCE[0]}")/.."
export PATH="${CARGO_HOME:-$HOME/.cargo}/bin:/opt/homebrew/bin:/usr/local/bin:${PATH}"

# Release only what anyone can rebuild: a clean tree whose HEAD is on GitHub.
if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
  echo "error: working tree has uncommitted changes" >&2
  exit 1
fi
HEAD_SHA="$(git rev-parse HEAD)"
REMOTE_SHA="$(git ls-remote "https://github.com/${REPO}.git" "refs/heads/${BRANCH}" | cut -f1)"
if [[ "$HEAD_SHA" != "$REMOTE_SHA" ]]; then
  echo "error: HEAD $HEAD_SHA is not the pushed ${BRANCH} ($REMOTE_SHA)" >&2
  exit 1
fi

OUT_DIR="${WORK_ROOT}/release-${RELEASE_NUMBER}"
rm -rf "$OUT_DIR"
# arm64 only: every Mac running this edition is Apple silicon, and a
# universal build compiles every Swift file twice.
CMUX_DEVBOX_ARCH=arm64 ./scripts/build-devbox.sh --release "$RELEASE_NUMBER" --out "$OUT_DIR"

APP_PATH="${OUT_DIR}/cmux DevBox.app"
ZIP_PATH="${OUT_DIR}/cmux-DevBox.zip"
PLIST="$APP_PATH/Contents/Info.plist"
SHORT_VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PLIST")"
BUNDLE_VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$PLIST")"
TAG="v${SHORT_VERSION}"

if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
  echo "error: release $TAG already exists" >&2
  exit 1
fi

SPARKLE_BIN="$(find "${WORK_ROOT}/DerivedData/SourcePackages/artifacts" -type f -name sign_update -path '*/bin/*' | head -n 1)"
[[ -x "$SPARKLE_BIN" ]] || { echo "error: Sparkle sign_update not found" >&2; exit 1; }
# Prints: sparkle:edSignature="..." length="..."
ED_ATTRIBUTES="$("$SPARKLE_BIN" --ed-key-file "$ED_KEY_FILE" "$ZIP_PATH")"
[[ "$ED_ATTRIBUTES" == *'sparkle:edSignature="'* ]] || { echo "error: sign_update: $ED_ATTRIBUTES" >&2; exit 1; }

ZIP_URL="https://github.com/${REPO}/releases/download/${TAG}/cmux-DevBox.zip"
NOTES_URL="https://github.com/${REPO}/releases/tag/${TAG}"
PUB_DATE="$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')"
cat > "${OUT_DIR}/appcast.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>cmux DevBox</title>
    <link>https://github.com/${REPO}</link>
    <item>
      <title>${SHORT_VERSION}</title>
      <pubDate>${PUB_DATE}</pubDate>
      <sparkle:version>${BUNDLE_VERSION}</sparkle:version>
      <sparkle:shortVersionString>${SHORT_VERSION}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>${MIN_SYSTEM_VERSION}</sparkle:minimumSystemVersion>
      <sparkle:hardwareRequirements>arm64</sparkle:hardwareRequirements>
      <sparkle:releaseNotesLink>${NOTES_URL}</sparkle:releaseNotesLink>
      <enclosure url="${ZIP_URL}" type="application/octet-stream" ${ED_ATTRIBUTES} />
    </item>
  </channel>
</rss>
EOF

(cd "$OUT_DIR" && shasum -a 256 cmux-DevBox.zip appcast.xml > SHA256SUMS.txt)

gh release create "$TAG" --repo "$REPO" --target "$HEAD_SHA" \
  --title "cmux DevBox ${SHORT_VERSION}" --notes-file "$NOTES_FILE" \
  "$ZIP_PATH" "${OUT_DIR}/appcast.xml" "${OUT_DIR}/SHA256SUMS.txt"

# Read back what installed copies will see.
LIVE_APPCAST="$(curl -fsSL "https://github.com/${REPO}/releases/latest/download/appcast.xml")"
if [[ "$LIVE_APPCAST" != *"<sparkle:version>${BUNDLE_VERSION}</sparkle:version>"* ]]; then
  echo "error: live appcast does not list build ${BUNDLE_VERSION}" >&2
  exit 1
fi
LIVE_ZIP_SHA="$(curl -fsSL "$ZIP_URL" | shasum -a 256 | cut -d' ' -f1)"
LOCAL_ZIP_SHA="$(shasum -a 256 "$ZIP_PATH" | cut -d' ' -f1)"
if [[ "$LIVE_ZIP_SHA" != "$LOCAL_ZIP_SHA" ]]; then
  echo "error: downloaded ZIP checksum differs from the built one" >&2
  exit 1
fi

echo "Published ${TAG} (build ${BUNDLE_VERSION})"
echo "Download: https://github.com/${REPO}/releases/latest/download/cmux-DevBox.zip"
