#!/usr/bin/env bash
# Publishes one cmux DevBox release to GitHub so installed copies update
# themselves through Sparkle.
#
#   ./scripts/release-devbox.sh <n> <notes.md> [--publish-existing]
#
# Builds an Apple silicon (arm64), stably signed app as <upstream>-devbox.<n>, EdDSA-signs
# the ZIP, writes appcast.xml, creates release tag v<upstream>-devbox.<n> on
# the pushed HEAD of devbox-064, uploads ZIP + appcast + SHA256SUMS, then
# reads the published appcast back and checks it.
#
# Needs (on the build Mac): the signing keychain and Sparkle private key under
# ~/.config/cmux-devbox (see docs/devbox-edition.md), gh logged in, and HEAD
# already pushed to the fork. Installed copies poll
# releases/latest/download/appcast.xml, so the newest release must carry it.
set -euo pipefail

REPO="JayYuuuuu/cmux-devbox"
BRANCH="devbox-064"
ED_KEY_FILE="$HOME/.config/cmux-devbox/sparkle-ed25519-private.key"
WORK_ROOT="${CMUX_DEVBOX_WORK_ROOT:-$HOME/cmux-devbox-build}"
MIN_SYSTEM_VERSION="14.0"

RELEASE_NUMBER="${1:?usage: release-devbox.sh <n> <notes.md>}"
NOTES_FILE="${2:?usage: release-devbox.sh <n> <notes.md>}"
PUBLISH_EXISTING="${3:-}"
if [[ -n "$PUBLISH_EXISTING" && "$PUBLISH_EXISTING" != --publish-existing ]]; then
  echo "error: unknown option $PUBLISH_EXISTING" >&2
  exit 2
fi
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
if [[ "$PUBLISH_EXISTING" != --publish-existing ]]; then
  rm -rf "$OUT_DIR"
  # arm64 only: every Mac running this edition is Apple silicon.
  CMUX_DEVBOX_ARCH=arm64 ./scripts/build-devbox.sh --release "$RELEASE_NUMBER" --out "$OUT_DIR"
fi

APP_PATH="${OUT_DIR}/cmux DevBox.app"
ZIP_PATH="${OUT_DIR}/cmux-DevBox.zip"
PLIST="$APP_PATH/Contents/Info.plist"
SHORT_VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PLIST")"
BUNDLE_VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$PLIST")"
TAG="v${SHORT_VERSION}"
if [[ "$PUBLISH_EXISTING" == --publish-existing ]]; then
  EDITION_VERSION="$(/usr/libexec/PlistBuddy -c "Print :CMUXEditionVersion" "$PLIST")"
  if [[ "$SHORT_VERSION" != *"-devbox.${RELEASE_NUMBER}" || "$EDITION_VERSION" != "${SHORT_VERSION} (${HEAD_SHA:0:9})" ]]; then
    echo "error: existing artifact version or source commit does not match this checkout" >&2
    exit 1
  fi
  codesign --verify --deep --strict "$APP_PATH"
  (cd "$OUT_DIR" && shasum -a 256 -c SHA256SUMS.txt)
fi

RELEASE_API=""
if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
  IS_DRAFT="$(gh release view "$TAG" --repo "$REPO" --json isDraft --jq .isDraft)"
  RELEASE_HEAD="$(gh release view "$TAG" --repo "$REPO" --json targetCommitish --jq .targetCommitish)"
  if [[ "$IS_DRAFT" != true || "$RELEASE_HEAD" != "$HEAD_SHA" ]]; then
    echo "error: release $TAG is already published or belongs to another commit" >&2
    exit 1
  fi
fi

ZIP_URL="https://github.com/${REPO}/releases/download/${TAG}/cmux-DevBox.zip"
NOTES_URL="https://github.com/${REPO}/releases/tag/${TAG}"

if [[ "$PUBLISH_EXISTING" != --publish-existing ]]; then
SPARKLE_BIN="$(find "${WORK_ROOT}/DerivedData/SourcePackages/artifacts" -type f -name sign_update -path '*/bin/*' | head -n 1)"
[[ -x "$SPARKLE_BIN" ]] || { echo "error: Sparkle sign_update not found" >&2; exit 1; }
# Prints: sparkle:edSignature="..." length="..."
ED_ATTRIBUTES="$("$SPARKLE_BIN" --ed-key-file "$ED_KEY_FILE" "$ZIP_PATH")"
[[ "$ED_ATTRIBUTES" == *'sparkle:edSignature="'* ]] || { echo "error: sign_update: $ED_ATTRIBUTES" >&2; exit 1; }

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

fi

# Keep a failed upload resumable and invisible to Sparkle. GitHub can accept
# an upload and then return a duplicate-name error on an HTTP retry; the
# server's uploaded state and SHA-256 digest decide success, not that error.
if ! gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
  gh release create "$TAG" --repo "$REPO" --target "$HEAD_SHA" \
    --title "cmux DevBox ${SHORT_VERSION}" --notes-file "$NOTES_FILE" --draft
fi
RELEASE_API="$(gh release view "$TAG" --repo "$REPO" --json apiUrl --jq .apiUrl)"

verify_release_asset() {
  local asset_name="$1" expected_sha="$2" remote_state
  remote_state="$(gh api "${RELEASE_API}/assets" --jq ".[] | select(.name == \"${asset_name}\") | \"\(.state) \(.digest)\"")" || return 1
  [[ "$remote_state" == "uploaded sha256:${expected_sha}" ]]
}

for asset_path in "$ZIP_PATH" "${OUT_DIR}/appcast.xml" "${OUT_DIR}/SHA256SUMS.txt"; do
  asset_name="$(basename "$asset_path")"
  asset_sha="$(shasum -a 256 "$asset_path" | cut -d' ' -f1)"
  if ! verify_release_asset "$asset_name" "$asset_sha"; then
    # A lost upload response is harmless only if readback proves the exact bytes.
    gh release upload "$TAG" "$asset_path" --repo "$REPO" || true
  fi
  if ! verify_release_asset "$asset_name" "$asset_sha"; then
    echo "error: draft $TAG retained; $asset_name is missing or its digest differs" >&2
    exit 1
  fi
done
gh release edit "$TAG" --repo "$REPO" --draft=false --latest

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
