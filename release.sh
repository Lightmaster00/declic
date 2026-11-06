#!/bin/bash
# Publishes a new Déclic version on GitHub. Installed copies then offer it automatically
# ("Check for Updates…" menu item, or the daily check).
#
#   ./release.sh 1.0.1 "Release notes"
#
# One-time setup:
#   - .github-repo contains "owner/repo" (e.g. Lightmaster00/declic), a public repository;
#   - the GitHub CLI is installed and signed in: brew install gh && gh auth login.
#
# Always publish from the same Mac: updates are only accepted when they are signed with the
# same certificate as the installed app.
#
# Optional: with an Apple "Developer ID" certificate and notarization, macOS no longer shows
# the "unidentified developer" warning on first launch:
#   SIGN_ID="Developer ID Application: Your Name (TEAMID)" NOTARY_PROFILE=declic ./release.sh 1.0.1
#   (create the profile once with: xcrun notarytool store-credentials declic)
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${1:?Usage: ./release.sh <version> [notes]}"
NOTES="${2:-Déclic $VERSION}"
REPO="${GITHUB_REPO:-$(cat .github-repo 2>/dev/null | tr -d '[:space:]' || true)}"
[[ -n "$REPO" ]] || { echo "❌ Create .github-repo containing \"owner/repo\"."; exit 1; }
command -v gh >/dev/null || { echo "❌ Install the GitHub CLI: brew install gh && gh auth login"; exit 1; }

# 1. Version number in Info.plist.
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" Resources/Info.plist
BUILD_NUMBER=$(( $(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" Resources/Info.plist) + 1 ))
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" Resources/Info.plist

# 2. Build, sign and package (zip for in-app updates, DMG for downloads).
RELEASE=1 GITHUB_REPO="$REPO" ./build.sh dmg
ZIP="build/Declic.zip"
DMG="build/Declic.dmg"

# 3. Notarization (when a profile is provided).
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    echo "📮 Notarizing…"
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
    xcrun stapler staple "build/Déclic.app"
fi
rm -f "$ZIP"
ditto -c -k --keepParent "build/Déclic.app" "$ZIP"

# 4. Commit the version bump, then publish.
if git rev-parse --git-dir >/dev/null 2>&1; then
    git add Resources/Info.plist
    git commit -q -m "Release $VERSION" || true
    git push -q || true
fi
gh release create "v$VERSION" "$DMG" "$ZIP" --repo "$REPO" --title "Déclic $VERSION" --notes "$NOTES"
echo "✅ Déclic $VERSION published: https://github.com/$REPO/releases/tag/v$VERSION"
