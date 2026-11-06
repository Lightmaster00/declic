import AppKit
@preconcurrency import ScreenCaptureKit

struct WindowCandidate {
    let window: SCWindow
    /// Frame in global Cocoa coordinates (origin at bottom left).
    let frame: CGRect
    let scale: CGFloat
}

enum CaptureError: LocalizedError {
    case noDisplay
    case writerSetup
    case emptyRecording
    case gifExport

    var errorDescription: String? {
        switch self {
        case .noDisplay: return S.errNoDisplay
        case .writerSetup: return S.errWriter
        case .emptyRecording: return S.errEmpty
        case .gifExport: return S.errGIF
        }
    }
}

/// Hides desktop icons by covering them with the wallpaper.
@MainActor
enum DesktopCover {
    private static var windows: [NSWindow] = []

    static var windowIDs: Set<CGWindowID> { Set(windows.map { CGWindowID($0.windowNumber) }) }

    static func showIfNeeded() async {
        guard Prefs.shared.hideDesktopIcons, windows.isEmpty else { return }
        let level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        for screen in NSScreen.screens {
            guard let url = NSWorkspace.shared.desktopImageURL(for: screen),
                  let image = NSImage(contentsOf: url) else { continue }
            let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.setFrame(screen.frame, display: false)
            window.level = level
            window.ignoresMouseEvents = true
            window.isReleasedWhenClosed = false
            window.hasShadow = false
            window.collectionBehavior = [.canJoinAllSpaces, .stationary]
            let view = NSView(frame: CGRect(origin: .zero, size: screen.frame.size))
            view.wantsLayer = true
            view.layer?.contents = image
            view.layer?.contentsGravity = .resizeAspectFill
            window.contentView = view
            window.orderFrontRegardless()
            windows.append(window)
        }
        try? await Task.sleep(nanoseconds: 150_000_000)
    }

    static func hide() {
        for w in windows { w.orderOut(nil) }
        windows.removeAll()
    }
}

/// ScreenCaptureKit access.
@MainActor
enum Capturer {
    static func content() async throws -> SCShareableContent {
        try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    }

    static func displayID(of screen: NSScreen) -> CGDirectDisplayID {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (screen.deviceDescription[key] as? NSNumber)?.uint32Value ?? CGMainDisplayID()
    }

    static func display(for screen: NSScreen, in content: SCShareableContent) -> SCDisplay? {
        let id = displayID(of: screen)
        return content.displays.first { $0.displayID == id }
    }

    /// Filter for a whole display, without Declic's windows (except the desktop-icon cover).
    static func displayFilter(_ display: SCDisplay, content: SCShareableContent) -> SCContentFilter {
        let pid = ProcessInfo.processInfo.processIdentifier
        let own = content.applications.filter { $0.processID == pid }
        let covers = DesktopCover.windowIDs
        let keep = content.windows.filter { covers.contains($0.windowID) }
        return SCContentFilter(display: display, excludingApplications: own, exceptingWindows: keep)
    }

    static func captureDisplay(_ display: SCDisplay, content: SCShareableContent) async throws -> CGImage {
        let filter = displayFilter(display, content: content)
        let config = SCStreamConfiguration()
        let scale = CGFloat(filter.pointPixelScale)
        config.width = Int(filter.contentRect.width * scale)
        config.height = Int(filter.contentRect.height * scale)
        config.showsCursor = false
        config.captureResolution = .best
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    static func captureScreen(_ screen: NSScreen) async throws -> CGImage {
        let content = try await content()
        guard let display = display(for: screen, in: content) else { throw CaptureError.noDisplay }
        return try await captureDisplay(display, content: content)
    }

    /// Freezes all displays (selection happens on a still image).
    static func snapshotAllScreens() async throws -> [ScreenShot] {
        let content = try await content()
        var shots: [ScreenShot] = []
        for screen in NSScreen.screens {
            guard let display = display(for: screen, in: content) else { continue }
            let image = try await captureDisplay(display, content: content)
            shots.append(ScreenShot(screen: screen, image: image))
        }
        if shots.isEmpty { throw CaptureError.noDisplay }
        return shots
    }

    static func captureWindow(_ window: SCWindow) async throws -> CGImage {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        let scale = CGFloat(filter.pointPixelScale)
        config.width = Int(filter.contentRect.width * scale)
        config.height = Int(filter.contentRect.height * scale)
        config.showsCursor = false
        config.captureResolution = .best
        config.ignoreShadowsSingleWindow = !Prefs.shared.windowShadow
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    /// Visible windows, front to back.
    static func windowCandidates(_ content: SCShareableContent) -> [WindowCandidate] {
        let pid = ProcessInfo.processInfo.processIdentifier
        let info = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]]) ?? []
        let order = info.compactMap { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value }

        var byID: [CGWindowID: SCWindow] = [:]
        for w in content.windows { byID[w.windowID] = w }

        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        var result: [WindowCandidate] = []
        for id in order {
            guard let w = byID[id],
                  w.windowLayer == 0,
                  w.isOnScreen,
                  w.frame.width > 40, w.frame.height > 40,
                  w.owningApplication?.processID != pid else { continue }
            let f = w.frame
            let cocoa = CGRect(x: f.minX, y: primaryHeight - f.maxY, width: f.width, height: f.height)
            let scale = NSScreen.best(for: cocoa).backingScaleFactor
            result.append(WindowCandidate(window: w, frame: cocoa, scale: scale))
        }
        return result
    }

    static func presentError(_ error: Error) {
        NSLog("Declic capture error: \(error)")
        let alert = NSAlert()
        alert.messageText = S.captureFailed
        alert.informativeText = "\(error.localizedDescription)\n\n\(S.permissionHelp)"
        alert.addButton(withTitle: S.openSettings)
        alert.addButton(withTitle: S.ok)
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// Orchestrates screenshots and post-capture actions.
@MainActor
final class CaptureCoordinator {
    static let shared = CaptureCoordinator()

    private var areaSelector: AreaSelector?
    private(set) var busy = false

    func captureFullscreen() {
        guard !busy else { return }
        busy = true
        Task {
            defer {
                DesktopCover.hide()
                self.busy = false
            }
            do {
                await DesktopCover.showIfNeeded()
                let screen = NSScreen.underMouse
                let image = try await Capturer.captureScreen(screen)
                self.deliver(image, scale: screen.backingScaleFactor, origin: screen.frame)
            } catch {
                Capturer.presentError(error)
            }
        }
    }

    /// Area capture: hover = highlighted window (click to capture it),
    /// drag = area. The screen is only frozen when the option is on.
    func captureArea() {
        // Pressing the shortcut again while selecting cancels the selection.
        if busy {
            areaSelector?.cancelSelection()
            return
        }
        busy = true
        Task {
            do {
                await DesktopCover.showIfNeeded()
                let prefs = Prefs.shared
                let content = try await Capturer.content()
                let windows = Capturer.windowCandidates(content)
                let frozen = prefs.freezeScreen
                let shots: [ScreenShot]
                if frozen || prefs.showMagnifier {
                    // Image of each display: shown when frozen, otherwise only used by the magnifier.
                    shots = try await Capturer.snapshotAllScreens().map {
                        ScreenShot(screen: $0.screen, image: $0.image, frozen: frozen)
                    }
                } else {
                    shots = NSScreen.screens.map { ScreenShot(screen: $0, image: nil, frozen: false) }
                }
                if frozen { DesktopCover.hide() }

                self.areaSelector = AreaSelector(shots: shots, windows: windows) { [weak self] selection in
                    guard let self else { return }
                    self.areaSelector = nil
                    switch selection {
                    case nil:
                        DesktopCover.hide()
                        self.busy = false

                    case .window(let candidate):
                        Task {
                            defer {
                                DesktopCover.hide()
                                self.busy = false
                            }
                            do {
                                var image = try await Capturer.captureWindow(candidate.window)
                                image = ImageTools.applyWindowBackground(image, scale: candidate.scale)
                                self.deliver(image, scale: candidate.scale, origin: candidate.frame)
                            } catch {
                                Capturer.presentError(error)
                            }
                        }

                    case .area(let result):
                        Prefs.shared.lastCaptureArea = result.screenRect
                        if let cropped = result.croppedImage() {
                            self.busy = false
                            self.deliver(cropped, scale: result.shot.screen.backingScaleFactor, origin: result.screenRect)
                        } else {
                            // Screen not frozen: capture now, once the overlay is gone.
                            Task {
                                defer {
                                    DesktopCover.hide()
                                    self.busy = false
                                }
                                do {
                                    try await Task.sleep(nanoseconds: 60_000_000)
                                    let full = try await Capturer.captureScreen(result.shot.screen)
                                    if let cropped = result.crop(full) {
                                        self.deliver(cropped, scale: result.shot.screen.backingScaleFactor,
                                                     origin: result.screenRect)
                                    }
                                } catch {
                                    Capturer.presentError(error)
                                }
                            }
                        }
                    }
                }
            } catch {
                DesktopCover.hide()
                self.busy = false
                Capturer.presentError(error)
            }
        }
    }

    /// Captures the same area as the last area capture, without selecting it again.
    /// Falls back to a normal area capture when there is none (or its display is gone).
    func capturePreviousArea() {
        if busy {
            areaSelector?.cancelSelection()
            return
        }
        guard let rect = Prefs.shared.lastCaptureArea else { captureArea(); return }
        let screen = NSScreen.best(for: rect)
        let visible = rect.intersection(screen.frame)
        guard !visible.isNull, visible.width >= 1, visible.height >= 1 else { captureArea(); return }
        busy = true
        Task {
            defer {
                DesktopCover.hide()
                self.busy = false
            }
            do {
                await DesktopCover.showIfNeeded()
                let full = try await Capturer.captureScreen(screen)
                let local = visible.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
                let area = AreaResult(shot: ScreenShot(screen: screen, image: nil, frozen: false), rect: local)
                if let cropped = area.crop(full) {
                    self.deliver(cropped, scale: screen.backingScaleFactor, origin: visible)
                }
            } catch {
                Capturer.presentError(error)
            }
        }
    }

    /// Window capture: pick the window in Declic's window picker.
    func captureWindow() {
        if busy {
            if MissionControlPicker.shared.isPicking { MissionControlPicker.shared.cancel() }
            return
        }
        busy = true
        MissionControlPicker.shared.pick { [weak self] candidate in
            guard let self else { return }
            guard let candidate else { self.busy = false; return }
            Task {
                defer { self.busy = false }
                do {
                    var image = try await Capturer.captureWindow(candidate.window)
                    image = ImageTools.applyWindowBackground(image, scale: candidate.scale)
                    self.deliver(image, scale: candidate.scale, origin: candidate.frame)
                } catch {
                    Capturer.presentError(error)
                }
            }
        }
    }

    /// Endpoint for every image capture: history + the actions chosen in settings.
    func deliver(_ captured: CGImage, scale captureScale: CGFloat, origin: CGRect?) {
        let prefs = Prefs.shared
        var image = captured
        var scale = captureScale
        if prefs.scaleTo1x, scale > 1, let small = ImageTools.downscale(image, by: scale) {
            image = small
            scale = 1
        }

        Sound.shutter()
        HistoryStore.shared.addImage(image, scale: scale)

        if prefs.afterCopy {
            Clipboard.copy(image: image, scale: scale)
            if !prefs.afterQuickAccess { FeedbackHUD.show(S.copied) }
        }
        if prefs.afterSave {
            do {
                try FileUtil.savePNG(image)
                if !prefs.afterQuickAccess { FeedbackHUD.show(S.savedShort) }
            } catch { showError(S.saveFailed, error) }
        }
        if prefs.afterAnnotate { EditorWindowController.open(image: image, scale: scale) }
        if prefs.afterQuickAccess {
            QuickAccessManager.shared.show(.image(image, scale: scale, origin: origin))
        }
    }
}
