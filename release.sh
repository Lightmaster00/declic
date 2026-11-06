#!/bin/bash
# Publie une nouvelle version de Déclic sur GitHub. Les apps installées la proposent
# ensuite automatiquement (menu « Rechercher des mises à jour… » ou vérification quotidienne).
#
#   ./release.sh 1.0.1 "Notes de version"
#
# Prérequis (une seule fois) :
#   - le fichier .github-repo contient « propriétaire/dépôt » (ex. Lightmaster00/declic), dépôt public ;
#   - l'outil gh est installé et connecté : brew install gh && gh auth login.
#
# Optionnel : avec un certificat Apple « Developer ID » et la notarisation, macOS n'affiche plus
# l'avertissement « développeur non identifié » au premier lancement :
#   SIGN_ID="Developer ID Application: Ton Nom (TEAMID)" NOTARY_PROFILE=declic ./release.sh 1.0.1
#   (profil créé une fois avec : xcrun notarytool store-credentials declic)
#
# Important : les mises à jour n'acceptent qu'une app signée avec le même certificat que
# l'app installée. En changeant de certificat, la première version se réinstalle à la main.
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${1:?Usage : ./release.sh <version> [notes]}"
NOTES="${2:-Déclic $VERSION}"
REPO="${GITHUB_REPO:-$(cat .github-repo 2>/dev/null | tr -d '[:space:]' || true)}"
[[ -n "$REPO" ]] || { echo "❌ Crée le fichier .github-repo avec « propriétaire/dépôt »."; exit 1; }
command -v gh >/dev/null || { echo "❌ Installe gh : brew install gh && gh auth login"; exit 1; }

# 1. Version dans l'Info.plist.
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" Resources/Info.plist
BUILD_NUMBER=$(( $(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" Resources/Info.plist) + 1 ))
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" Resources/Info.plist

# 2. Compilation et signature (sans le chemin des sources).
RELEASE=1 GITHUB_REPO="$REPO" ./build.sh

# 3. Archive.
ZIP="build/Declic-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "build/Déclic.app" "$ZIP"

# 4. Notarisation (si un profil est fourni).
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    echo "📮 Notarisation…"
    xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "build/Déclic.app"
    rm -f "$ZIP"
    ditto -c -k --keepParent "build/Déclic.app" "$ZIP"
fi

# 5. Publication.
gh release create "v$VERSION" "$ZIP" --repo "$REPO" --title "Déclic $VERSION" --notes "$NOTES"
echo "✅ Déclic $VERSION publiée sur https://github.com/$REPO/releases"
