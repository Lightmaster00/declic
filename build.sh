#!/bin/bash
# Builds Declic.
#
#   ./build.sh           build "build/Declic.app"
#   ./build.sh run       build, then launch the app
#   ./build.sh install   build, install to /Applications and relaunch (recommended)
#   ./build.sh test      run the automated tests
#   ./build.sh dmg       build, then create "build/Declic.dmg"
#
# The app is signed with a local certificate created automatically the first time
# ("Declic Local Signing", in your login keychain). The signature stays the same from one
# build to the next, so macOS keeps its permissions (Screen Recording, Accessibility…)
# after every update.
#
# Environment:
#   SIGN_ID      signing identity (e.g. "Developer ID Application: … (TEAMID)", or "-" for ad-hoc)
#   GITHUB_REPO  public repository used for updates (otherwise read from .github-repo)
#   RELEASE=1    distribution build (without the source folder path)
set -euo pipefail
cd "$(dirname "$0")"

IDENTITY="Declic Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
OPENSSL=/usr/bin/openssl
APP="build/Declic.app"
INSTALLED="/Applications/Declic.app"
BUNDLE_ID="com.lightmaster.declic"

if [[ "${1:-}" == "test" ]]; then
    swift test
    exit 0
fi

ensure_identity() {
    if security find-identity -p codesigning "$KEYCHAIN" 2>/dev/null | grep -q "$IDENTITY"; then
        return 0
    fi
    echo "🔐 Creating the local signing certificate \"$IDENTITY\" (one time only)…"
    local tmp
    tmp=$(mktemp -d)
    cat > "$tmp/cert.cnf" <<CNF
[req]
distinguished_name = dn
prompt = no
[dn]
CN = $IDENTITY
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF
    "$OPENSSL" req -x509 -newkey rsa:2048 -nodes -days 3650 \
        -keyout "$tmp/key.pem" -out "$tmp/cert.pem" \
        -config "$tmp/cert.cnf" -extensions ext >/dev/null 2>&1
    "$OPENSSL" pkcs12 -export -inkey "$tmp/key.pem" -in "$tmp/cert.pem" -name "$IDENTITY" \
        -out "$tmp/identity.p12" -passout pass:declic >/dev/null 2>&1
    security import "$tmp/identity.p12" -k "$KEYCHAIN" -P declic -T /usr/bin/codesign >/dev/null
    echo "   macOS may ask for your password to trust the certificate."
    security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$tmp/cert.pem" || true
    rm -rf "$tmp"
}

make_dmg() {
    local dmg="build/Declic.dmg" stage
    stage=$(mktemp -d)
    cp -R "$APP" "$stage/"
    ln -s /Applications "$stage/Applications"
    rm -f "$dmg"
    hdiutil create -volname "Declic" -srcfolder "$stage" -ov -format UDZO -quiet "$dmg"
    rm -rf "$stage"
    if [[ "$SIGN_ID" != "-" ]]; then
        codesign --force --sign "$SIGN_ID" ${EXTRA_SIGN_FLAGS[@]+"${EXTRA_SIGN_FLAGS[@]}"} "$dmg" 2>/dev/null || true
    fi
    echo "💿 $dmg ready"
}

# 1. Compile
swift build -c release

# 2. Assemble the app bundle
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Declic "$APP/Contents/MacOS/Declic"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Source folder (diagnostic logs in development builds).
if [[ -z "${RELEASE:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Add :DeclicSourceDir string $PWD" "$APP/Contents/Info.plist"
fi
# Public GitHub repository used for automatic updates ("owner/repo").
GITHUB_REPO="${GITHUB_REPO:-$(cat .github-repo 2>/dev/null | tr -d '[:space:]' || true)}"
if [[ -n "$GITHUB_REPO" ]]; then
    /usr/libexec/PlistBuddy -c "Add :DeclicGitHubRepo string $GITHUB_REPO" "$APP/Contents/Info.plist"
fi

# 3. Stable signature
SIGN_ID="${SIGN_ID:-}"
if [[ -z "$SIGN_ID" ]]; then
    if ensure_identity; then SIGN_ID="$IDENTITY"; else SIGN_ID="-"; fi
fi
# Developer ID certificate (distribution): hardened runtime + timestamp, required for notarization.
EXTRA_SIGN_FLAGS=()
if [[ "$SIGN_ID" == Developer\ ID* ]]; then
    EXTRA_SIGN_FLAGS=(--options runtime --timestamp)
fi
if ! codesign --force --deep --sign "$SIGN_ID" --identifier "$BUNDLE_ID" ${EXTRA_SIGN_FLAGS[@]+"${EXTRA_SIGN_FLAGS[@]}"} "$APP" 2>/dev/null; then
    echo "⚠️  Could not sign with \"$SIGN_ID\"; using an ad-hoc signature instead (permissions will be asked again)."
    codesign --force --deep --sign - "$APP"
    SIGN_ID="-"
fi
echo "✅ $APP ready (signed with: $SIGN_ID)"

# 4. Launch / install / package
case "${1:-}" in
    run)
        pkill -x Declic 2>/dev/null || true
        sleep 0.4
        open "$APP"
        ;;
    install)
        pkill -x Declic 2>/dev/null || true
        sleep 0.4
        rm -rf /Applications/D*clic.app   # also removes the old accented name
        ditto "$APP" "$INSTALLED"
        echo "📦 Installed to $INSTALLED"
        open "$INSTALLED"
        ;;
    dmg)
        make_dmg
        ;;
esac
