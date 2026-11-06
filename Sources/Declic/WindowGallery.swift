import AppKit
import Carbon
import CoreImage
@preconcurrency import ScreenCaptureKit

/// Window thumbnails, captured in parallel.
enum WindowThumbnails {
    static func capture(_ candidates: [WindowCandidate], maxSide: CGFloat) async -> [CGWindowID: CGImage] {
        await withTaskGroup(of: (CGWindowID, CGImage?).self) { group in
            for candidate in candidates {
                let window = candidate.window
                group.addTask {
                    let filter = SCContentFilter(desktopIndependentWindow: window)
                    let rect = filter.contentRect
                    let pixelScale = CGFloat(filter.pointPixelScale)
                    let fit = min(1, maxSide / max(rect.width * pixelScale, rect.height * pixelScale, 1))
                    let config = SCStreamConfiguration()
                    config.width = max(1, Int(rect.width * pixelScale * fit))
                    config.height = max(1, Int(rect.height * pixelScale * fit))
                    config.showsCursor = false
                    config.ignoreShadowsSingleWindow = true
                    let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                    return (window.windowID, image)
                }
            }
            var result: [CGWindowID: CGImage] = [:]
            for await (id, image) in group {
                if let image { result[id] = image }
            }
            return result
        }
    }
}

/// Declic's Mission Control-style picker: every window spreads out over the wallpaper,
/// you pick one, then everything returns exactly as it was. No app is
/// activated and no Space switches: it's just a layer over the screen.
@MainActor
final class WindowGallery {
    private var window: OverlayWindow?
    private var background: GalleryBackgroundView?
    private var tiles: [GalleryTileView] = []
    private var completion: ((WindowCandidate?) -> Void)?
    private var keys: [UInt32?] = []
    private var hovered: GalleryTileView?
    private var hint: NSTextField?
    private var closing = false
    /// Frontmost app when opened: we always return to it on close.
    private let previousApp = NSWorkspace.shared.frontmostApplication

    init(candidates: [WindowCandidate], title: String, completion: @escaping (WindowCandidate?) -> Void) {
        self.completion = completion
        keys = [
            HotKeyCenter.shared.register(keyCode: kVK_Escape, modifiers: 0) { [weak self] in self?.finish(nil) },
            HotKeyCenter.shared.register(keyCode: kVK_Return, modifiers: 0) { [weak self] in
                guard let self, let tile = self.hovered else { return }
                self.finish(tile)
            },
        ]
        Task {
            let thumbs = await WindowThumbnails.capture(candidates, maxSide: 760)
            guard self.completion != nil else { return }
            self.present(candidates: candidates, thumbnails: thumbs, title: title)
        }
    }

    /// Cancels (like Escape).
    func cancel() { finish(nil) }

    private func present(candidates: [WindowCandidate], thumbnails: [CGWindowID: CGImage], title: String) {
        let screen = NSScreen.underMouse
        let overlay = OverlayWindow(screen: screen)
        overlay.appearance = NSAppearance(named: .darkAqua)
        let content = GalleryBackgroundView(frame: CGRect(origin: .zero, size: screen.frame.size), screen: screen)
        content.onClickOutside = { [weak self] in self?.finish(nil) }
        overlay.contentView = content
        background = content

        let hint = NSTextField(labelWithString: title)
        hint.font = .systemFont(ofSize: 13, weight: .medium)
        hint.textColor = NSColor.white.withAlphaComponent(0.8)
        hint.sizeToFit()
        hint.frame.origin = CGPoint(x: (content.bounds.width - hint.frame.width) / 2, y: content.bounds.height - 44)
        content.addSubview(hint)
        self.hint = hint

        // Layout: proportional sizes, order close to the real positions (top → bottom, left → right).
        let ordered = candidates.enumerated().sorted { a, b in
            let ra = a.element.frame, rb = b.element.frame
            if abs(ra.midY - rb.midY) > 80 { return ra.midY > rb.midY }
            return ra.minX < rb.minX
        }.map { $0.element }
        let area = content.bounds.insetBy(dx: 70, dy: 0)
            .divided(atDistance: 90, from: .maxYEdge).remainder
            .divided(atDistance: 70, from: .minYEdge).remainder
        let targets = Self.layout(ordered.map { $0.frame.size }, in: area)

        for (index, candidate) in ordered.enumerated() {
            let pid = candidate.window.owningApplication?.processID
            let icon = pid.flatMap { NSRunningApplication(processIdentifier: $0)?.icon }
            let appName = candidate.window.owningApplication?.applicationName ?? S.window
            let windowTitle = candidate.window.title.flatMap { $0.isEmpty ? nil : $0 }
            let tile = GalleryTileView(candidate: candidate,
                                       image: thumbnails[candidate.window.windowID],
                                       icon: icon,
                                       title: windowTitle.map { "\(appName) — \($0)" } ?? appName)
            tile.frame = targets[index]
            var start = candidate.frame.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
            if !start.intersects(content.bounds) {
                start = CGRect(x: targets[index].midX - 30, y: targets[index].midY - 20, width: 60, height: 40)
            }
            tile.startFrame = start
            tile.onClick = { [weak self, weak tile] in
                guard let self, let tile else { return }
                self.finish(tile)
            }
            tile.onHover = { [weak self, weak tile] inside in
                guard let self, let tile else { return }
                if inside {
                    if self.hovered !== tile { self.hovered?.highlighted = false }
                    self.hovered = tile
                    tile.highlighted = true
                } else if self.hovered === tile {
                    tile.highlighted = false
                    self.hovered = nil
                }
            }
            content.addSubview(tile)
            tiles.append(tile)
        }

        overlay.orderFrontRegardless()
        window = overlay
        content.layoutSubtreeIfNeeded()

        content.setBackdrop(visible: false, duration: 0)
        content.setBackdrop(visible: true, duration: 0.32)
        hint.alphaValue = 0
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.3
            hint.animator().alphaValue = 1
        }
        for tile in tiles { tile.animate(fromStart: true, duration: 0.4) }
    }

    /// "Justified" grid: every window at the same scale (relative sizes are kept),
    /// arranged in centered rows, like Mission Control.
    static func layout(_ sizes: [CGSize], in area: CGRect) -> [CGRect] {
        guard !sizes.isEmpty else { return [] }
        let gap: CGFloat = 36

        func rows(for scale: CGFloat) -> [[Int]] {
            var result: [[Int]] = [[]]
            var width: CGFloat = 0
            for (i, s) in sizes.enumerated() {
                let w = s.width * scale
                if !result[result.count - 1].isEmpty, width + gap + w > area.width {
                    result.append([])
                    width = 0
                }
                width += (result[result.count - 1].isEmpty ? 0 : gap) + w
                result[result.count - 1].append(i)
            }
            return result
        }

        func height(of rows: [[Int]], scale: CGFloat) -> CGFloat {
            let heights = rows.map { row in row.map { sizes[$0].height * scale }.max() ?? 0 }
            return heights.reduce(0, +) + gap * CGFloat(max(0, rows.count - 1))
        }

        // Largest scale (≤ 0.8) that fits everything.
        var lo: CGFloat = 0.02, hi: CGFloat = 0.8
        for _ in 0..<24 {
            let mid = (lo + hi) / 2
            let r = rows(for: mid)
            let fitsWidth = r.allSatisfy { row in
                row.map { sizes[$0].width * mid }.reduce(0, +) + gap * CGFloat(max(0, row.count - 1)) <= area.width
            }
            if fitsWidth && height(of: r, scale: mid) <= area.height { lo = mid } else { hi = mid }
        }
        let scale = lo
        let layoutRows = rows(for: scale)
        let totalHeight = height(of: layoutRows, scale: scale)

        var frames = [CGRect](repeating: .zero, count: sizes.count)
        var y = area.midY + totalHeight / 2
        for row in layoutRows {
            let rowHeight = row.map { sizes[$0].height * scale }.max() ?? 0
            let rowWidth = row.map { sizes[$0].width * scale }.reduce(0, +) + gap * CGFloat(max(0, row.count - 1))
            var x = area.midX - rowWidth / 2
            for i in row {
                let w = (sizes[i].width * scale).rounded()
                let h = (sizes[i].height * scale).rounded()
                frames[i] = CGRect(x: x.rounded(), y: (y - rowHeight / 2 - h / 2).rounded(), width: w, height: h)
                x += w + gap
            }
            y -= rowHeight + gap
        }
        return frames
    }

    private func finish(_ tile: GalleryTileView?) {
        guard !closing, let cb = completion else { return }
        closing = true
        completion = nil
        for key in keys { HotKeyCenter.shared.unregister(key) }
        keys = []
        let chosen = tile?.candidate

        // Direct return: the whole gallery fades out at once, leaving
        // the original screen as it was (without flying every window back).
        guard let overlay = window else {
            restorePreviousApp()
            cb(chosen)
            return
        }
        tile?.highlighted = true
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            overlay.animator().alphaValue = 0
        }, completionHandler: nil)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 240_000_000)
            overlay.orderOut(nil)
            self.window = nil
            self.tiles = []
            self.background = nil
            self.hint = nil
            NSCursor.arrow.set()
            self.restorePreviousApp()
            cb(chosen)
        }
    }

    private func restorePreviousApp() {
        guard let previousApp, NSWorkspace.shared.frontmostApplication != previousApp else { return }
        previousApp.activate()
    }
}

/// Dimmed, blurred wallpaper, like Mission Control.
final class GalleryBackgroundView: NSView {
    var onClickOutside: (() -> Void)?
    private let wallpaper = CALayer()
    private let dim = CALayer()

    init(frame: NSRect, screen: NSScreen) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        wallpaper.frame = bounds
        wallpaper.contentsGravity = .resizeAspectFill
        wallpaper.contents = Self.blurredWallpaper(for: screen)
        layer?.addSublayer(wallpaper)

        dim.frame = bounds
        dim.backgroundColor = NSColor.black.withAlphaComponent(0.22).cgColor
        layer?.addSublayer(dim)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    /// Wallpaper downscaled then blurred (fast, and soft once enlarged).
    private static func blurredWallpaper(for screen: NSScreen) -> CGImage? {
        guard let url = NSWorkspace.shared.desktopImageURL(for: screen),
              let thumb = ImageTools.thumbnail(of: url, maxPixel: 640) else { return nil }
        let input = CIImage(cgImage: thumb)
        guard let filter = CIFilter(name: "CIGaussianBlur") else { return thumb }
        filter.setValue(input.clampedToExtent(), forKey: kCIInputImageKey)
        filter.setValue(10, forKey: kCIInputRadiusKey)
        guard let output = filter.outputImage?.cropped(to: input.extent),
              let blurred = CIContext().createCGImage(output, from: input.extent) else { return thumb }
        return blurred
    }

    /// Fades the backdrop (wallpaper + veil) without touching the tiles.
    func setBackdrop(visible: Bool, duration: CFTimeInterval) {
        let target: Float = visible ? 1 : 0
        for layer in [wallpaper, dim] {
            if duration > 0 {
                let animation = CABasicAnimation(keyPath: "opacity")
                animation.fromValue = layer.presentation()?.opacity ?? layer.opacity
                animation.toValue = target
                animation.duration = duration
                animation.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0, 0.2, 1)
                layer.add(animation, forKey: "fade")
            }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.opacity = target
            CATransaction.commit()
        }
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        wallpaper.frame = bounds
        dim.frame = bounds
        CATransaction.commit()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onClickOutside?() }
}

/// A window's tile in the gallery.
final class GalleryTileView: NSView {
    let candidate: WindowCandidate
    var onClick: (() -> Void)?
    var onHover: ((Bool) -> Void)?
    var startFrame: CGRect = .zero

    private let shadowLayer = CALayer()
    private let imageLayer = CALayer()
    private let highlightLayer = CALayer()
    private let labelBox = NSView()
    private let iconView = NSImageView()
    private let label: NSTextField

    var highlighted = false {
        didSet {
            guard highlighted != oldValue else { return }
            highlightLayer.opacity = highlighted ? 1 : 0
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                labelBox.animator().alphaValue = highlighted ? 1 : 0
            }
        }
    }

    init(candidate: WindowCandidate, image: CGImage?, icon: NSImage?, title: String) {
        self.candidate = candidate
        label = NSTextField(labelWithString: title)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = false

        shadowLayer.shadowColor = NSColor.black.cgColor
        shadowLayer.shadowOpacity = 0.5
        shadowLayer.shadowRadius = 18
        shadowLayer.shadowOffset = CGSize(width: 0, height: -8)
        layer?.addSublayer(shadowLayer)

        imageLayer.cornerRadius = 10
        imageLayer.cornerCurve = .continuous
        imageLayer.masksToBounds = true
        if let image {
            imageLayer.contents = image
            imageLayer.contentsGravity = .resize
        } else {
            imageLayer.backgroundColor = NSColor(white: 0.18, alpha: 1).cgColor
            imageLayer.contents = icon
            imageLayer.contentsGravity = .center
        }
        layer?.addSublayer(imageLayer)

        highlightLayer.cornerRadius = 12
        highlightLayer.cornerCurve = .continuous
        highlightLayer.borderWidth = 4
        highlightLayer.borderColor = NSColor.controlAccentColor.cgColor
        highlightLayer.opacity = 0
        layer?.addSublayer(highlightLayer)

        labelBox.wantsLayer = true
        labelBox.layer?.cornerRadius = 8
        labelBox.layer?.cornerCurve = .continuous
        labelBox.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.6).cgColor
        labelBox.alphaValue = 0
        addSubview(labelBox)

        iconView.image = icon
        iconView.imageScaling = .scaleProportionallyUpOrDown
        labelBox.addSubview(iconView)

        label.font = .systemFont(ofSize: 12.5, weight: .semibold)
        label.textColor = .white
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        labelBox.addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.frame = bounds
        shadowLayer.frame = bounds
        shadowLayer.shadowPath = CGPath(roundedRect: CGRect(origin: .zero, size: bounds.size),
                                        cornerWidth: 10, cornerHeight: 10, transform: nil)
        highlightLayer.frame = bounds.insetBy(dx: -5, dy: -5)
        CATransaction.commit()

        // App name under the window (shown on hover).
        let iconSize: CGFloat = 18
        let maxText = max(60, bounds.width + 80)
        let textWidth = min(label.intrinsicContentSize.width, maxText)
        let boxWidth = iconSize + 8 + textWidth + 20
        labelBox.frame = CGRect(x: (bounds.width - boxWidth) / 2, y: -36, width: boxWidth, height: 28)
        iconView.frame = CGRect(x: 10, y: 5, width: iconSize, height: iconSize)
        label.frame = CGRect(x: 10 + iconSize + 8, y: 6, width: textWidth, height: 16)
    }

    /// Transform that puts the tile back over the real window.
    private func startTransform() -> CATransform3D {
        guard let layer else { return CATransform3DIdentity }
        let f = frame
        let start = startFrame
        let sx = start.width / max(f.width, 1)
        let sy = start.height / max(f.height, 1)
        let ax = layer.anchorPoint.x * f.width
        let ay = layer.anchorPoint.y * f.height
        let tx = (start.minX - f.minX) - ax * (1 - sx)
        let ty = (start.minY - f.minY) - ay * (1 - sy)
        return CATransform3DConcat(CATransform3DMakeScale(sx, sy, 1), CATransform3DMakeTranslation(tx, ty, 0))
    }

    /// `fromStart`: from the real window to the grid; otherwise back to the real window.
    func animate(fromStart: Bool, duration: CFTimeInterval) {
        guard let layer else { return }
        let start = startTransform()
        let animation = CABasicAnimation(keyPath: "transform")
        animation.fromValue = NSValue(caTransform3D: fromStart ? start : CATransform3DIdentity)
        animation.toValue = NSValue(caTransform3D: fromStart ? CATransform3DIdentity : start)
        animation.duration = duration
        // Out: quick start then ease; back: ease in and out.
        animation.timingFunction = fromStart
            ? CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
            : CAMediaTimingFunction(controlPoints: 0.4, 0, 0.2, 1)
        if !fromStart {
            animation.fillMode = .forwards
            animation.isRemovedOnCompletion = false
        }
        layer.add(animation, forKey: "expose")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas where area.owner === self { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onClick?() }
}
