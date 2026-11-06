import AppKit
import UniformTypeIdentifiers

enum RecordingFormat: String {
    case mp4
    case gif
}

enum ImageFormat: String, CaseIterable, Identifiable {
    case png, jpeg, heic
    var id: String { rawValue }
    var ext: String { rawValue == "jpeg" ? "jpg" : rawValue }
    var utType: UTType {
        switch self {
        case .png: return .png
        case .jpeg: return .jpeg
        case .heic: return .heic
        }
    }
    var title: String { rawValue.uppercased() }
}

enum QuickAccessPosition: String, CaseIterable, Identifiable {
    case bottomLeft, bottomRight
    var id: String { rawValue }
}

enum QuickAccessSize: String, CaseIterable, Identifiable {
    case small, medium, large
    var id: String { rawValue }
    var card: CGSize {
        switch self {
        case .small: return CGSize(width: 204, height: 158)
        case .medium: return CGSize(width: 256, height: 194)
        case .large: return CGSize(width: 320, height: 248)
        }
    }
}

enum WindowBackground: String, CaseIterable, Identifiable {
    case transparent, white, light, dark, custom
    var id: String { rawValue }
}

enum VideoQuality: String, CaseIterable, Identifiable {
    case standard, high
    var id: String { rawValue }
}

enum RecordModeChoice: String {
    case area, fullscreen, window
}

/// Clés UserDefaults (partagées avec les @AppStorage de la fenêtre de réglages).
enum PrefKey {
    static let saveFolder = "saveFolder.v2"
    static let filePrefix = "filePrefix"
    static let playSound = "playSound"

    static let afterQuickAccess = "after.quickAccess"
    static let afterCopy = "after.copy"
    static let afterSave = "after.save"
    static let afterAnnotate = "after.annotate"
    static let afterPin = "after.pin"
    static let recAfterQuickAccess = "rec.after.quickAccess"
    static let recAfterCopy = "rec.after.copy"
    static let recAfterSave = "rec.after.save"

    static let imageFormat = "image.format"
    static let jpegQuality = "image.jpegQuality"
    static let scaleTo1x = "image.scaleTo1x"
    static let freezeScreen = "capture.freeze"
    static let showMagnifier = "capture.magnifier"
    static let showCrosshair = "capture.crosshair"
    static let hideDesktopIcons = "capture.hideIcons"
    static let windowShadow = "window.shadow"
    static let windowBackground = "window.background"
    static let windowPadding = "window.padding"
    static let windowColor = "window.color"

    static let qaPosition = "qa.position"
    static let qaSize = "qa.size"
    static let qaAutoClose = "qa.autoClose"

    static let recFPS = "rec.fps"
    static let recCursor = "rec.cursor"
    static let showClicks = "showClicks"
    static let recQuality = "rec.quality"
    static let recCountdown = "rec.countdown"
    static let recLastMode = "rec.lastMode"
    static let recLastFormat = "rec.lastFormat"
    static let gifFPS = "gif.fps"
    static let gifWidth = "gif.width"

    static let historyEnabled = "history.enabled"
    static let historyDays = "history.days"
    static let autoCheckUpdates = "updates.autoCheck"
    static let skippedVersion = "updates.skippedVersion"
}

/// Lecture des réglages (la fenêtre de réglages écrit directement dans UserDefaults).
@MainActor
final class Prefs {
    static let shared = Prefs()
    private let d = UserDefaults.standard

    init() {
        d.register(defaults: [
            PrefKey.playSound: true,
            PrefKey.afterQuickAccess: true,
            PrefKey.afterCopy: false,
            PrefKey.afterSave: false,
            PrefKey.afterAnnotate: false,
            PrefKey.afterPin: false,
            PrefKey.recAfterQuickAccess: true,
            PrefKey.recAfterCopy: false,
            PrefKey.recAfterSave: false,
            PrefKey.imageFormat: ImageFormat.png.rawValue,
            PrefKey.jpegQuality: 0.9,
            PrefKey.scaleTo1x: false,
            PrefKey.freezeScreen: false,
            PrefKey.showMagnifier: true,
            PrefKey.showCrosshair: false,
            PrefKey.hideDesktopIcons: false,
            PrefKey.windowShadow: true,
            PrefKey.windowBackground: WindowBackground.transparent.rawValue,
            PrefKey.windowPadding: 40.0,
            PrefKey.windowColor: "#5B5BD6",
            PrefKey.qaPosition: QuickAccessPosition.bottomLeft.rawValue,
            PrefKey.qaSize: QuickAccessSize.medium.rawValue,
            PrefKey.qaAutoClose: 0,
            PrefKey.recFPS: 60,
            PrefKey.recCursor: true,
            PrefKey.showClicks: true,
            PrefKey.recQuality: VideoQuality.high.rawValue,
            PrefKey.recCountdown: 0,
            PrefKey.recLastMode: RecordModeChoice.area.rawValue,
            PrefKey.recLastFormat: RecordingFormat.mp4.rawValue,
            PrefKey.gifFPS: 15,
            PrefKey.gifWidth: 960,
            PrefKey.historyEnabled: true,
            PrefKey.historyDays: 30,
            PrefKey.autoCheckUpdates: true,
            PrefKey.filePrefix: "",
        ])
    }

    // MARK: Général

    /// Dossier de sauvegarde : le Bureau par défaut.
    var saveFolder: URL {
        get {
            if let path = d.string(forKey: PrefKey.saveFolder), !path.isEmpty {
                return URL(fileURLWithPath: path, isDirectory: true)
            }
            return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Desktop", isDirectory: true)
        }
        set { d.set(newValue.path, forKey: PrefKey.saveFolder) }
    }

    var screenshotPrefix: String {
        let p = (d.string(forKey: PrefKey.filePrefix) ?? "").trimmingCharacters(in: .whitespaces)
        return p.isEmpty ? S.screenshotPrefix : p
    }

    var autoCheckUpdates: Bool { d.bool(forKey: PrefKey.autoCheckUpdates) }

    var playSound: Bool {
        get { d.bool(forKey: PrefKey.playSound) }
        set { d.set(newValue, forKey: PrefKey.playSound) }
    }

    // MARK: Après la capture

    var afterQuickAccess: Bool { d.bool(forKey: PrefKey.afterQuickAccess) }
    var afterCopy: Bool { d.bool(forKey: PrefKey.afterCopy) }
    var afterSave: Bool { d.bool(forKey: PrefKey.afterSave) }
    var afterAnnotate: Bool { d.bool(forKey: PrefKey.afterAnnotate) }
    var afterPin: Bool { d.bool(forKey: PrefKey.afterPin) }
    var recAfterQuickAccess: Bool { d.bool(forKey: PrefKey.recAfterQuickAccess) }
    var recAfterCopy: Bool { d.bool(forKey: PrefKey.recAfterCopy) }
    var recAfterSave: Bool { d.bool(forKey: PrefKey.recAfterSave) }

    // MARK: Captures

    var imageFormat: ImageFormat { ImageFormat(rawValue: d.string(forKey: PrefKey.imageFormat) ?? "") ?? .png }
    var jpegQuality: Double { d.double(forKey: PrefKey.jpegQuality) }
    var scaleTo1x: Bool { d.bool(forKey: PrefKey.scaleTo1x) }
    var freezeScreen: Bool { d.bool(forKey: PrefKey.freezeScreen) }
    var showMagnifier: Bool { d.bool(forKey: PrefKey.showMagnifier) }
    var showCrosshair: Bool { d.bool(forKey: PrefKey.showCrosshair) }
    var hideDesktopIcons: Bool { d.bool(forKey: PrefKey.hideDesktopIcons) }
    var windowShadow: Bool { d.bool(forKey: PrefKey.windowShadow) }
    var windowBackground: WindowBackground {
        WindowBackground(rawValue: d.string(forKey: PrefKey.windowBackground) ?? "") ?? .transparent
    }
    var windowPadding: CGFloat { CGFloat(d.double(forKey: PrefKey.windowPadding)) }
    var windowColor: NSColor { NSColor(hex: d.string(forKey: PrefKey.windowColor) ?? "") ?? .systemIndigo }

    // MARK: Accès rapide

    var qaPosition: QuickAccessPosition { QuickAccessPosition(rawValue: d.string(forKey: PrefKey.qaPosition) ?? "") ?? .bottomLeft }
    var qaSize: QuickAccessSize { QuickAccessSize(rawValue: d.string(forKey: PrefKey.qaSize) ?? "") ?? .medium }
    var qaAutoClose: Int { d.integer(forKey: PrefKey.qaAutoClose) }

    // MARK: Enregistrement

    var recFPS: Int { max(10, d.integer(forKey: PrefKey.recFPS)) }
    var recCursor: Bool { d.bool(forKey: PrefKey.recCursor) }
    var showClicks: Bool {
        get { d.bool(forKey: PrefKey.showClicks) }
        set { d.set(newValue, forKey: PrefKey.showClicks) }
    }
    var recQuality: VideoQuality { VideoQuality(rawValue: d.string(forKey: PrefKey.recQuality) ?? "") ?? .high }
    var recCountdown: Int { d.integer(forKey: PrefKey.recCountdown) }
    var recLastMode: RecordModeChoice {
        get { RecordModeChoice(rawValue: d.string(forKey: PrefKey.recLastMode) ?? "") ?? .area }
        set { d.set(newValue.rawValue, forKey: PrefKey.recLastMode) }
    }
    var recLastFormat: RecordingFormat {
        get { RecordingFormat(rawValue: d.string(forKey: PrefKey.recLastFormat) ?? "") ?? .mp4 }
        set { d.set(newValue.rawValue, forKey: PrefKey.recLastFormat) }
    }
    var gifFPS: Int { max(5, d.integer(forKey: PrefKey.gifFPS)) }
    var gifWidth: Int { max(320, d.integer(forKey: PrefKey.gifWidth)) }

    // MARK: Historique

    var historyEnabled: Bool { d.bool(forKey: PrefKey.historyEnabled) }
    var historyDays: Int { d.integer(forKey: PrefKey.historyDays) }
}

extension NSColor {
    convenience init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
                  green: CGFloat((v >> 8) & 0xFF) / 255,
                  blue: CGFloat(v & 0xFF) / 255,
                  alpha: 1)
    }

    var hexString: String {
        guard let c = usingColorSpace(.sRGB) else { return "#000000" }
        let r = Int((c.redComponent * 255).rounded())
        let g = Int((c.greenComponent * 255).rounded())
        let b = Int((c.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
