import AppKit
import AVFoundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

extension NSScreen {
    /// The display under the mouse pointer.
    static var underMouse: NSScreen {
        let p = NSEvent.mouseLocation
        return screens.first { NSMouseInRect(p, $0.frame, false) } ?? main ?? screens[0]
    }

    /// The display holding most of a rectangle (global Cocoa coordinates).
    static func best(for rect: CGRect) -> NSScreen {
        var best: NSScreen?
        var bestArea: CGFloat = 0
        for screen in screens {
            let i = screen.frame.intersection(rect)
            let area = i.isNull ? 0 : i.width * i.height
            if area > bestArea {
                bestArea = area
                best = screen
            }
        }
        return best ?? underMouse
    }
}

extension NSWindow.Level {
    /// Above the selection overlays (recording control bar…).
    static let aboveOverlay = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
}

enum ImageTools {
    static let sRGB = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    static func encode(_ image: CGImage, format: ImageFormat, quality: Double) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data as CFMutableData, format.utType.identifier as CFString, 1, nil) else {
            return nil
        }
        var props: [String: Any] = [:]
        if format != .png { props[kCGImageDestinationLossyCompressionQuality as String] = quality }
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }

    /// Scales a Retina capture down to 1x.
    static func downscale(_ image: CGImage, by scale: CGFloat) -> CGImage? {
        guard scale > 1 else { return image }
        let w = max(1, Int((CGFloat(image.width) / scale).rounded()))
        let h = max(1, Int((CGFloat(image.height) / scale).rounded()))
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }

    /// Adds a colored margin around a window capture.
    @MainActor
    static func applyWindowBackground(_ image: CGImage, scale: CGFloat) -> CGImage {
        let prefs = Prefs.shared
        let color: NSColor
        switch prefs.windowBackground {
        case .transparent: return image
        case .white: color = .white
        case .light: color = NSColor(srgbRed: 0.91, green: 0.91, blue: 0.93, alpha: 1)
        case .dark: color = NSColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1)
        case .custom: color = prefs.windowColor
        }
        let pad = Int(prefs.windowPadding * max(scale, 1))
        let w = image.width + pad * 2, h = image.height + pad * 2
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
        ctx.setFillColor(color.usingColorSpace(.sRGB)?.cgColor ?? color.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.draw(image, in: CGRect(x: pad, y: pad, width: image.width, height: image.height))
        return ctx.makeImage() ?? image
    }

    /// Downscaled image for display (macOS can't display images taller than 16,384 px).
    static func downscaled(_ image: CGImage, maxPixel: Int) -> CGImage {
        let longest = max(image.width, image.height)
        guard longest > maxPixel else { return image }
        let f = CGFloat(maxPixel) / CGFloat(longest)
        let w = max(1, Int(CGFloat(image.width) * f)), h = max(1, Int(CGFloat(image.height) * f))
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage() ?? image
    }

    /// Lightweight thumbnail of an image or video file.
    static func thumbnail(of url: URL, maxPixel: Int) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    }
}

enum FileUtil {
    static func pngData(_ image: CGImage) -> Data? {
        let rep = NSBitmapImageRep(cgImage: image)
        return rep.representation(using: .png, properties: [:])
    }

    /// "2026-11-06 at 01.05.12" depending on the system language.
    static func timestamp() -> String {
        let now = Date()
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.dateFormat = "yyyy-MM-dd"
        let time = DateFormatter()
        time.locale = Locale(identifier: "en_US_POSIX")
        time.dateFormat = "HH.mm.ss"
        let at = S.at
        return at.isEmpty
            ? "\(day.string(from: now)) \(time.string(from: now))"
            : "\(day.string(from: now)) \(at) \(time.string(from: now))"
    }

    /// Unique temporary folder (one per file, to keep clean names for drag and drop).
    static func newTempFolder() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Declic", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Temporary file in the chosen format (for drag and drop).
    @MainActor
    static func writeTempImage(_ image: CGImage) throws -> URL {
        let prefs = Prefs.shared
        let format = prefs.imageFormat
        guard let data = ImageTools.encode(image, format: format, quality: prefs.jpegQuality) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let url = newTempFolder().appendingPathComponent("\(prefs.screenshotPrefix) \(timestamp()).\(format.ext)")
        try data.write(to: url)
        return url
    }

    /// New free URL in the save folder (the Desktop by default).
    @MainActor
    static func newSaveURL(prefix: String, ext: String) throws -> URL {
        let folder = Prefs.shared.saveFolder
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let base = "\(prefix) \(timestamp())"
        var url = folder.appendingPathComponent("\(base).\(ext)")
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("\(base) (\(n)).\(ext)")
            n += 1
        }
        return url
    }

    /// Saves an image to the save folder, in the format chosen in settings.
    @MainActor
    @discardableResult
    static func savePNG(_ image: CGImage) throws -> URL {
        let prefs = Prefs.shared
        let format = prefs.imageFormat
        guard let data = ImageTools.encode(image, format: format, quality: prefs.jpegQuality) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let url = try newSaveURL(prefix: prefs.screenshotPrefix, ext: format.ext)
        try data.write(to: url)
        return url
    }

    /// Copies a video / GIF to the save folder.
    @MainActor
    @discardableResult
    static func saveVideo(_ url: URL, isGIF: Bool) throws -> URL {
        let dest = try newSaveURL(prefix: S.recordingPrefix, ext: isGIF ? "gif" : "mp4")
        try FileManager.default.copyItem(at: url, to: dest)
        return dest
    }

    static func loadImage(_ url: URL) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    @MainActor
    static func thumbnail(for url: URL, isGIF: Bool) async -> NSImage? {
        if isGIF { return NSImage(contentsOf: url) }
        let gen = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 640, height: 640)
        guard let result = try? await gen.image(at: .zero) else { return nil }
        return NSImage(cgImage: result.image, size: .zero)
    }
}

enum Clipboard {
    static func copy(image: CGImage, scale: CGFloat) {
        let s = max(scale, 1)
        let ns = NSImage(cgImage: image, size: NSSize(width: CGFloat(image.width) / s, height: CGFloat(image.height) / s))
        let item = NSPasteboardItem()
        if let png = FileUtil.pngData(image) { item.setData(png, forType: .png) }
        if let tiff = ns.tiffRepresentation { item.setData(tiff, forType: .tiff) }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([item])
    }

    static func copy(fileURL: URL) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([fileURL as NSURL])
    }
}

@MainActor
enum Sound {
    private static var current: NSSound?

    static func shutter() {
        guard Prefs.shared.playSound else { return }
        let path = "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Screen Capture.aif"
        let sound = NSSound(contentsOfFile: path, byReference: true) ?? NSSound(named: "Tink")
        current = sound
        sound?.play()
    }

    /// Short confirmation sound (copy, save).
    static func success() {
        guard Prefs.shared.playSound else { return }
        let sound = NSSound(named: "Pop")
        sound?.volume = 0.5
        current = sound
        sound?.play()
    }

    static func tick() {
        guard Prefs.shared.playSound else { return }
        let sound = NSSound(named: "Tink")
        current = sound
        sound?.play()
    }
}

/// Floating panel that doesn't activate the app (thumbnails, HUDs, controls).
final class FloatingPanel: NSPanel {
    init(size: CGSize) {
        super.init(contentRect: CGRect(origin: .zero, size: size),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isFloatingPanel = true
        level = .floating
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    // Never key: clicking a thumbnail or a bar doesn't steal focus from the current app.
    override var canBecomeKey: Bool { false }
}

/// NSHostingView that accepts the first click even when the app isn't active.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
func showError(_ title: String, _ error: Error) {
    NSLog("Declic: \(title): \(error)")
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = error.localizedDescription
    NSApp.activate(ignoringOtherApps: true)
    alert.runModal()
}
