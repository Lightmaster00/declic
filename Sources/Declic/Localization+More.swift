import Foundation

/// Strings for settings, history and the newer modes.
extension S {
    // MARK: Menu / general
    static var settings: String { tr("Settings…", "Réglages…", "Ajustes…", "Einstellungen …", "設定…") }
    static var history: String { tr("Capture History", "Historique des captures", "Historial de capturas", "Aufnahmeverlauf", "キャプチャ履歴") }
    static var record: String { tr("Record", "Enregistrer", "Grabar", "Aufnehmen", "収録") }
    static var none: String { tr("None", "Aucun", "Ninguno", "Keiner", "なし") }
    static var never: String { tr("Never", "Jamais", "Nunca", "Nie", "しない") }
    static var change: String { tr("Change…", "Modifier…", "Cambiar…", "Ändern …", "変更…") }
    static var delete: String { tr("Delete", "Supprimer", "Eliminar", "Löschen", "削除") }
    static var showInFinder: String { tr("Show in Finder", "Afficher dans le Finder", "Mostrar en el Finder", "Im Finder zeigen", "Finder で表示") }
    static var version: String { tr("Version", "Version", "Versión", "Version", "バージョン") }
    static var aboutText: String {
        tr("Screenshots, annotations, recordings and scrolling captures for macOS.",
           "Captures d'écran, annotations, enregistrements et captures défilantes pour macOS.",
           "Capturas, anotaciones, grabaciones y capturas con desplazamiento para macOS.",
           "Bildschirmfotos, Anmerkungen, Aufnahmen und Scroll-Aufnahmen für macOS.",
           "macOS 用のスクリーンショット、注釈、画面収録、スクロールキャプチャ。")
    }
    static func seconds(_ n: Int) -> String { tr("\(n) seconds", "\(n) secondes", "\(n) segundos", "\(n) Sekunden", "\(n) 秒") }
    static func days(_ n: Int) -> String {
        n == 1 ? tr("1 day", "1 jour", "1 día", "1 Tag", "1 日")
               : tr("\(n) days", "\(n) jours", "\(n) días", "\(n) Tage", "\(n) 日")
    }
    static var forever: String { tr("Forever", "Toujours", "Siempre", "Für immer", "無期限") }

    // MARK: Tabs
    static var tabGeneral: String { tr("General", "Général", "General", "Allgemein", "一般") }
    static var tabCaptures: String { tr("Screenshots", "Captures", "Capturas", "Bildschirmfotos", "スクリーンショット") }
    static var tabQuickAccess: String { tr("Quick Access", "Accès rapide", "Acceso rápido", "Schnellzugriff", "クイックアクセス") }
    static var tabRecording: String { tr("Recording", "Enregistrement", "Grabación", "Aufnahme", "収録") }
    static var tabShortcuts: String { tr("Shortcuts", "Raccourcis", "Atajos", "Kurzbefehle", "ショートカット") }
    static var tabHistory: String { tr("History", "Historique", "Historial", "Verlauf", "履歴") }
    static var tabAbout: String { tr("About", "À propos", "Acerca de", "Über", "情報") }

    // MARK: General
    static var launchAtLogin: String { tr("Launch at login", "Ouvrir au démarrage de la session", "Abrir al iniciar sesión", "Beim Anmelden öffnen", "ログイン時に起動") }
    static var exportSection: String { tr("Export", "Exportation", "Exportación", "Export", "書き出し") }
    static var exportLocation: String { tr("Save to", "Enregistrer dans", "Guardar en", "Sichern in", "保存先") }
    static var filePrefixLabel: String { tr("File name prefix", "Préfixe du nom de fichier", "Prefijo del nombre", "Dateinamen-Präfix", "ファイル名の接頭辞") }
    static var afterScreenshot: String { tr("After taking a screenshot", "Après une capture d'écran", "Después de una captura", "Nach einem Bildschirmfoto", "スクリーンショットの後") }
    static var afterRecording: String { tr("After recording", "Après un enregistrement", "Después de grabar", "Nach einer Aufnahme", "収録の後") }
    static var showQuickAccess: String { tr("Show Quick Access overlay", "Afficher la vignette d'accès rapide", "Mostrar miniatura de acceso rápido", "Schnellzugriff anzeigen", "クイックアクセスを表示") }
    static var copyToClipboard: String { tr("Copy to clipboard", "Copier dans le presse-papiers", "Copiar al portapapeles", "In die Zwischenablage kopieren", "クリップボードにコピー") }
    static var copyFileToClipboard: String { tr("Copy file to clipboard", "Copier le fichier dans le presse-papiers", "Copiar archivo al portapapeles", "Datei in die Zwischenablage kopieren", "ファイルをクリップボードにコピー") }
    static var saveToFolder: String { tr("Save to folder", "Enregistrer dans le dossier", "Guardar en la carpeta", "Im Ordner sichern", "フォルダに保存") }
    static var openAnnotate: String { tr("Open annotation editor", "Ouvrir l'éditeur d'annotations", "Abrir el editor de anotaciones", "Anmerkungseditor öffnen", "注釈エディタを開く") }
    static var pinToScreen: String { tr("Pin to screen", "Épingler à l'écran", "Fijar en pantalla", "Am Bildschirm anheften", "画面にピン留め") }

    // MARK: Captures
    static var fileSection: String { tr("File", "Fichier", "Archivo", "Datei", "ファイル") }
    static var fileFormat: String { tr("Format", "Format", "Formato", "Format", "フォーマット") }
    static var quality: String { tr("Quality", "Qualité", "Calidad", "Qualität", "画質") }
    static var scaleTo1x: String { tr("Scale Retina screenshots to 1x", "Réduire les captures Retina en 1x", "Reducir capturas Retina a 1x", "Retina-Bildschirmfotos auf 1x skalieren", "Retina のスクリーンショットを 1x に縮小") }
    static var scaleTo1xHelp: String { tr("Smaller files, same size on screen.", "Fichiers plus légers, même taille à l'écran.", "Archivos más ligeros, mismo tamaño en pantalla.", "Kleinere Dateien, gleiche Größe auf dem Bildschirm.", "ファイルが小さくなり、画面上の大きさは同じです。") }
    static var areaSection: String { tr("Area selection", "Sélection de zone", "Selección de área", "Bereichsauswahl", "範囲選択") }
    static var freezeScreen: String { tr("Freeze screen while selecting", "Figer l'écran pendant la sélection", "Congelar la pantalla al seleccionar", "Bildschirm bei Auswahl einfrieren", "選択中は画面を固定") }
    static var showMagnifier: String { tr("Show magnifier", "Afficher la loupe", "Mostrar lupa", "Lupe anzeigen", "拡大鏡を表示") }
    static var showCrosshair: String { tr("Show guide lines", "Afficher les lignes de repère", "Mostrar líneas guía", "Hilfslinien anzeigen", "ガイド線を表示") }
    static var hideDesktopIcons: String { tr("Hide desktop icons while capturing", "Masquer les icônes du bureau pendant la capture", "Ocultar iconos del escritorio al capturar", "Schreibtischsymbole beim Aufnehmen ausblenden", "キャプチャ中はデスクトップアイコンを隠す") }
    static var hideDesktopIconsHelp: String { tr("Your wallpaper is shown instead of the icons.", "Ton fond d'écran est affiché à la place des icônes.", "Se muestra el fondo de pantalla en lugar de los iconos.", "Statt der Symbole wird das Hintergrundbild gezeigt.", "アイコンの代わりに壁紙が表示されます。") }
    static var windowSection: String { tr("Window screenshots", "Captures de fenêtre", "Capturas de ventana", "Fensteraufnahmen", "ウインドウのキャプチャ") }
    static var windowShadow: String { tr("Include window shadow", "Inclure l'ombre de la fenêtre", "Incluir sombra de la ventana", "Fensterschatten einbeziehen", "ウインドウの影を含める") }
    static var windowBackgroundLabel: String { tr("Background", "Arrière-plan", "Fondo", "Hintergrund", "背景") }
    static var bgTransparent: String { tr("Transparent", "Transparent", "Transparente", "Transparent", "透明") }
    static var bgWhite: String { tr("White", "Blanc", "Blanco", "Weiß", "白") }
    static var bgLight: String { tr("Light gray", "Gris clair", "Gris claro", "Hellgrau", "ライトグレー") }
    static var bgDark: String { tr("Dark", "Sombre", "Oscuro", "Dunkel", "ダーク") }
    static var bgCustom: String { tr("Custom color", "Couleur personnalisée", "Color personalizado", "Eigene Farbe", "カスタムカラー") }
    static var bgColor: String { tr("Color", "Couleur", "Color", "Farbe", "色") }
    static var padding: String { tr("Padding", "Marge", "Margen", "Rand", "余白") }

    // MARK: Quick Access
    static var position: String { tr("Position", "Position", "Posición", "Position", "位置") }
    static var bottomLeft: String { tr("Bottom left", "En bas à gauche", "Abajo a la izquierda", "Unten links", "左下") }
    static var bottomRight: String { tr("Bottom right", "En bas à droite", "Abajo a la derecha", "Unten rechts", "右下") }
    static var overlaySize: String { tr("Size", "Taille", "Tamaño", "Größe", "サイズ") }
    static var sizeSmall: String { tr("Small", "Petite", "Pequeño", "Klein", "小") }
    static var sizeMedium: String { tr("Medium", "Moyenne", "Mediano", "Mittel", "中") }
    static var sizeLarge: String { tr("Large", "Grande", "Grande", "Groß", "大") }
    static var autoClose: String { tr("Close automatically after", "Fermer automatiquement après", "Cerrar automáticamente tras", "Automatisch schließen nach", "自動的に閉じるまで") }
    static var autoCloseHelp: String {
        tr("The overlay stays open while the pointer is over it.",
           "La vignette reste ouverte tant que le pointeur est dessus.",
           "La miniatura sigue abierta mientras el puntero esté encima.",
           "Die Vorschau bleibt geöffnet, solange der Zeiger darauf ist.",
           "ポインタが上にある間は閉じません。")
    }

    // MARK: Recording
    static var videoSection: String { tr("Video", "Vidéo", "Vídeo", "Video", "ビデオ") }
    static var frameRate: String { tr("Frame rate", "Images par seconde", "Fotogramas por segundo", "Bildrate", "フレームレート") }
    static var qualityStandard: String { tr("Standard", "Standard", "Estándar", "Standard", "標準") }
    static var qualityHigh: String { tr("High", "Haute", "Alta", "Hoch", "高") }
    static var showCursor: String { tr("Show cursor", "Afficher le pointeur", "Mostrar puntero", "Zeiger anzeigen", "ポインタを表示") }
    static var countdown: String { tr("Countdown", "Compte à rebours", "Cuenta atrás", "Countdown", "カウントダウン") }
    static var maxWidth: String { tr("Maximum width", "Largeur maximale", "Ancho máximo", "Maximale Breite", "最大幅") }
    static var clickToSelect: String { tr("Click to select", "Clique pour sélectionner", "Haz clic para seleccionar", "Zum Auswählen klicken", "クリックで選択") }

    // MARK: Shortcuts
    static var typeShortcut: String { tr("Type shortcut…", "Tape le raccourci…", "Pulsa el atajo…", "Kurzbefehl drücken …", "ショートカットを入力…") }
    static var clearShortcut: String { tr("Remove shortcut", "Supprimer le raccourci", "Quitar atajo", "Kurzbefehl entfernen", "ショートカットを削除") }
    static var restoreDefaults: String { tr("Restore Defaults", "Valeurs par défaut", "Restaurar", "Standard wiederherstellen", "デフォルトに戻す") }
    static var shortcutsHelp: String {
        tr("Click a field, then press the new combination. ⌫ removes it, Esc cancels.",
           "Clique sur un champ puis tape la nouvelle combinaison. ⌫ la supprime, Échap annule.",
           "Haz clic en un campo y pulsa la combinación. ⌫ la quita, Esc cancela.",
           "Feld anklicken und Kombination drücken. ⌫ entfernt, Esc bricht ab.",
           "欄をクリックして組み合わせを押します。⌫ で削除、Esc でキャンセル。")
    }

    // MARK: History
    static var keepHistory: String { tr("Keep capture history", "Conserver l'historique des captures", "Guardar historial de capturas", "Aufnahmeverlauf behalten", "キャプチャ履歴を保持") }
    static var keepFor: String { tr("Keep for", "Conserver pendant", "Conservar durante", "Behalten für", "保持期間") }
    static var openHistory: String { tr("Open History…", "Ouvrir l'historique…", "Abrir historial…", "Verlauf öffnen …", "履歴を開く…") }
    static var clearHistory: String { tr("Clear History", "Effacer l'historique", "Borrar historial", "Verlauf löschen", "履歴を消去") }
    static var clearHistoryConfirm: String {
        tr("Delete all captures from the history?", "Supprimer toutes les captures de l'historique ?",
           "¿Eliminar todas las capturas del historial?", "Alle Aufnahmen aus dem Verlauf löschen?",
           "履歴のすべてのキャプチャを削除しますか?")
    }
    static var historyEmpty: String { tr("No captures yet", "Aucune capture pour l'instant", "Aún no hay capturas", "Noch keine Aufnahmen", "まだキャプチャはありません") }
    static var filterAll: String { tr("All", "Tout", "Todo", "Alle", "すべて") }
    static var filterScreenshots: String { tr("Screenshots", "Captures", "Capturas", "Bildschirmfotos", "スクリーンショット") }
    static var filterRecordings: String { tr("Recordings", "Vidéos", "Grabaciones", "Aufnahmen", "収録") }
    static func itemsCount(_ n: Int) -> String {
        tr("\(n) item\(n > 1 ? "s" : "")", "\(n) élément\(n > 1 ? "s" : "")", "\(n) elemento\(n > 1 ? "s" : "")",
           "\(n) Objekt\(n > 1 ? "e" : "")", "\(n) 件")
    }

    // MARK: Scrolling capture
    static var clickToScroll: String { tr("Click the window to scroll", "Clique sur la fenêtre à faire défiler", "Haz clic en la ventana a desplazar", "Zu scrollendes Fenster anklicken", "スクロールするウインドウをクリック") }
    static var autoScroll: String { tr("Auto-scroll", "Défilement automatique", "Desplazamiento automático", "Automatisch scrollen", "自動スクロール") }
    static var autoScrolling: String { tr("Scrolling automatically…", "Défilement automatique…", "Desplazando automáticamente…", "Scrollt automatisch …", "自動スクロール中…") }

    // MARK: Gallery / preview
    static var galleryHint: String {
        tr("Click a window to capture it · Esc to cancel", "Clique sur une fenêtre pour la capturer · Échap pour annuler",
           "Haz clic en una ventana para capturarla · Esc para cancelar", "Fenster anklicken zum Aufnehmen · Esc zum Abbrechen",
           "ウインドウをクリックしてキャプチャ · Esc でキャンセル")
    }
    static var clickToPreview: String { tr("Click to preview", "Clique pour l'aperçu", "Haz clic para previsualizar", "Klicken für Vorschau", "クリックでプレビュー") }
    static var pinShort: String { tr("Pin", "Épingler", "Fijar", "Anheften", "ピン留め") }
    static var options: String { tr("Options", "Options", "Opciones", "Optionen", "オプション") }

    // MARK: Scrolling capture / thumbnails
    static var tooFast: String { tr("Too fast — scroll back up a little", "Trop rapide — remonte un peu", "Demasiado rápido — sube un poco", "Zu schnell – etwas zurückscrollen", "速すぎます — 少し戻してください") }
    static var maxHeightReached: String { tr("Maximum height reached", "Hauteur maximale atteinte", "Altura máxima alcanzada", "Maximale Höhe erreicht", "最大の高さに達しました") }
    static var clickToAnnotate: String { tr("Click to annotate", "Clique pour annoter", "Haz clic para anotar", "Klicken zum Kommentieren", "クリックで注釈") }

    // MARK: Update
    static var updateApp: String { tr("Update Déclic", "Mettre à jour Déclic", "Actualizar Déclic", "Déclic aktualisieren", "Déclic をアップデート") }
    static var updating: String { tr("Updating… Déclic will restart", "Mise à jour… Déclic va redémarrer", "Actualizando… Déclic se reiniciará", "Aktualisierung … Déclic startet neu", "アップデート中… Déclic は再起動します") }
    static var updateFailed: String { tr("Update failed", "La mise à jour a échoué", "Error al actualizar", "Aktualisierung fehlgeschlagen", "アップデートに失敗しました") }
    static var updateFailedHelp: String { tr("The build did not finish. The log shows the error.", "La compilation n'a pas abouti. Le journal indique l'erreur.", "La compilación no terminó. El registro muestra el error.", "Der Build wurde nicht abgeschlossen. Das Protokoll zeigt den Fehler.", "ビルドが完了しませんでした。ログにエラーが表示されています。") }
    static var showLog: String { tr("Show Log", "Afficher le journal", "Ver registro", "Protokoll zeigen", "ログを表示") }

    // MARK: Keep thumbnail
    static var pinCard: String { tr("Keep this thumbnail", "Garder cette vignette", "Mantener esta miniatura", "Diese Vorschau behalten", "このサムネイルを残す") }
    static var unpinCard: String { tr("Stop keeping this thumbnail", "Ne plus garder cette vignette", "Dejar de mantener la miniatura", "Vorschau nicht mehr behalten", "サムネイルを残さない") }
    static var areaHint: String { tr("Drag to capture · Space: window", "Glisse pour capturer · Espace : fenêtre", "Arrastra para capturar · Espacio: ventana", "Ziehen zum Aufnehmen · Leertaste: Fenster", "ドラッグでキャプチャ · スペース: ウインドウ") }
    static var zoomIn: String { tr("Zoom In", "Zoom avant", "Acercar", "Vergrößern", "拡大") }
    static var zoomOut: String { tr("Zoom Out", "Zoom arrière", "Alejar", "Verkleinern", "縮小") }
    static var zoomFit: String { tr("Fit to Window", "Ajuster à la fenêtre", "Ajustar a la ventana", "An Fenster anpassen", "ウインドウに合わせる") }
    static var zoomActual: String { tr("Actual Size", "Taille réelle", "Tamaño real", "Originalgröße", "実際のサイズ") }
    // MARK: Updates (GitHub)
    static var checkForUpdates: String { tr("Check for Updates…", "Rechercher des mises à jour…", "Buscar actualizaciones…", "Nach Updates suchen …", "アップデートを確認…") }
    static var autoCheckUpdates: String { tr("Check for updates automatically", "Rechercher les mises à jour automatiquement", "Buscar actualizaciones automáticamente", "Automatisch nach Updates suchen", "自動的にアップデートを確認") }
    static var checkNow: String { tr("Check Now", "Vérifier", "Comprobar", "Jetzt prüfen", "今すぐ確認") }
    static var upToDate: String { tr("Déclic is up to date", "Déclic est à jour", "Déclic está actualizado", "Déclic ist aktuell", "Déclic は最新です") }
    static func upToDateDetail(_ v: String) -> String { tr("You have the latest version (\(v)).", "Tu as la dernière version (\(v)).", "Tienes la última versión (\(v)).", "Du hast die neueste Version (\(v)).", "最新バージョン (\(v)) です。") }
    static func updateAvailable(_ v: String) -> String { tr("Déclic \(v) is available", "Déclic \(v) est disponible", "Déclic \(v) está disponible", "Déclic \(v) ist verfügbar", "Déclic \(v) が利用可能です") }
    static func updateAvailableDetail(current: String) -> String { tr("You have version \(current). The update installs in a few seconds and Déclic restarts.", "Tu as la version \(current). La mise à jour s'installe en quelques secondes, puis Déclic redémarre.", "Tienes la versión \(current). La actualización se instala en unos segundos y Déclic se reinicia.", "Du hast Version \(current). Das Update wird in Sekunden installiert, dann startet Déclic neu.", "現在のバージョンは \(current) です。数秒でインストールされ、Déclic が再起動します。") }
    static var installAndRestart: String { tr("Install and Restart", "Installer et redémarrer", "Instalar y reiniciar", "Installieren und neu starten", "インストールして再起動") }
    static var later: String { tr("Later", "Plus tard", "Más tarde", "Später", "後で") }
    static var skipVersion: String { tr("Skip This Version", "Ignorer cette version", "Omitir esta versión", "Diese Version überspringen", "このバージョンをスキップ") }
    static var downloadingUpdate: String { tr("Downloading the update…", "Téléchargement de la mise à jour…", "Descargando la actualización…", "Update wird geladen …", "アップデートをダウンロード中…") }
    static var installingUpdate: String { tr("Installing…", "Installation…", "Instalando…", "Installation …", "インストール中…") }
    static var restarting: String { tr("Restarting Déclic…", "Redémarrage de Déclic…", "Reiniciando Déclic…", "Déclic startet neu …", "Déclic を再起動中…") }
    static var updateCheckFailed: String { tr("Could not check for updates", "Impossible de vérifier les mises à jour", "No se pudieron buscar actualizaciones", "Updates konnten nicht geprüft werden", "アップデートを確認できませんでした") }
    static var downloadManually: String { tr("Download Manually", "Télécharger manuellement", "Descargar manualmente", "Manuell laden", "手動でダウンロード") }
    static var updateNoAsset: String { tr("The release has no .zip file.", "La version publiée ne contient pas de fichier .zip.", "La versión no contiene un archivo .zip.", "Die Version enthält keine .zip-Datei.", "リリースに .zip ファイルがありません。") }
    static var updateBadArchive: String { tr("The downloaded archive is damaged.", "L'archive téléchargée est endommagée.", "El archivo descargado está dañado.", "Das geladene Archiv ist beschädigt.", "ダウンロードしたアーカイブが破損しています。") }
    static var updateBadSignature: String { tr("The downloaded app is not signed like this one: it was not installed.", "L'app téléchargée n'a pas la même signature que celle-ci : elle n'a pas été installée.", "La app descargada no tiene la misma firma: no se instaló.", "Die geladene App ist anders signiert und wurde nicht installiert.", "ダウンロードしたアプリの署名が一致しないため、インストールしませんでした。") }
    static func updateCannotReplace(_ folder: String) -> String { tr("Déclic cannot write to \(folder).", "Déclic ne peut pas écrire dans \(folder).", "Déclic no puede escribir en \(folder).", "Déclic kann nicht in \(folder) schreiben.", "Déclic は \(folder) に書き込めません。") }

    static var tagline: String { tr("Capture, annotate, share — in one click.", "Capture, annote, partage — en un déclic.", "Captura, anota, comparte — en un clic.", "Aufnehmen, markieren, teilen — mit einem Klick.", "撮って、書いて、共有。ワンクリックで。") }
    static var copiedShort: String { tr("Copied", "Copié", "Copiado", "Kopiert", "コピーしました") }
    static var savedShort: String { tr("Saved", "Enregistré", "Guardado", "Gesichert", "保存しました") }
    static var windowHint: String { tr("Click a window · Space: area", "Clique sur une fenêtre · Espace : zone", "Haz clic en una ventana · Espacio: área", "Fenster anklicken · Leertaste: Bereich", "ウインドウをクリック · スペース: 範囲") }
}
