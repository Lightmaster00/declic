import Foundation

/// Interface language, taken from the system language (Settings › General › Language & Region).
enum Lang: String {
    case en, fr, es, de, ja

    static let current: Lang = {
        for identifier in Locale.preferredLanguages {
            let code = Locale(identifier: identifier).language.languageCode?.identifier
                ?? String(identifier.prefix(2))
            if let lang = Lang(rawValue: code) { return lang }
        }
        return .en
    }()
}

func tr(_ en: String, _ fr: String, _ es: String, _ de: String, _ ja: String) -> String {
    switch Lang.current {
    case .en: return en
    case .fr: return fr
    case .es: return es
    case .de: return de
    case .ja: return ja
    }
}

/// Every interface string.
enum S {
    // MARK: Menu
    static var sectionCapture: String { tr("Capture", "Capture", "Captura", "Aufnahme", "キャプチャ") }
    static var sectionRecord: String { tr("Recording", "Enregistrement", "Grabación", "Video", "収録") }
    static var captureArea: String { tr("Capture Area", "Capturer une zone", "Capturar área", "Bereich aufnehmen", "範囲をキャプチャ") }
    static var captureFullscreen: String { tr("Capture Fullscreen", "Capturer le plein écran", "Capturar pantalla completa", "Vollbild aufnehmen", "画面全体をキャプチャ") }
    static var captureWindow: String { tr("Capture Window", "Capturer une fenêtre", "Capturar ventana", "Fenster aufnehmen", "ウインドウをキャプチャ") }
    static var scrollingCapture: String { tr("Scrolling Capture", "Capture défilante", "Captura con desplazamiento", "Scroll-Aufnahme", "スクロールキャプチャ") }
    static var recordScreen: String { tr("Record Screen…", "Enregistrer l'écran…", "Grabar pantalla…", "Bildschirm aufnehmen…", "画面を収録…") }
    static var stopRecording: String { tr("Stop Recording", "Arrêter l'enregistrement", "Detener grabación", "Aufnahme beenden", "収録を停止") }
    static var openImage: String { tr("Annotate an Image…", "Annoter une image…", "Anotar una imagen…", "Bild kommentieren…", "画像に注釈…") }
    static var openFolder: String { tr("Open Captures Folder", "Ouvrir le dossier des captures", "Abrir carpeta de capturas", "Aufnahmeordner öffnen", "保存先フォルダを開く") }
    static var playSound: String { tr("Capture Sound", "Son de capture", "Sonido de captura", "Aufnahmeton", "キャプチャ音") }
    static var showClicks: String { tr("Show Clicks in Recordings", "Afficher les clics dans les vidéos", "Mostrar clics en grabaciones", "Klicks in Aufnahmen zeigen", "収録でクリックを表示") }
    static var requiresMacOS15: String { tr("Requires macOS 15", "Nécessite macOS 15", "Requiere macOS 15", "Erfordert macOS 15", "macOS 15 が必要です") }
    static var quit: String { tr("Quit Declic", "Quitter Declic", "Salir de Declic", "Declic beenden", "Declic を終了") }
    static var choose: String { tr("Choose", "Choisir", "Elegir", "Auswählen", "選択") }

    // MARK: Recording
    static var modeArea: String { tr("Area", "Zone", "Área", "Bereich", "範囲") }
    static var modeFullscreen: String { tr("Fullscreen", "Plein écran", "Pantalla", "Vollbild", "全画面") }
    static var modeApp: String { tr("App", "Application", "Aplicación", "App", "アプリ") }
    static var video: String { tr("Video", "Vidéo", "Vídeo", "Video", "ビデオ") }
    static var cancel: String { tr("Cancel", "Annuler", "Cancelar", "Abbrechen", "キャンセル") }
    static var stop: String { tr("Stop", "Arrêter", "Detener", "Stopp", "停止") }
    static var converting: String { tr("Converting to GIF…", "Conversion en GIF…", "Convirtiendo a GIF…", "GIF wird erstellt…", "GIFに変換中…") }

    // MARK: Selection
    static var hintRecordArea: String { tr("Drag to choose the area to record · Esc: cancel",
                                           "Glisse pour choisir la zone à enregistrer · Échap : annuler",
                                           "Arrastra para elegir el área a grabar · Esc: cancelar",
                                           "Ziehen, um den Aufnahmebereich zu wählen · Esc: Abbrechen",
                                           "ドラッグで収録範囲を選択 · Esc: キャンセル") }
    static var window: String { tr("Window", "Fenêtre", "Ventana", "Fenster", "ウインドウ") }

    // MARK: Thumbnail / keep
    static var copy: String { tr("Copy", "Copier", "Copiar", "Kopieren", "コピー") }
    static var save: String { tr("Save", "Enregistrer", "Guardar", "Sichern", "保存") }
    static var annotate: String { tr("Annotate", "Annoter", "Anotar", "Kommentieren", "注釈") }
    static var close: String { tr("Close", "Fermer", "Cerrar", "Schließen", "閉じる") }
    static var open: String { tr("Open", "Ouvrir", "Abrir", "Öffnen", "開く") }

    // MARK: Editor
    static var toolSelect: String { tr("Select", "Sélection", "Seleccionar", "Auswahl", "選択") }
    static var toolArrow: String { tr("Arrow", "Flèche", "Flecha", "Pfeil", "矢印") }
    static var toolLine: String { tr("Line", "Ligne", "Línea", "Linie", "線") }
    static var toolRectangle: String { tr("Rectangle", "Rectangle", "Rectángulo", "Rechteck", "四角形") }
    static var toolEllipse: String { tr("Ellipse", "Ellipse", "Elipse", "Ellipse", "楕円") }
    static var toolText: String { tr("Text", "Texte", "Texto", "Text", "テキスト") }
    static var toolHighlight: String { tr("Highlighter", "Surligneur", "Resaltador", "Textmarker", "ハイライト") }
    static var toolPixelate: String { tr("Pixelate", "Pixeliser", "Pixelar", "Verpixeln", "モザイク") }
    static var toolCounter: String { tr("Counter", "Compteur", "Contador", "Zähler", "番号") }
    static var toolCrop: String { tr("Crop", "Recadrer", "Recortar", "Zuschneiden", "切り取り") }
    static var undo: String { tr("Undo", "Annuler", "Deshacer", "Widerrufen", "取り消す") }
    static var redo: String { tr("Redo", "Rétablir", "Rehacer", "Wiederholen", "やり直す") }
    static var saveAs: String { tr("Save As…", "Enregistrer sous…", "Guardar como…", "Sichern unter…", "別名で保存…") }
    static var copied: String { tr("Copied to clipboard", "Copié dans le presse-papiers", "Copiado al portapapeles", "In die Zwischenablage kopiert", "クリップボードにコピーしました") }
    static var textPlaceholder: String { tr("Text", "Texte", "Texto", "Text", "テキスト") }
    static var editorTitle: String { tr("Annotate", "Annoter", "Anotar", "Kommentieren", "注釈") }
    static var strokeWidth: String { tr("Stroke Width", "Épaisseur", "Grosor", "Linienstärke", "線の太さ") }
    static var widthNames: [String] {
        [tr("Thin", "Fin", "Fino", "Dünn", "細"),
         tr("Medium", "Moyen", "Medio", "Mittel", "中"),
         tr("Thick", "Épais", "Grueso", "Dick", "太"),
         tr("Extra Thick", "Très épais", "Muy grueso", "Sehr dick", "極太")]
    }
    static func saved(_ name: String) -> String {
        tr("Saved: \(name)", "Enregistré : \(name)", "Guardado: \(name)", "Gesichert: \(name)", "保存しました: \(name)")
    }
    static func error(_ message: String) -> String {
        tr("Error: \(message)", "Erreur : \(message)", "Error: \(message)", "Fehler: \(message)", "エラー: \(message)")
    }

    // MARK: Scrolling capture
    static var scrollInstruction: String { tr("Scroll slowly", "Fais défiler lentement", "Desplázate despacio", "Langsam scrollen", "ゆっくりスクロール") }
    static var done: String { tr("Done", "Terminer", "Listo", "Fertig", "完了") }

    // MARK: Errors
    static var captureFailed: String { tr("Capture failed", "Capture impossible", "No se pudo capturar", "Aufnahme fehlgeschlagen", "キャプチャできませんでした") }
    static var permissionHelp: String { tr(
        "Make sure Declic is allowed in System Settings › Privacy & Security › Screen & System Audio Recording, then relaunch the app.",
        "Vérifie que Declic est autorisé dans Réglages Système › Confidentialité et sécurité › Enregistrement de l'écran et de l'audio système, puis relance l'app.",
        "Asegúrate de que Declic esté permitido en Ajustes del Sistema › Privacidad y seguridad › Grabación de pantalla y audio del sistema, y vuelve a abrir la app.",
        "Erlaube Declic unter Systemeinstellungen › Datenschutz & Sicherheit › Bildschirm- & Systemaudioaufnahme und starte die App neu.",
        "システム設定 › プライバシーとセキュリティ › 画面収録とシステムオーディオ録音 で Declic を許可し、アプリを再起動してください。") }
    static var openSettings: String { tr("Open Settings", "Ouvrir les réglages", "Abrir Ajustes", "Einstellungen öffnen", "設定を開く") }
    static var ok: String { "OK" }
    static var saveFailed: String { tr("Couldn't save", "Enregistrement impossible", "No se pudo guardar", "Sichern fehlgeschlagen", "保存できませんでした") }
    static var openFailed: String { tr("Couldn't open the image", "Impossible d'ouvrir l'image", "No se pudo abrir la imagen", "Bild konnte nicht geöffnet werden", "画像を開けませんでした") }
    static var recordingFailed: String { tr("Recording failed", "Enregistrement vidéo impossible", "No se pudo grabar", "Aufnahme fehlgeschlagen", "収録できませんでした") }
    static var errNoDisplay: String { tr("No display found.", "Aucun écran trouvé.", "No se encontró ninguna pantalla.", "Kein Bildschirm gefunden.", "ディスプレイが見つかりません。") }
    static var errWriter: String { tr("Couldn't prepare the video file.", "Impossible de préparer le fichier vidéo.", "No se pudo preparar el archivo de vídeo.", "Videodatei konnte nicht vorbereitet werden.", "ビデオファイルを準備できませんでした。") }
    static var errEmpty: String { tr("The recording contains no frames.", "L'enregistrement ne contient aucune image.", "La grabación no contiene imágenes.", "Die Aufnahme enthält keine Bilder.", "収録にフレームがありません。") }
    static var errGIF: String { tr("GIF conversion failed.", "La conversion en GIF a échoué.", "Falló la conversión a GIF.", "GIF-Konvertierung fehlgeschlagen.", "GIFへの変換に失敗しました。") }

    // MARK: Main menu
    static var menuFile: String { tr("File", "Fichier", "Archivo", "Ablage", "ファイル") }
    static var menuEdit: String { tr("Edit", "Édition", "Edición", "Bearbeiten", "編集") }
    static var cut: String { tr("Cut", "Couper", "Cortar", "Ausschneiden", "カット") }
    static var paste: String { tr("Paste", "Coller", "Pegar", "Einsetzen", "ペースト") }
    static var selectAll: String { tr("Select All", "Tout sélectionner", "Seleccionar todo", "Alles auswählen", "すべてを選択") }

    // MARK: File names
    static var screenshotPrefix: String { tr("Screenshot", "Capture d'écran", "Captura de pantalla", "Bildschirmfoto", "スクリーンショット") }
    static var recordingPrefix: String { tr("Screen Recording", "Enregistrement de l'écran", "Grabación de pantalla", "Bildschirmaufnahme", "画面収録") }
    static var at: String { tr("at", "à", "a las", "um", "") }
}
