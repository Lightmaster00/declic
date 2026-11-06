import AppKit
import Carbon

/// Borderless full-screen window above everything.
/// It's a non-activating panel: the frontmost app stays active,
/// so nothing visibly changes on screen when the selection appears.
final class OverlayWindow: NSPanel {
    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = false
        hidesOnDeactivate = false
        setFrame(screen.frame, display: false)
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    // Never key: the frontmost app's window keeps keyboard focus
    // (otherwise you had to click it again after every capture). Keys go
    // through global shortcuts (Escape, Return, Space).
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Overlay cursor.
///
/// Déclic isn't the active app during a selection (so nothing changes on screen),
/// so macOS normally hands the cursor back to the app underneath: you'd see the crosshair,
/// then the arrow or a text cursor. Déclic is allowed to set the cursor in the background
/// and keeps re-applying it while an overlay is open.
@MainActor
enum OverlayCursor {
    private static var timer: Timer?
    private static var provider: (@MainActor () -> NSCursor)?
    private static var enabledBackground = false

    static func start(_ cursor: @escaping @MainActor () -> NSCursor) {
        allowBackgroundCursor()
        provider = cursor
        cursor().set()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { _ in
            MainActor.assumeIsolated { OverlayCursor.provider?().set() }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    static func stop() {
        timer?.invalidate()
        timer = nil
        provider = nil
        NSCursor.arrow.set()
    }

    /// "SetsCursorInBackground" property of the window server connection
    /// (the same technique screenshot and accessibility tools use).
    private static func allowBackgroundCursor() {
        guard !enabledBackground else { return }
        enabledBackground = true
        typealias DefaultConnection = @convention(c) () -> Int32
        typealias SetProperty = @convention(c) (Int32, Int32, CFString, CFTypeRef) -> Int32
        let handle = UnsafeMutableRawPointer(bitPattern: -2) // RTLD_DEFAULT
        guard let connSym = dlsym(handle, "_CGSDefaultConnection"),
              let setSym = dlsym(handle, "CGSSetConnectionProperty") else { return }
        let connection = unsafeBitCast(connSym, to: DefaultConnection.self)()
        let setProperty = unsafeBitCast(setSym, to: SetProperty.self)
        _ = setProperty(connection, connection, "SetsCursorInBackground" as CFString, kCFBooleanTrue)
    }
}

/// Shared overlay drawing.
enum OverlayDrawing {
    /// Small dark label (size, coordinates, app name).
    @discardableResult
    static func label(_ text: String, at point: CGPoint, in bounds: CGRect,
                      size: CGFloat = 11, centered: Bool = false, icon: NSImage? = nil) -> CGRect {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: size, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.95),
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        let textSize = str.size()
        let iconSize: CGFloat = icon == nil ? 0 : (textSize.height + 2).rounded()
        let padX: CGFloat = 7, padY: CGFloat = 3.5
        var r = CGRect(x: point.x, y: point.y,
                       width: (textSize.width + padX * 2 + (icon == nil ? 0 : iconSize + 5)).rounded(),
                       height: (max(textSize.height, iconSize) + padY * 2).rounded())
        if centered { r.origin.x = (point.x - r.width / 2).rounded() }
        r.origin.x = min(max(r.minX, bounds.minX + 4), bounds.maxX - r.width - 4)
        r.origin.y = min(max(r.minY, bounds.minY + 4), bounds.maxY - r.height - 4)

        let radius = min(5, r.height / 2)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowBlurRadius = 4
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
        shadow.set()
        NSColor(white: 0.06, alpha: 0.72).setFill()
        NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius).fill()
        NSGraphicsContext.restoreGraphicsState()

        var x = r.minX + padX
        if let icon {
            icon.draw(in: CGRect(x: x, y: r.midY - iconSize / 2, width: iconSize, height: iconSize))
            x += iconSize + 5
        }
        str.draw(at: CGPoint(x: x, y: r.midY - textSize.height / 2))
        return r
    }

    /// Magnifier: enlarged pixels around the point, with grid and coordinates.
    static func loupe(image: CGImage, at m: CGPoint, in bounds: CGRect, ctx: CGContext) {
        guard bounds.width > 0 else { return }
        let sx = CGFloat(image.width) / bounds.width
        let sy = CGFloat(image.height) / bounds.height
        let px = (m.x * sx).rounded(.down)
        let py = ((bounds.height - m.y) * sy).rounded(.down)
        let n: CGFloat = 13
        let half = (n - 1) / 2
        let source = CGRect(x: px - half, y: py - half, width: n, height: n)
        let imageBounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        guard source.intersects(imageBounds) else { return }

        let side: CGFloat = 104
        let cell = side / n
        var origin = CGPoint(x: m.x + 18, y: m.y - 18 - side)
        if origin.x + side > bounds.maxX - 6 { origin.x = m.x - 18 - side }
        if origin.y < bounds.minY + 6 { origin.y = m.y + 18 }
        let rect = CGRect(origin: origin, size: CGSize(width: side, height: side))
        let radius: CGFloat = 9
        let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -2), blur: 8, color: NSColor.black.withAlphaComponent(0.4).cgColor)
        ctx.addPath(path)
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.fillPath()
        ctx.restoreGState()

        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        ctx.interpolationQuality = .none
        let visible = source.intersection(imageBounds)
        if let crop = image.cropping(to: visible) {
            let dx = (visible.minX - source.minX) * cell
            let dyTop = (visible.minY - source.minY) * cell
            ctx.draw(crop, in: CGRect(x: rect.minX + dx,
                                      y: rect.maxY - dyTop - visible.height * cell,
                                      width: visible.width * cell,
                                      height: visible.height * cell))
        }
        // Very subtle grid.
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.05).cgColor)
        ctx.setLineWidth(0.5)
        for i in 1..<Int(n) {
            let o = (CGFloat(i) * cell).rounded() + 0.25
            ctx.move(to: CGPoint(x: rect.minX + o, y: rect.minY))
            ctx.addLine(to: CGPoint(x: rect.minX + o, y: rect.maxY))
            ctx.move(to: CGPoint(x: rect.minX, y: rect.minY + o))
            ctx.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + o))
        }
        ctx.strokePath()
        // Pixel central.
        let center = CGRect(x: rect.minX + half * cell, y: rect.minY + half * cell, width: cell, height: cell)
        ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.5).cgColor)
        ctx.setLineWidth(2)
        ctx.stroke(center.insetBy(dx: -0.5, dy: -0.5))
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(1)
        ctx.stroke(center)
        // Coordinates strip.
        let band = CGRect(x: rect.minX, y: rect.minY, width: side, height: 16)
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.55).cgColor)
        ctx.fill(band)
        ctx.restoreGState()

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.9),
        ]
        let coords = NSAttributedString(string: "\(Int(px)), \(Int(py))", attributes: attrs)
        let cs = coords.size()
        coords.draw(at: CGPoint(x: rect.midX - cs.width / 2, y: rect.minY + (16 - cs.height) / 2))

        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.55).cgColor)
        ctx.setLineWidth(1)
        ctx.strokePath()
        ctx.restoreGState()
    }
}

// MARK: - Selection result

struct ScreenShot {
    let screen: NSScreen
    /// Display image (for the magnifier, and shown when the screen is frozen).
    let image: CGImage?
    /// The screen is frozen: the capture is cut from `image`.
    var frozen = true
}

/// Result of an area capture: a drawn area, or a clicked window.
enum AreaSelection {
    case area(AreaResult)
    case window(WindowCandidate)
}

struct AreaResult {
    let shot: ScreenShot
    /// Rectangle in points, origin at bottom left, relative to the display.
    let rect: CGRect
    var viewSize: CGSize { shot.screen.frame.size }

    var isFullScreen: Bool {
        abs(rect.width - viewSize.width) < 1 && abs(rect.height - viewSize.height) < 1
    }

    func croppedImage() -> CGImage? {
        guard shot.frozen, let image = shot.image else { return nil }
        return crop(image)
    }

    /// Cuts the selection out of a full-display image.
    func crop(_ image: CGImage) -> CGImage? {
        let sx = CGFloat(image.width) / viewSize.width
        let sy = CGFloat(image.height) / viewSize.height
        let r = CGRect(x: rect.minX * sx,
                       y: (viewSize.height - rect.maxY) * sy,
                       width: rect.width * sx,
                       height: rect.height * sy).integral
        return image.cropping(to: r)
    }

    /// Rectangle in points, origin at the display's top left (for SCStreamConfiguration.sourceRect).
    var displayRect: CGRect {
        CGRect(x: rect.minX, y: viewSize.height - rect.maxY, width: rect.width, height: rect.height)
    }

    /// Rectangle in global Cocoa coordinates.
    var screenRect: CGRect {
        rect.offsetBy(dx: shot.screen.frame.minX, dy: shot.screen.frame.minY)
    }
}

// MARK: - Selection view

final class AreaSelectionView: NSView {
    enum Mode {
        /// Captures on mouse up.
        case immediate
        /// Editable selection (move, resize), confirmed elsewhere.
        case adjustable
    }

    var mode: Mode = .immediate
    var image: CGImage?
    var showMagnifier = true
    var showCrosshair = true
    var hint: String?

    var onFinish: ((CGRect?) -> Void)?
    /// Windows (local coordinates, front to back): hover = highlight, click = capture.
    var windowRects: [CGRect] = []
    var onWindowClick: ((Int) -> Void)?
    private var hoveredWindow: Int?
    /// Window mode (Space key): hover = highlighted window, click = capture.
    var windowMode = false {
        didSet {
            if let mouse { updateHoveredWindow(mouse) } else { hoveredWindow = nil }
            needsDisplay = true
        }
    }
    var onToggleWindowMode: (() -> Void)?
    var onChange: ((CGRect?) -> Void)?
    var onConfirm: (() -> Void)?

    private(set) var selection: CGRect?
    private var mouse: CGPoint?
    private var dragging = false

    private enum Drag {
        case none
        case new(start: CGPoint)
        case move(offset: CGPoint)
        case resize(handle: Int, original: CGRect, start: CGPoint)
    }
    private var drag: Drag = .none

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func setSelection(_ rect: CGRect?) {
        selection = rect
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner === self { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseMoved, .activeAlways, .cursorUpdate, .mouseEnteredAndExited, .inVisibleRect],
                                       owner: self,
                                       userInfo: nil))
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window {
            let p = window.mouseLocationOutsideOfEventStream
            if bounds.contains(p) {
                mouse = p
                updateHoveredWindow(p)
            }
        }
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
        if mode == .adjustable, let selection, !dragging, canMove(selection) {
            addCursorRect(selection.insetBy(dx: 6, dy: 6), cursor: .openHand)
        }
    }

    override func cursorUpdate(with event: NSEvent) {
        desiredCursor.set()
    }

    private func updateHoveredWindow(_ p: CGPoint) {
        guard mode == .immediate, windowMode else { hoveredWindow = nil; return }
        hoveredWindow = windowRects.firstIndex { $0.contains(p) }
    }

    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        mouse = p
        updateHoveredWindow(p)
        // The app isn't active: set the cursor ourselves.
        desiredCursor.set()
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        mouse = nil
        needsDisplay = true
    }

    /// Cursor wanted at the current mouse position.
    var desiredCursor: NSCursor {
        guard let window else { return .crosshair }
        let p = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        if case .move = drag { return .closedHand }
        if case .resize(let h, _, _) = drag { return Self.resizeCursor(for: h) }
        if mode == .adjustable, !dragging, let h = handle(at: p) { return Self.resizeCursor(for: h) }
        if mode == .adjustable, !dragging, let selection, canMove(selection),
           selection.insetBy(dx: 6, dy: 6).contains(p), handle(at: p) == nil {
            return .openHand
        }
        return .crosshair
    }

    /// A selection covering almost the whole screen doesn't move: a new drag replaces it.
    private func canMove(_ r: CGRect) -> Bool {
        r.width * r.height < bounds.width * bounds.height * 0.85
    }

    // MARK: Handles

    private func handlePoints(_ r: CGRect) -> [CGPoint] {
        [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.midX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
         CGPoint(x: r.maxX, y: r.midY), CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.midX, y: r.maxY),
         CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.minX, y: r.midY)]
    }

    /// Handle under the pointer: the corners, then any point along the edges (not only
    /// the small dots), so resizing is easy.
    /// 0 bas-gauche, 1 bas, 2 bas-droite, 3 droite, 4 haut-droite, 5 haut, 6 haut-gauche, 7 gauche.
    private func handle(at p: CGPoint) -> Int? {
        guard mode == .adjustable, let r = selection, r.width > 0, r.height > 0 else { return nil }
        for i in [0, 2, 4, 6] {
            let h = handlePoints(r)[i]
            if hypot(h.x - p.x, h.y - p.y) <= 12 { return i }
        }
        let edge: CGFloat = 7
        let withinX = p.x > r.minX - edge && p.x < r.maxX + edge
        let withinY = p.y > r.minY - edge && p.y < r.maxY + edge
        if withinX, abs(p.y - r.minY) <= edge { return 1 }
        if withinX, abs(p.y - r.maxY) <= edge { return 5 }
        if withinY, abs(p.x - r.minX) <= edge { return 7 }
        if withinY, abs(p.x - r.maxX) <= edge { return 3 }
        return nil
    }

    /// Resize cursor for a handle (double arrows, like window edges).
    private static func resizeCursor(for handle: Int) -> NSCursor {
        switch handle {
        case 1, 5: return .resizeUpDown
        case 3, 7: return .resizeLeftRight
        case 0, 4: return systemCursor("_windowResizeNorthEastSouthWestCursor") ?? .crosshair
        default: return systemCursor("_windowResizeNorthWestSouthEastCursor") ?? .crosshair
        }
    }

    /// macOS diagonal cursors (the window-corner ones), not public API.
    private static func systemCursor(_ name: String) -> NSCursor? {
        let selector = NSSelectorFromString(name)
        guard NSCursor.responds(to: selector) else { return nil }
        return NSCursor.perform(selector)?.takeUnretainedValue() as? NSCursor
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        dragging = true
        if mode == .adjustable, let selection {
            if let h = handle(at: p) {
                drag = .resize(handle: h, original: selection, start: p)
                return
            }
            if selection.contains(p), canMove(selection) {
                drag = .move(offset: CGPoint(x: p.x - selection.minX, y: p.y - selection.minY))
                NSCursor.closedHand.set()
                return
            }
        }
        drag = .new(start: p)
        selection = CGRect(origin: p, size: .zero)
        if mode == .adjustable { onChange?(nil) }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        var p = convert(event.locationInWindow, from: nil)
        p.x = min(max(p.x, bounds.minX), bounds.maxX)
        p.y = min(max(p.y, bounds.minY), bounds.maxY)
        mouse = p
        switch drag {
        case .none:
            break
        case .new(let s):
            if event.modifierFlags.contains(.shift) {
                let m = max(abs(p.x - s.x), abs(p.y - s.y))
                p = CGPoint(x: s.x + (p.x < s.x ? -m : m), y: s.y + (p.y < s.y ? -m : m))
            }
            selection = Self.rect(s, p)
        case .move(let offset):
            guard let sel = selection else { break }
            var origin = CGPoint(x: p.x - offset.x, y: p.y - offset.y)
            origin.x = min(max(origin.x, bounds.minX), bounds.maxX - sel.width)
            origin.y = min(max(origin.y, bounds.minY), bounds.maxY - sel.height)
            selection = CGRect(origin: origin, size: sel.size).integral
        case .resize(let h, let r, _):
            var minX = r.minX, maxX = r.maxX, minY = r.minY, maxY = r.maxY
            switch h {
            case 0: minX = p.x; minY = p.y
            case 1: minY = p.y
            case 2: maxX = p.x; minY = p.y
            case 3: maxX = p.x
            case 4: maxX = p.x; maxY = p.y
            case 5: maxY = p.y
            case 6: minX = p.x; maxY = p.y
            default: minX = p.x
            }
            selection = Self.rect(CGPoint(x: minX, y: minY), CGPoint(x: maxX, y: maxY))
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        dragging = false
        defer {
            drag = .none
            window?.invalidateCursorRects(for: self)
            needsDisplay = true
        }
        let r = (selection ?? .zero).intersection(bounds)
        let valid = r.width >= 4 && r.height >= 4

        switch mode {
        case .immediate:
            if valid {
                onFinish?(r)
            } else if windowMode, let index = hoveredWindow {
                // Single click on a window: capture that window.
                selection = nil
                onWindowClick?(index)
            } else {
                selection = nil
            }
        case .adjustable:
            if valid {
                selection = r
                onChange?(r)
            } else if case .new = drag {
                // Single click: clear the selection so a new one can be drawn.
                selection = nil
                onChange?(nil)
            }
        }
    }

    override func keyDown(with event: NSEvent) {
        switch Int(event.keyCode) {
        case kVK_Escape:
            onFinish?(nil)
        case kVK_Return, kVK_ANSI_KeypadEnter:
            if mode == .adjustable { onConfirm?() } else { onFinish?(bounds) }
        case kVK_Space:
            if mode == .immediate { onToggleWindowMode?() }
        default:
            super.keyDown(with: event)
        }
    }

    private static func rect(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y)).integral
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let sel = selection.flatMap { $0.width > 0 && $0.height > 0 ? $0 : nil }

        // Invisible veil: enough to receive clicks.
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.004).cgColor)
        ctx.fill(bounds)

        // Capture mode: the screen isn't dimmed; only the hovered window
        // (window mode) is highlighted.
        if mode == .immediate {
            let showWindow = windowMode && sel == nil
            if showWindow, let index = hoveredWindow, index < windowRects.count {
                let r = windowRects[index]
                ctx.setFillColor(NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor)
                ctx.addPath(CGPath(roundedRect: r, cornerWidth: 10, cornerHeight: 10, transform: nil))
                ctx.fillPath()
                ctx.setStrokeColor(NSColor.controlAccentColor.withAlphaComponent(0.9).cgColor)
                ctx.setLineWidth(2)
                ctx.addPath(CGPath(roundedRect: r.insetBy(dx: 1, dy: 1), cornerWidth: 10, cornerHeight: 10, transform: nil))
                ctx.strokePath()
            }
        }

        // In recording mode, the area around the selection is slightly dimmed.
        if mode == .adjustable, let sel {
            let path = CGMutablePath()
            path.addRect(bounds)
            path.addRect(sel)
            ctx.addPath(path)
            ctx.setFillColor(NSColor.black.withAlphaComponent(0.25).cgColor)
            ctx.fillPath(using: .evenOdd)
        }

        if let sel {
            // Selection rectangle: thin border, readable on any background.
            ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.3).cgColor)
            ctx.setLineWidth(1)
            ctx.stroke(sel.insetBy(dx: -1.5, dy: -1.5))
            ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.95).cgColor)
            ctx.stroke(sel.insetBy(dx: -0.5, dy: -0.5))

            if mode == .adjustable && sel.width > 24 && sel.height > 24 {
                for p in handlePoints(sel) {
                    let r = CGRect(x: p.x - 3.5, y: p.y - 3.5, width: 7, height: 7)
                    ctx.setFillColor(NSColor.white.cgColor)
                    ctx.fillEllipse(in: r)
                    ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.3).cgColor)
                    ctx.setLineWidth(0.5)
                    ctx.strokeEllipse(in: r)
                }
            }
        }

        // Thin full-screen guide lines, readable on light or dark backgrounds.
        if showCrosshair, sel == nil || dragging, let m = mouse {
            let x = m.x.rounded() + 0.5, y = m.y.rounded() + 0.5
            ctx.saveGState()
            ctx.setLineWidth(1)
            ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.18).cgColor)
            ctx.move(to: CGPoint(x: bounds.minX, y: y - 1)); ctx.addLine(to: CGPoint(x: bounds.maxX, y: y - 1))
            ctx.move(to: CGPoint(x: x + 1, y: bounds.minY)); ctx.addLine(to: CGPoint(x: x + 1, y: bounds.maxY))
            ctx.strokePath()
            ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.7).cgColor)
            ctx.move(to: CGPoint(x: bounds.minX, y: y)); ctx.addLine(to: CGPoint(x: bounds.maxX, y: y))
            ctx.move(to: CGPoint(x: x, y: bounds.minY)); ctx.addLine(to: CGPoint(x: x, y: bounds.maxY))
            ctx.strokePath()
            ctx.restoreGState()
        }

        if showMagnifier, !windowMode, let image, let m = mouse, mode == .immediate || dragging {
            OverlayDrawing.loupe(image: image, at: m, in: bounds, ctx: ctx)
        }

        // Selection size, next to the cursor.
        if let sel, dragging, let m = mouse {
            let scale = window?.backingScaleFactor ?? 2
            let loupeVisible = showMagnifier && image != nil
            let offset: CGFloat = loupeVisible ? 140 : 18
            OverlayDrawing.label("\(Int(sel.width * scale)) × \(Int(sel.height * scale))",
                                 at: CGPoint(x: m.x + 18, y: m.y - offset), in: bounds, size: 12)
        }
        if let sel, !dragging, mode == .adjustable {
            OverlayDrawing.label("\(Int(sel.width)) × \(Int(sel.height))",
                                 at: CGPoint(x: sel.midX, y: sel.minY - 24), in: bounds, centered: true)
        }

        if mode == .immediate, sel == nil {
            OverlayDrawing.label(windowMode ? S.windowHint : S.areaHint,
                                 at: CGPoint(x: bounds.midX, y: bounds.minY + 36), in: bounds,
                                 size: 12, centered: true)
        } else if let hint, sel == nil {
            OverlayDrawing.label(hint, at: CGPoint(x: bounds.midX, y: bounds.maxY - 54), in: bounds,
                                 size: 12, centered: true)
        }
    }

    /// White text with shadow, bottom right of the crosshair, no background (macOS style).
    private static func drawCoordinates(_ text: String, near m: CGPoint, in bounds: CGRect) {
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.9)
        shadow.shadowBlurRadius = 2
        shadow.shadowOffset = .zero
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.white,
            .shadow: shadow,
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        let size = str.size()
        var p = CGPoint(x: m.x + 14, y: m.y - 12 - size.height)
        if p.x + size.width > bounds.maxX - 4 { p.x = m.x - 14 - size.width }
        if p.y < bounds.minY + 4 { p.y = m.y + 12 }
        str.draw(at: p)
    }
}

// MARK: - Area capture (immediate)

@MainActor
final class AreaSelector {
    private var windows: [OverlayWindow] = []
    private var shots: [ScreenShot] = []
    private var completion: ((AreaSelection?) -> Void)?
    private var escKey: UInt32?
    private var returnKey: UInt32?
    private var spaceKey: UInt32?
    private var views: [AreaSelectionView] = []
    private var windowMode = false
    private let candidates: [WindowCandidate]

    init(shots: [ScreenShot], windows: [WindowCandidate] = [], hint: String? = nil,
         completion: @escaping (AreaSelection?) -> Void) {
        self.shots = shots
        self.candidates = windows
        self.completion = completion
        let prefs = Prefs.shared

        for shot in shots {
            let window = OverlayWindow(screen: shot.screen)
            let container = NSView(frame: CGRect(origin: .zero, size: shot.screen.frame.size))
            container.wantsLayer = true
            if shot.frozen, let image = shot.image {
                container.layer?.contents = image
                container.layer?.contentsGravity = .resize
            }

            let view = AreaSelectionView(frame: container.bounds)
            let origin = shot.screen.frame.origin
            view.windowRects = windows.map { $0.frame.offsetBy(dx: -origin.x, dy: -origin.y) }
            view.onWindowClick = { [weak self] index in self?.finishWindow(index) }
            view.onToggleWindowMode = { [weak self] in self?.toggleWindowMode() }
            views.append(view)
            view.autoresizingMask = [.width, .height]
            view.mode = .immediate
            view.image = shot.image
            view.showMagnifier = prefs.showMagnifier
            view.showCrosshair = prefs.showCrosshair
            view.hint = hint
            view.onFinish = { [weak self] rect in self?.finish(shot: shot, rect: rect) }
            container.addSubview(view)
            window.contentView = container
            self.windows.append(window)

            window.orderFrontRegardless()
        }

        // Escape / Return work even though the app isn't active.
        escKey = HotKeyCenter.shared.register(keyCode: kVK_Escape, modifiers: 0) { [weak self] in
            self?.cancel()
        }
        returnKey = HotKeyCenter.shared.register(keyCode: kVK_Return, modifiers: 0) { [weak self] in
            self?.selectWholeScreenUnderMouse()
        }
        if !windows.isEmpty {
            spaceKey = HotKeyCenter.shared.register(keyCode: kVK_Space, modifiers: 0) { [weak self] in
                self?.toggleWindowMode()
            }
        }
        let overlays = self.windows
        let overlayViews = self.views
        OverlayCursor.start { overlayCursor(windows: overlays, views: overlayViews) }
    }

    private func toggleWindowMode() {
        guard !candidates.isEmpty else { return }
        windowMode.toggle()
        for view in views { view.windowMode = windowMode }
    }

    private func cancel() {
        guard let shot = shots.first else { return }
        finish(shot: shot, rect: nil)
    }

    private func selectWholeScreenUnderMouse() {
        let screen = NSScreen.underMouse
        guard let shot = shots.first(where: { $0.screen == screen }) ?? shots.first else { return }
        finish(shot: shot, rect: CGRect(origin: .zero, size: shot.screen.frame.size))
    }

    private func close() -> ((AreaSelection?) -> Void)? {
        guard let cb = completion else { return nil }
        completion = nil
        HotKeyCenter.shared.unregister(escKey)
        HotKeyCenter.shared.unregister(returnKey)
        HotKeyCenter.shared.unregister(spaceKey)
        for w in windows { w.orderOut(nil) }
        windows.removeAll()
        views.removeAll()
        OverlayCursor.stop()
        return cb
    }

    private func finish(shot: ScreenShot, rect: CGRect?) {
        guard let cb = close() else { return }
        if let rect {
            cb(.area(AreaResult(shot: shot, rect: rect)))
        } else {
            cb(nil)
        }
    }

    private func finishWindow(_ index: Int) {
        guard index < candidates.count, let cb = close() else { return }
        cb(.window(candidates[index]))
    }
}

// MARK: - Recording area (editable)

@MainActor
final class RecordAreaPicker {
    private var windows: [OverlayWindow] = []
    private var views: [(screen: NSScreen, view: AreaSelectionView)] = []
    var onChange: ((AreaResult?) -> Void)?
    var onConfirm: (() -> Void)?
    private(set) var current: AreaResult?

    init(initial: AreaResult?) {
        for screen in NSScreen.screens {
            let window = OverlayWindow(screen: screen)
            let view = AreaSelectionView(frame: CGRect(origin: .zero, size: screen.frame.size))
            view.mode = .adjustable
            view.showMagnifier = false
            view.showCrosshair = Prefs.shared.showCrosshair
            view.hint = S.hintRecordArea
            view.onChange = { [weak self, weak view] rect in
                guard let self, let view else { return }
                self.selectionChanged(on: screen, view: view, rect: rect)
            }
            view.onConfirm = { [weak self] in self?.onConfirm?() }
            window.contentView = view
            windows.append(window)
            views.append((screen, view))
            if let initial, initial.shot.screen == screen {
                view.setSelection(initial.rect)
                current = initial
            }
            window.orderFrontRegardless()
        }
        let overlays = windows
        let allViews = views.map { $0.view }
        OverlayCursor.start { overlayCursor(windows: overlays, views: allViews) }
    }

    private func selectionChanged(on screen: NSScreen, view: AreaSelectionView, rect: CGRect?) {
        // Only one selection at a time, across all displays.
        for entry in views where entry.view !== view && entry.view.selection != nil {
            entry.view.setSelection(nil)
        }
        current = rect.map { AreaResult(shot: ScreenShot(screen: screen, image: nil), rect: $0) }
        onChange?(current)
    }

    /// Clears the selection; returns false if there was none.
    @discardableResult
    func clearSelection() -> Bool {
        guard current != nil else { return false }
        for entry in views { entry.view.setSelection(nil) }
        current = nil
        onChange?(nil)
        return true
    }

    func close() {
        guard !windows.isEmpty else { return }
        for w in windows { w.orderOut(nil) }
        windows.removeAll()
        views.removeAll()
        OverlayCursor.stop()
    }
}

/// Cursor to show: the one from the view under the mouse, or the arrow over
/// another window (the recording bar, for example).
@MainActor
private func overlayCursor(windows: [OverlayWindow], views: [AreaSelectionView]) -> NSCursor {
    let mouse = NSEvent.mouseLocation
    let top = NSWindow.windowNumber(at: mouse, belowWindowWithWindowNumber: 0)
    guard let window = windows.first(where: { $0.windowNumber == top }) else { return .arrow }
    return views.first(where: { $0.window === window })?.desiredCursor ?? .crosshair
}

// MARK: - Window selection

@MainActor
final class WindowSelector {
    private var windows: [OverlayWindow] = []
    private var views: [WindowPickView] = []
    private let candidates: [WindowCandidate]
    private var completion: ((WindowCandidate?) -> Void)?
    private var escKey: UInt32?
    let hint: String
    /// Persistent mode: a click selects without closing the overlay.
    let persistent: Bool
    var onSelect: ((WindowCandidate) -> Void)?
    private(set) var hovered: WindowCandidate?
    private(set) var hoveredIcon: NSImage?
    private(set) var selected: WindowCandidate?

    init(candidates: [WindowCandidate], hint: String, persistent: Bool = false,
         completion: @escaping (WindowCandidate?) -> Void) {
        self.candidates = candidates
        self.hint = hint
        self.persistent = persistent
        self.completion = completion
        NSCursor.crosshair.set()

        for screen in NSScreen.screens {
            let window = OverlayWindow(screen: screen)
            let view = WindowPickView(frame: CGRect(origin: .zero, size: screen.frame.size))
            view.screenOrigin = screen.frame.origin
            view.selector = self
            window.contentView = view
            windows.append(window)
            views.append(view)
            window.orderFrontRegardless()
        }
        if !persistent {
            escKey = HotKeyCenter.shared.register(keyCode: kVK_Escape, modifiers: 0) { [weak self] in
                self?.cancel()
            }
        }
        updateHover()
    }

    func updateHover() {
        let p = NSEvent.mouseLocation
        let new = candidates.first { $0.frame.contains(p) }
        if new?.window.windowID != hovered?.window.windowID {
            hovered = new
            if let pid = new?.window.owningApplication?.processID {
                hoveredIcon = NSRunningApplication(processIdentifier: pid)?.icon
            } else {
                hoveredIcon = nil
            }
            for v in views { v.needsDisplay = true }
        }
    }

    func select() {
        updateHover()
        guard let hovered else { return }
        if persistent {
            selected = hovered
            for v in views { v.needsDisplay = true }
            onSelect?(hovered)
        } else {
            finish(hovered)
        }
    }

    /// Deselects (persistent mode); returns false if nothing was selected.
    @discardableResult
    func clearSelection() -> Bool {
        guard selected != nil else { return false }
        selected = nil
        for v in views { v.needsDisplay = true }
        return true
    }

    func cancel() { finish(nil) }

    func close() {
        completion = nil
        HotKeyCenter.shared.unregister(escKey)
        escKey = nil
        for w in windows { w.orderOut(nil) }
        windows.removeAll()
        views.removeAll()
        NSCursor.arrow.set()
    }

    private func finish(_ candidate: WindowCandidate?) {
        guard let cb = completion else { return }
        close()
        cb(candidate)
    }
}

final class WindowPickView: NSView {
    weak var selector: WindowSelector?
    var screenOrigin: CGPoint = .zero

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner === self { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseMoved, .activeAlways, .inVisibleRect],
                                       owner: self,
                                       userInfo: nil))
    }

    override func mouseMoved(with event: NSEvent) { selector?.updateHover() }
    override func mouseDown(with event: NSEvent) { selector?.select() }

    override func keyDown(with event: NSEvent) {
        if Int(event.keyCode) == kVK_Escape, selector?.persistent == false {
            selector?.cancel()
        } else {
            super.keyDown(with: event)
        }
    }

    private func local(_ c: WindowCandidate) -> CGRect {
        c.frame.offsetBy(dx: -screenOrigin.x, dy: -screenOrigin.y)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext, let selector else { return }
        let selected = selector.selected.map(local)
        let hovered = selector.hovered.map(local)
        let focus = selected ?? hovered
        let radius: CGFloat = 10

        // Veil around the highlighted window (it also receives clicks).
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.28).cgColor)
        let path = CGMutablePath()
        path.addRect(bounds)
        if let focus, focus.intersects(bounds) {
            path.addRoundedRect(in: focus, cornerWidth: radius, cornerHeight: radius)
        }
        ctx.addPath(path)
        ctx.fillPath(using: .evenOdd)

        func outline(_ r: CGRect, width: CGFloat, alpha: CGFloat) {
            guard r.intersects(bounds) else { return }
            ctx.setFillColor(NSColor.controlAccentColor.withAlphaComponent(alpha).cgColor)
            ctx.addPath(CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil))
            ctx.fillPath()
            ctx.setStrokeColor(NSColor.controlAccentColor.cgColor)
            ctx.setLineWidth(width)
            ctx.addPath(CGPath(roundedRect: r.insetBy(dx: width / 2, dy: width / 2),
                               cornerWidth: radius, cornerHeight: radius, transform: nil))
            ctx.strokePath()
        }

        if let selected { outline(selected, width: 3, alpha: 0.1) }
        if let hovered, hovered != selected { outline(hovered, width: 1.5, alpha: 0.06) }

        if let hovered, hovered.intersects(bounds) {
            let name = selector.hovered?.window.owningApplication?.applicationName ?? S.window
            let area = hovered.intersection(bounds)
            OverlayDrawing.label("\(name)  ·  \(selector.hint)",
                                 at: CGPoint(x: area.midX, y: area.midY - 11),
                                 in: bounds, size: 12, centered: true, icon: selector.hoveredIcon)
        }
    }
}
