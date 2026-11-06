#!/bin/bash
# Compile Déclic.
#
#   ./build.sh           compile « build/Déclic.app »
#   ./build.sh run       compile puis lance l'app
#   ./build.sh install   compile, installe dans /Applications et relance (recommandé)
#   ./build.sh test      lance les tests automatiques
#
# L'app est signée avec un certificat local créé automatiquement la première fois
# (« Declic Local Signing », dans ton trousseau). La signature reste la même d'un
# build à l'autre : macOS garde donc les autorisations (Enregistrement de l'écran,
# Accessibilité…) après chaque mise à jour.
#
# Variables :
#   SIGN_ID      identité de signature (ex. « Developer ID Application: … (TEAMID) »)
#   GITHUB_REPO  dépôt public des mises à jour (sinon lu dans .github-repo)
#   RELEASE=1    build de distribution (sans le chemin des sources)
set -euo pipefail
cd "$(dirname "$0")"

IDENTITY="Declic Local Signing"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
OPENSSL=/usr/bin/openssl
APP="build/Déclic.app"
INSTALLED="/Applications/Déclic.app"
BUNDLE_ID="com.lightmaster.declic"

if [[ "${1:-}" == "test" ]]; then
    swift test
    exit 0
fi

ensure_identity() {
    if security find-identity -p codesigning "$KEYCHAIN" 2>/dev/null | grep -q "$IDENTITY"; then
        return 0
    fi
    echo "🔐 Création du certificat de signature local « $IDENTITY » (une seule fois)…"
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
    echo "   macOS va peut-être demander ton mot de passe pour faire confiance au certificat."
    security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$tmp/cert.pem" || true
    rm -rf "$tmp"
}

# 1. Compilation
swift build -c release

# 2. Assemblage de l'app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Declic "$APP/Contents/MacOS/Declic"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Emplacement des sources (journaux de diagnostic des builds de développement).
if [[ -z "${RELEASE:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Add :DeclicSourceDir string $PWD" "$APP/Contents/Info.plist"
fi
# Dépôt GitHub public des mises à jour automatiques (« propriétaire/dépôt »).
GITHUB_REPO="${GITHUB_REPO:-$(cat .github-repo 2>/dev/null | tr -d '[:space:]' || true)}"
if [[ -n "$GITHUB_REPO" ]]; then
    /usr/libexec/PlistBuddy -c "Add :DeclicGitHubRepo string $GITHUB_REPO" "$APP/Contents/Info.plist"
fi

# 3. Signature stable
SIGN_ID="${SIGN_ID:-}"
if [[ -z "$SIGN_ID" ]]; then
    if ensure_identity; then SIGN_ID="$IDENTITY"; else SIGN_ID="-"; fi
fi
# Certificat « Developer ID » (distribution) : runtime renforcé + horodatage, requis pour la notarisation.
EXTRA_SIGN_FLAGS=()
if [[ "$SIGN_ID" == Developer\ ID* ]]; then
    EXTRA_SIGN_FLAGS=(--options runtime --timestamp)
fi
if ! codesign --force --deep --sign "$SIGN_ID" --identifier "$BUNDLE_ID" ${EXTRA_SIGN_FLAGS[@]+"${EXTRA_SIGN_FLAGS[@]}"} "$APP" 2>/dev/null; then
    echo "⚠️  Signature avec « $SIGN_ID » impossible, signature ad-hoc à la place (les autorisations seront redemandées)."
    codesign --force --deep --sign - "$APP"
    SIGN_ID="-"
fi
echo "✅ $APP prêt (signé avec : $SIGN_ID)"

# 4. Lancement / installation
case "${1:-}" in
    run)
        pkill -x Declic 2>/dev/null || true
        sleep 0.4
        open "$APP"
        ;;
    install)
        pkill -x Declic 2>/dev/null || true
        pkill -x ShotKit 2>/dev/null || true   # ancienne version
        sleep 0.4
        rm -rf "$INSTALLED"
        ditto "$APP" "$INSTALLED"
        echo "📦 Installé dans $INSTALLED"
        open "$INSTALLED"
        ;;
esac
