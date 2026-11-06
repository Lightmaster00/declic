# Déclic

**Capture, annote, partage — en un déclic.**
Captures d'écran, capture défilante, enregistrement vidéo et GIF pour macOS 14+.
App native (Swift, ScreenCaptureKit), **gratuite et open source** (licence MIT) : tout reste sur ton Mac.

**[Télécharger la dernière version](https://github.com/Lightmaster00/declic/releases/latest)** · [Site](https://lightmaster00.github.io/declic/)

### Installation

1. Télécharge `Declic-x.y.z.zip`, ouvre-le et glisse **Déclic** dans *Applications*.
2. Au premier lancement, macOS peut indiquer que l'app vient d'un développeur non identifié :
   ouvre *Réglages Système › Confidentialité et sécurité* et clique **Ouvrir quand même**.
3. Autorise *Enregistrement de l'écran* (et *Accessibilité* pour le défilement automatique).

Les mises à jour suivantes s'installent ensuite depuis l'app, en un clic.

![Icône](Branding/icon-256.png)

## Fonctionnalités

L'interface suit la langue du système (français, anglais, espagnol, allemand, japonais ; anglais sinon).
Tous les raccourcis se modifient dans **Réglages › Raccourcis**.

| Raccourci par défaut | Action |
|-----------|--------|
| ⌥⇧3 | Capture plein écran |
| ⌥⇧4 | Capture d'une zone — glisser = zone, Espace = choisir une fenêtre, Maj = carré, Entrée = plein écran, Échap = annuler |
| ⌥⇧5 | Capture d'une fenêtre : toutes les fenêtres s'étalent, un clic capture, retour immédiat à l'écran d'origine |
| ⌥⇧8 | Capture défilante : choisis la fenêtre, fais défiler (dans les deux sens) ou *Défilement automatique*, puis *Terminer* |
| ⌥⇧6 | Enregistrement : **Zone**, **Plein écran** ou **Application**, en vidéo MP4 ou en GIF |
| ⌥⇧H | Historique des captures |

- **Vignette d'accès rapide** (en bas à gauche) : clic = éditeur ; au survol *Copier*, *Enregistrer*
  (avec confirmation animée), *Garder* (la vignette reste affichée) et *Fermer* ; glisser-déposer
  vers n'importe quelle app ; la pile défile quand elle dépasse la hauteur de l'écran.
- **Éditeur d'annotations** : flèches, formes, texte, surligneur, pixellisation, numéros, recadrage,
  annuler / rétablir, zoom (pincement, ⌘+ / ⌘− / ⌘0 / ⌘1, Espace + glisser).
- **Capture défilante** : Déclic repère la partie qui défile sous ton pointeur (sans la barre
  d'outils ni les autres panneaux) et assemble le contenu. Le défilement automatique demande
  l'autorisation *Accessibilité*.
- **Enregistrement** : zone redimensionnable, compte à rebours, pointeur et clics, export GIF.
- **Historique** : toutes les captures et vidéos, avec copie, enregistrement, annotation, suppression.
- **Mises à jour** : proposées automatiquement dès qu'une nouvelle version est publiée.

## Développement

```bash
./build.sh install   # compile, installe /Applications/Déclic.app et relance
./build.sh test      # tests automatiques
./build.sh run       # lance la version de build/ sans l'installer
```

- **Autorisations conservées** : au premier build, un certificat local (« Declic Local Signing »)
  est créé dans le trousseau ; toutes les versions suivantes sont signées avec lui, donc
  *Enregistrement de l'écran* et *Accessibilité* ne sont pas redemandés.
- **Intégration continue** : chaque envoi sur GitHub compile l'app et lance les tests sur un Mac
  (onglet *Actions* du dépôt).
- **Journal de la capture défilante** : `build/debug/scroll.log` (build de développement) ou
  `~/Library/Logs/Declic/scroll.log`.

## Publier une version

Le code, les versions téléchargeables et le site sont dans le dépôt public indiqué par
`.github-repo` (`Lightmaster00/declic`).

```bash
brew install gh && gh auth login     # une seule fois
./release.sh 1.0.1 "Ce qui change"
```

Chaque app installée vérifie les mises à jour au lancement puis toutes les 24 h (désactivable dans
Réglages › Général) et propose *Installer et redémarrer*. Une version signée avec un autre
certificat que l'app installée est refusée.

Les versions sont signées avec le certificat local de la machine qui publie : publie-les toujours
depuis le même Mac. Avec un certificat Apple *Developer ID* et la notarisation (voir `release.sh`),
l'avertissement « développeur non identifié » disparaît.

## Contribuer

Les contributions sont bienvenues : ouvre une *issue* pour signaler un bug ou proposer une idée,
ou une *pull request* (les tests doivent passer : `./build.sh test`).

## Licence

MIT — voir [LICENSE](LICENSE). Le nom et l'icône « Déclic » identifient ce projet.

## Structure

```
Sources/Declic/
  App.swift / AppDelegate.swift   point d'entrée, menu de la barre des menus, raccourcis
  Brand.swift                     couleurs et icône de la barre des menus
  Capturer.swift                  ScreenCaptureKit + orchestration des captures
  Overlay.swift                   sélection de zone (curseurs, poignées)
  MissionControl.swift / WindowGallery.swift   choix d'une fenêtre
  ScrollCapture.swift             capture défilante (détection de la zone, assemblage)
  QuickAccess.swift               vignettes d'accès rapide
  Editor.swift / EditorModel.swift   éditeur d'annotations
  Recording.swift                 enregistrement vidéo / GIF
  History.swift / Preview.swift   historique, aperçu des vidéos
  Settings.swift / Prefs.swift / Shortcuts.swift / HotKeys.swift
  Updater.swift                   mises à jour depuis GitHub
  Localization*.swift             textes (5 langues)
  UIComponents.swift / Util.swift
Tests/DeclicTests/                tests (assemblage, détection des panneaux, versions, galerie)
Branding/                         icône, charte (BRAND.md)
site/                             page de présentation (publiée sur GitHub Pages)
```
