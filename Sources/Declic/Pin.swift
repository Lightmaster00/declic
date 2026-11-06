import AppKit
import SwiftUI

/// Pinned images: floating windows that stay on top until closed.
@MainActor
final class PinManager {
    static let shared = PinManager()
    private var pins: [PinController] = []

    var hasPins: Bool { !pins.isEmpty }

    func pin(image: CGImage, scale: CGFloat, origin: CGRect?) {
        let controller = PinController(image: image, scale: scale, origin: origin)
        controller.onClose = { [weak self] closed in
            self?.pins.removeAll { $0 === closed }
        }
        pins.append(controller)
        controller.show()
    }

    func closeAll() {
        let all = pins
        for pin in all { pin.close() }
        pins.removeAll()
    }
}

final class PinPanel: NSPanel {
    init(frame: CGRect) {
        super.init(contentRect: frame,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        level = .floating
        isFloatingPanel = true
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    override var canBecomeKey: Bool { true }
}

struct PinToolbar: View {
    let onCopy: () -> Void
    let onSave: () -> Void
    let onEdit: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            HUDIconButton(symbol: "doc.on.doc", help: S.copy, background: .clear, action: onCopy)
            HUDIconButton(symbol: "square.and.arrow.down", help: S.save, background: .clear, action: onSave)
            HUDIconButton(symbol: "pencil", help: S.annotate, background: .clear, action: onEdit)
            HUDIconButton(symbol: "xmark", help: S.close, background: Color.white.opacity(0.15), action: onClose)
        }
        .padding(4)
        .hudBackground(cornerRadius: 17)
        .padding(10)
    }
}

/// Pinned image view: drag to move, bottom-right corner to resize,
/// pinch or ⌘ + scroll to zoom, ⌥ + scroll for opacity, Escape to close.
final class PinImageView: NSView {
    var image: CGImage?
    var onHover: ((Bool) -> Void)?
    var onClose: (() -> Void)?
    var onCopy: (() -> Void)?

    private var hovering = false
    private var resizing = false
    private var resizeStart: (mouse: CGPoint, frame: CGRect)?
    private let grip: CGFloat = 18

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner === self { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self,
                                       userInfo: nil))
    }

    override func resetCursorRects() {
        addCursorRect(gripRect, cursor: .crosshair)
    }

    private var gripRect: CGRect {
        CGRect(x: bounds.maxX - grip, y: bounds.minY, width: grip, height: grip)
    }

    override func mouseEntered(with event: NSEvent) {
        hovering = true
        needsDisplay = true
        onHover?(true)
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
        needsDisplay = true
        onHover?(false)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let path = CGPath(roundedRect: bounds, cornerWidth: 8, cornerHeight: 8, transform: nil)
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        if let image {
            ctx.interpolationQuality = .high
            ctx.draw(image, in: bounds)
        }
        ctx.restoreGState()

        ctx.addPath(CGPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), cornerWidth: 8, cornerHeight: 8, transform: nil))
        ctx.setStrokeColor((hovering ? NSColor.controlAccentColor : NSColor.white.withAlphaComponent(0.25)).cgColor)
        ctx.setLineWidth(hovering ? 2 : 1)
        ctx.strokePath()

        if hovering {
            // Resize handle.
            ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.9).cgColor)
            ctx.setShadow(offset: .zero, blur: 2, color: NSColor.black.withAlphaComponent(0.6).cgColor)
            ctx.setLineWidth(1.5)
            ctx.setLineCap(.round)
            for i in 1...3 {
                let o = CGFloat(i) * 4
                ctx.move(to: CGPoint(x: bounds.maxX - 4 - o, y: bounds.minY + 4))
                ctx.addLine(to: CGPoint(x: bounds.maxX - 4, y: bounds.minY + 4 + o))
            }
            ctx.strokePath()
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        window?.makeFirstResponder(self)
        let p = convert(event.locationInWindow, from: nil)
        if gripRect.contains(p), let window {
            resizing = true
            resizeStart = (NSEvent.mouseLocation, window.frame)
        } else {
            resizing = false
            window?.performDrag(with: event)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard resizing, let start = resizeStart, let window, let image else { return }
        let m = NSEvent.mouseLocation
        let aspect = CGFloat(image.width) / CGFloat(image.height)
        let width = max(80, start.frame.width + (m.x - start.mouse.x))
        let height = width / aspect
        // The top-left corner stays put.
        let frame = CGRect(x: start.frame.minX, y: start.frame.maxY - height, width: width, height: height)
        window.setFrame(frame, display: true)
        window.invalidateShadow()
    }

    override func mouseUp(with event: NSEvent) {
        resizing = false
        resizeStart = nil
    }

    override func magnify(with event: NSEvent) {
        zoom(by: 1 + event.magnification)
    }

    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.option), let window {
            let delta = event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 0.005 : 0.05)
            window.alphaValue = min(1, max(0.2, window.alphaValue + delta))
        } else if event.modifierFlags.contains(.command) {
            let delta = event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 0.01 : 0.1)
            zoom(by: 1 + delta)
        } else {
            super.scrollWheel(with: event)
        }
    }

    private func zoom(by factor: CGFloat) {
        guard let window, let image else { return }
        let aspect = CGFloat(image.width) / CGFloat(image.height)
        let width = min(max(80, window.frame.width * factor), 6000)
        let height = width / aspect
        let center = CGPoint(x: window.frame.midX, y: window.frame.midY)
        window.setFrame(CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height), display: true)
        window.invalidateShadow()
    }

    override func keyDown(with event: NSEvent) {
        let cmd = event.modifierFlags.contains(.command)
        switch event.keyCode {
        case 53, 51, 117: onClose?() // escape, delete
        case 13 where cmd: onClose?() // ⌘W
        case 8 where cmd: onCopy?() // ⌘C
        default: super.keyDown(with: event)
        }
    }
}

@MainActor
final class PinController {
    let image: CGImage
    let scale: CGFloat
    var onClose: ((PinController) -> Void)?

    private let panel: PinPanel
    private let imageView: PinImageView
    private var toolbarHost: NSView?

    init(image: CGImage, scale: CGFloat, origin: CGRect?) {
        self.image = image
        self.scale = max(scale, 1)

        var size = CGSize(width: CGFloat(image.width) / self.scale, height: CGFloat(image.height) / self.scale)
        let screen = origin.map { NSScreen.best(for: $0) } ?? NSScreen.underMouse
        let vf = screen.visibleFrame
        let fit = min(1, (vf.width * 0.6) / size.width, (vf.height * 0.6) / size.height)
        size = CGSize(width: (size.width * fit).rounded(), height: (size.height * fit).rounded())

        var frame: CGRect
        if let origin, fit >= 1 {
            frame = CGRect(origin: origin.origin, size: size)
        } else {
            frame = CGRect(x: vf.midX - size.width / 2, y: vf.midY - size.height / 2, width: size.width, height: size.height)
        }
        frame.origin.x = min(max(frame.minX, vf.minX), vf.maxX - frame.width)
        frame.origin.y = min(max(frame.minY, vf.minY), vf.maxY - frame.height)

        panel = PinPanel(frame: frame)
        imageView = PinImageView(frame: CGRect(origin: .zero, size: frame.size))
        imageView.autoresizingMask = [.width, .height]
        imageView.image = image
        panel.contentView = imageView

        imageView.onClose = { [weak self] in self?.close() }
        imageView.onCopy = { [weak self] in self?.copy() }
        imageView.onHover = { [weak self] hovering in self?.setToolbarVisible(hovering) }

        let toolbar = PinToolbar(
            onCopy: { [weak self] in self?.copy() },
            onSave: { [weak self] in self?.save() },
            onEdit: { [weak self] in self?.edit() },
            onClose: { [weak self] in self?.close() }
        )
        let host = FirstMouseHostingView(rootView: toolbar)
        let toolbarSize = host.fittingSize
        host.frame = CGRect(x: imageView.bounds.maxX - toolbarSize.width,
                            y: imageView.bounds.maxY - toolbarSize.height,
                            width: toolbarSize.width, height: toolbarSize.height)
        host.autoresizingMask = [.minXMargin, .minYMargin]
        host.alphaValue = 0
        imageView.addSubview(host)
        toolbarHost = host
    }

    func show() {
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            panel.animator().alphaValue = 1
        }
    }

    private func setToolbarVisible(_ visible: Bool) {
        guard let host = toolbarHost else { return }
        // Hides the bar when the pinned image is too small for it.
        let fits = imageView.bounds.width >= host.frame.width && imageView.bounds.height >= host.frame.height
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            host.animator().alphaValue = visible && fits ? 1 : 0
        }
    }

    private func copy() {
        Clipboard.copy(image: image, scale: scale)
        flashBorder()
    }

    private func save() {
        do {
            try FileUtil.savePNG(image)
            flashBorder()
        } catch {
            showError(S.saveFailed, error)
        }
    }

    private func edit() {
        EditorWindowController.open(image: image, scale: scale)
    }

    private func flashBorder() {
        let panel = self.panel
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.08
            panel.animator().alphaValue = 0.6
        }, completionHandler: {
            MainActor.assumeIsolated {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.15
                    panel.animator().alphaValue = 1
                }
            }
        })
    }

    func close() {
        let panel = self.panel
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            panel.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated { panel.orderOut(nil) }
        })
        onClose?(self)
        onClose = nil
    }
}
