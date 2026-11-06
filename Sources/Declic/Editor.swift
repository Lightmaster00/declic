import AppKit
import Combine
import SwiftUI

// MARK: - Canvas

final class EditorCanvasView: NSView, NSTextFieldDelegate {
    let state: EditorState

    private enum DragMode {
        case none
        case drawing
        case moving(id: UUID, last: CGPoint)
        case cropping(start: CGPoint)
    }

    private var dragMode: DragMode = .none
    private var panning: CGPoint?
    private var spaceDown = false
    private var movedOnce = false
    private var textField: NSTextField?
    private var textOrigin: CGPoint = .zero
    private var cancellable: AnyCancellable?

    init(state: EditorState) {
        self.state = state
        super.init(frame: .zero)
        cancellable = state.objectWillChange.sink { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.needsDisplay = true
                self.window?.invalidateCursorRects(for: self)
            }
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: Geometry

    /// Scale (points per image pixel) when the image fits the window.
    private var fitScale: CGFloat {
        let size = state.imageSize
        let avail = bounds.insetBy(dx: 36, dy: 36)
        guard size.width > 0, size.height > 0, avail.width > 0, avail.height > 0 else { return 1 }
        return min(avail.width / size.width, avail.height / size.height, 1 / state.pixelScale)
    }

    private static let maxZoomPercent: CGFloat = 1600

    private var imageRect: CGRect {
        let size = state.imageSize
        guard size.width > 0, size.height > 0, bounds.width > 0 else { return .zero }
        let s = fitScale * state.zoom
        let w = size.width * s, h = size.height * s
        let pan = clampedPan(state.pan, width: w, height: h)
        return CGRect(x: (bounds.midX - w / 2 + pan.x).rounded(), y: (bounds.midY - h / 2 + pan.y).rounded(),
                      width: w, height: h)
    }

    /// The image can't leave the view: no offset when it fits, clamped otherwise.
    private func clampedPan(_ p: CGPoint, width w: CGFloat, height h: CGFloat) -> CGPoint {
        let mx = max(0, (w - bounds.width) / 2 + 36)
        let my = max(0, (h - bounds.height) / 2 + 36)
        return CGPoint(x: min(max(p.x, -mx), mx), y: min(max(p.y, -my), my))
    }

    // MARK: Zoom

    /// Zooms while keeping `anchor` (view coordinates) in place.
    func setZoom(_ zoom: CGFloat, anchor: CGPoint? = nil) {
        let base = fitScale
        let maxZoom = Self.maxZoomPercent / 100 / state.pixelScale / base
        let z = min(max(zoom, 0.25), max(1, maxZoom))
        let a = anchor ?? CGPoint(x: bounds.midX, y: bounds.midY)
        let ip = toImage(a)
        let size = state.imageSize
        let s = base * z
        let w = size.width * s, h = size.height * s
        // New center so that ip stays under the anchor.
        let origin = CGPoint(x: a.x - ip.x * s, y: a.y - ip.y * s)
        let pan = CGPoint(x: origin.x + w / 2 - bounds.midX, y: origin.y + h / 2 - bounds.midY)
        state.zoom = z
        state.pan = clampedPan(pan, width: w, height: h)
        updateZoomPercent()
    }

    func zoomIn() { setZoom(state.zoom * 1.25) }
    func zoomOut() { setZoom(state.zoom / 1.25) }
    func zoomToFit() {
        state.zoom = 1
        state.pan = .zero
        updateZoomPercent()
    }
    /// Actual size (1 image pixel = 1 screen pixel).
    func zoomActualSize() {
        let screenScale = window?.backingScaleFactor ?? state.pixelScale
        setZoom(1 / screenScale / fitScale)
    }

    func updateZoomPercent() {
        let percent = Int((fitScale * state.zoom * state.pixelScale * 100).rounded())
        if state.zoomPercent != percent { state.zoomPercent = percent }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        Task { @MainActor [weak self] in self?.updateZoomPercent() }
    }

    /// Trackpad pinch.
    override func magnify(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        setZoom(state.zoom * (1 + event.magnification), anchor: p)
    }

    /// Two-finger double tap: toggles fit / zoomed in.
    override func smartMagnify(with event: NSEvent) {
        if abs(state.zoom - 1) > 0.01 {
            zoomToFit()
        } else {
            let p = convert(event.locationInWindow, from: nil)
            setZoom(max(2, 1 / max(fitScale * state.pixelScale, 0.01)), anchor: p)
        }
    }

    /// Scroll wheel: ⌘ or ⌥ + scroll zooms; otherwise a zoomed image pans.
    override func scrollWheel(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.option) {
            let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 8
            setZoom(state.zoom * exp(delta * 0.01), anchor: p)
            return
        }
        let r = imageRect
        guard r.width > bounds.width - 72 || r.height > bounds.height - 72 else { return }
        let f: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 10
        let pan = CGPoint(x: state.pan.x + event.scrollingDeltaX * f, y: state.pan.y + event.scrollingDeltaY * f)
        state.pan = clampedPan(pan, width: r.width, height: r.height)
    }

    private var viewScale: CGFloat {
        let size = state.imageSize
        return size.width > 0 ? imageRect.width / size.width : 1
    }

    private func toImage(_ p: CGPoint) -> CGPoint {
        let r = imageRect, s = viewScale
        return CGPoint(x: (p.x - r.minX) / s, y: (p.y - r.minY) / s)
    }

    private func toView(_ p: CGPoint) -> CGPoint {
        let r = imageRect, s = viewScale
        return CGPoint(x: r.minX + p.x * s, y: r.minY + p.y * s)
    }

    override func resetCursorRects() {
        addCursorRect(imageRect, cursor: state.tool == .select ? .arrow : .crosshair)
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // Dark background with a subtle dot pattern.
        ctx.setFillColor(NSColor(calibratedWhite: 0.11, alpha: 1).cgColor)
        ctx.fill(bounds)
        ctx.setFillColor(NSColor(calibratedWhite: 1, alpha: 0.06).cgColor)
        let spacing: CGFloat = 18
        var y = dirtyRect.minY - dirtyRect.minY.truncatingRemainder(dividingBy: spacing)
        while y < dirtyRect.maxY {
            var x = dirtyRect.minX - dirtyRect.minX.truncatingRemainder(dividingBy: spacing)
            while x < dirtyRect.maxX {
                ctx.fill(CGRect(x: x, y: y, width: 1.5, height: 1.5))
                x += spacing
            }
            y += spacing
        }

        let r = imageRect
        guard r.width > 0 else { return }

        // Drop shadow under the image.
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: 6), blur: 24, color: NSColor.black.withAlphaComponent(0.55).cgColor)
        ctx.setFillColor(NSColor(calibratedWhite: 0.2, alpha: 1).cgColor)
        ctx.fill(r)
        ctx.restoreGState()

        ctx.saveGState()
        ctx.clip(to: r)
        ctx.translateBy(x: r.minX, y: r.minY)
        ctx.scaleBy(x: viewScale, y: viewScale)
        ctx.interpolationQuality = .high
        AnnotationRenderer.draw(state: state, in: ctx, includeDraft: true, showSelection: state.tool == .select)
        ctx.restoreGState()

        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.08).cgColor)
        ctx.setLineWidth(1)
        ctx.stroke(r.insetBy(dx: -0.5, dy: -0.5))

        if let crop = state.cropRect {
            let o = toView(crop.origin)
            let vr = CGRect(x: o.x, y: o.y, width: crop.width * viewScale, height: crop.height * viewScale)
            let path = CGMutablePath()
            path.addRect(r)
            path.addRect(vr)
            ctx.setFillColor(NSColor.black.withAlphaComponent(0.55).cgColor)
            ctx.addPath(path)
            ctx.fillPath(using: .evenOdd)
            ctx.setStrokeColor(NSColor.white.cgColor)
            ctx.setLineWidth(1)
            ctx.stroke(vr)
            // Rule-of-thirds grid.
            ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.35).cgColor)
            for i in 1...2 {
                let fx = vr.minX + vr.width * CGFloat(i) / 3
                let fy = vr.minY + vr.height * CGFloat(i) / 3
                ctx.move(to: CGPoint(x: fx, y: vr.minY)); ctx.addLine(to: CGPoint(x: fx, y: vr.maxY))
                ctx.move(to: CGPoint(x: vr.minX, y: fy)); ctx.addLine(to: CGPoint(x: vr.maxX, y: fy))
            }
            ctx.strokePath()
        }
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        commitText()
        window?.makeFirstResponder(self)
        // Space + drag (or middle click): pan the zoomed image.
        if spaceDown {
            panning = convert(event.locationInWindow, from: nil)
            NSCursor.closedHand.set()
            return
        }
        let p = toImage(convert(event.locationInWindow, from: nil))
        movedOnce = false

        switch state.tool {
        case .select:
            if let hit = hitAnnotation(at: p) {
                state.selectedID = hit.id
                dragMode = .moving(id: hit.id, last: p)
            } else {
                state.selectedID = nil
                dragMode = .none
            }
        case .text:
            beginText(at: p)
            dragMode = .none
        case .counter:
            state.add(state.makeAnnotation(.counter(state.takeCounterValue()), at: p))
            dragMode = .none
        case .crop:
            state.cropRect = CGRect(origin: p, size: .zero)
            dragMode = .cropping(start: p)
        case .arrow, .line, .rectangle, .ellipse, .highlight, .pixelate:
            state.draft = state.makeAnnotation(kind(for: state.tool), at: p)
            dragMode = .drawing
        }
    }

    override func mouseDragged(with event: NSEvent) {
        if let last = panning {
            let v = convert(event.locationInWindow, from: nil)
            let r = imageRect
            state.pan = clampedPan(CGPoint(x: state.pan.x + v.x - last.x, y: state.pan.y + v.y - last.y),
                                   width: r.width, height: r.height)
            panning = v
            return
        }
        let p = toImage(convert(event.locationInWindow, from: nil))
        switch dragMode {
        case .drawing:
            guard var d = state.draft else { return }
            d.end = event.modifierFlags.contains(.shift) ? constrained(from: d.start, to: p) : p
            state.draft = d
        case .moving(let id, let last):
            if !movedOnce {
                state.registerUndo()
                movedOnce = true
            }
            state.moveAnnotation(id, dx: p.x - last.x, dy: p.y - last.y)
            dragMode = .moving(id: id, last: p)
        case .cropping(let start):
            let r = CGRect(x: min(start.x, p.x), y: min(start.y, p.y),
                           width: abs(p.x - start.x), height: abs(p.y - start.y))
            state.cropRect = r.intersection(state.imageBounds)
        case .none:
            break
        }
    }

    override func otherMouseDown(with event: NSEvent) {
        panning = convert(event.locationInWindow, from: nil)
    }

    override func otherMouseDragged(with event: NSEvent) { mouseDragged(with: event) }

    override func otherMouseUp(with event: NSEvent) { panning = nil }

    override func mouseUp(with event: NSEvent) {
        if panning != nil {
            panning = nil
            (spaceDown ? NSCursor.openHand : NSCursor.arrow).set()
            return
        }
        switch dragMode {
        case .drawing:
            if let d = state.draft {
                state.draft = nil
                if hypot(d.end.x - d.start.x, d.end.y - d.start.y) > 3 { state.add(d) }
            }
        case .cropping:
            if let r = state.cropRect, r.width > 4, r.height > 4 { state.applyCrop(r) }
            state.cropRect = nil
        default:
            break
        }
        dragMode = .none
        movedOnce = false
    }

    private func kind(for tool: EditorTool) -> AnnotationKind {
        switch tool {
        case .arrow: return .arrow
        case .line: return .line
        case .rectangle: return .rectangle
        case .ellipse: return .ellipse
        case .highlight: return .highlight
        default: return .pixelate
        }
    }

    /// Shift: 45° angles for lines, squares/circles for shapes.
    private func constrained(from s: CGPoint, to p: CGPoint) -> CGPoint {
        let dx = p.x - s.x, dy = p.y - s.y
        switch state.tool {
        case .line, .arrow:
            let step = CGFloat.pi / 4
            let angle = (atan2(dy, dx) / step).rounded() * step
            let length = hypot(dx, dy)
            return CGPoint(x: s.x + cos(angle) * length, y: s.y + sin(angle) * length)
        default:
            let m = max(abs(dx), abs(dy))
            return CGPoint(x: s.x + (dx < 0 ? -m : m), y: s.y + (dy < 0 ? -m : m))
        }
    }

    private func hitAnnotation(at p: CGPoint) -> Annotation? {
        let tolerance = 6 * state.pixelScale
        for a in state.annotations.reversed() {
            switch a.kind {
            case .line, .arrow:
                if distance(from: p, toSegment: a.start, a.end) <= a.width / 2 + tolerance { return a }
            default:
                let b = AnnotationRenderer.bounds(of: a, scale: state.pixelScale)
                if b.insetBy(dx: -tolerance, dy: -tolerance).contains(p) { return a }
            }
        }
        return nil
    }

    private func distance(from p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let len2 = dx * dx + dy * dy
        guard len2 > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }

    // MARK: Text

    private func beginText(at p: CGPoint) {
        let fontSize = AnnotationRenderer.fontSize(width: state.strokeWidth, scale: state.pixelScale) * viewScale
        let vp = toView(p)
        let field = NSTextField(frame: CGRect(x: vp.x, y: vp.y, width: 80, height: fontSize * 1.4))
        field.font = NSFont.systemFont(ofSize: fontSize, weight: .bold)
        field.textColor = state.color
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.placeholderString = S.textPlaceholder
        field.delegate = self
        addSubview(field)
        window?.makeFirstResponder(field)
        textField = field
        textOrigin = p
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let field = textField else { return }
        let height = field.frame.height
        field.sizeToFit()
        field.setFrameSize(CGSize(width: max(80, field.frame.width + 20), height: height))
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        commitText()
    }

    private func commitText() {
        guard let field = textField else { return }
        textField = nil
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        field.removeFromSuperview()
        if !text.isEmpty {
            state.add(state.makeAnnotation(.text(text), at: textOrigin))
        }
        window?.makeFirstResponder(self)
    }

    // MARK: Keyboard & menus

    override func keyUp(with event: NSEvent) {
        if event.keyCode == 49 {
            spaceDown = false
            window?.invalidateCursorRects(for: self)
            NSCursor.arrow.set()
        } else {
            super.keyUp(with: event)
        }
    }

    override func keyDown(with event: NSEvent) {
        // ⌘+ / ⌘- / ⌘0 (fit) / ⌘1 (actual size).
        if event.modifierFlags.intersection([.command, .control, .option]) == .command,
           let key = event.charactersIgnoringModifiers {
            switch key {
            case "=", "+": zoomIn(); return
            case "-": zoomOut(); return
            case "0": zoomToFit(); return
            case "1": zoomActualSize(); return
            default: break
            }
        }
        if event.keyCode == 49 { // space: hand to pan
            if !spaceDown {
                spaceDown = true
                NSCursor.openHand.set()
            }
            return
        }
        switch event.keyCode {
        case 51, 117: // backspace / delete
            state.deleteSelected()
        case 53: // escape
            state.selectedID = nil
            state.cropRect = nil
        default:
            let mods = event.modifierFlags.intersection([.command, .control, .option])
            if mods.isEmpty, let key = event.charactersIgnoringModifiers?.lowercased(),
               let tool = EditorTool.forKey(key) {
                state.tool = tool
            } else {
                super.keyDown(with: event)
            }
        }
    }

    @objc func undo(_ sender: Any?) { state.undo() }
    @objc func redo(_ sender: Any?) { state.redo() }
    @objc func copy(_ sender: Any?) { state.copyToClipboard() }
    @objc func saveImage(_ sender: Any?) { state.saveToFolder() }
    @objc func saveImageAs(_ sender: Any?) { state.saveAs(from: window) }
}

struct CanvasRepresentable: NSViewRepresentable {
    let canvas: EditorCanvasView
    func makeNSView(context: Context) -> EditorCanvasView { canvas }
    func updateNSView(_ nsView: EditorCanvasView, context: Context) { nsView.needsDisplay = true }
}

// MARK: - Toolbar (inside the title bar)

struct EditorView: View {
    @ObservedObject var state: EditorState
    let canvas: EditorCanvasView

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Color.black.opacity(0.5)).frame(height: 1)
            CanvasRepresentable(canvas: canvas)
                .overlay(alignment: .bottomLeading) {
                    Text("\(state.image.width) × \(state.image.height) px")
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.black.opacity(0.45)))
                        .padding(12)
                        .allowsHitTesting(false)
                }
                .overlay(alignment: .bottomTrailing) {
                    ZoomControl(state: state, canvas: canvas)
                        .padding(12)
                }
                .overlay(alignment: .bottom) {
                    if let toast = state.toast {
                        HStack(spacing: 7) {
                            Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                            Text(toast).font(.system(size: 12.5, weight: .medium))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .hudBackground(cornerRadius: 18)
                        .padding(.bottom, 18)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .allowsHitTesting(false)
                    }
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.85), value: state.toast)
        }
        .ignoresSafeArea()
        .frame(minWidth: 1080, minHeight: 460)
        .environment(\.colorScheme, .dark)
    }

    private var header: some View {
        HStack(spacing: 12) {
            // Tools: native segmented control.
            Picker("", selection: $state.tool) {
                ForEach(EditorTool.allCases) { tool in
                    Image(systemName: tool.symbol)
                        .help(tool.label)
                        .tag(tool)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .onChange(of: state.tool) { _, tool in
                if tool != .select { state.selectedID = nil }
            }

            // Color: swatches + system color picker.
            HStack(spacing: 4) {
                ForEach(Array(EditorPalette.colors.enumerated()), id: \.offset) { _, color in
                    colorButton(color)
                }
                ColorPicker("", selection: Binding(
                    get: { Color(nsColor: state.color) },
                    set: { state.color = NSColor($0) }
                ), supportsOpacity: false)
                .labelsHidden()
                .help(S.bgColor)
            }

            Menu {
                Picker(S.strokeWidth, selection: $state.widthLevel) {
                    ForEach(Array(1...4), id: \.self) { level in
                        Text(S.widthNames[level - 1]).tag(level)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Image(systemName: "lineweight")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(S.strokeWidth)

            ControlGroup {
                Button { state.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                    .disabled(!state.canUndo)
                    .help("\(S.undo) (⌘Z)")
                Button { state.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                    .disabled(!state.canRedo)
                    .help("\(S.redo) (⇧⌘Z)")
            }
            .fixedSize()

            Spacer(minLength: 8)

            Button { state.copyToClipboard() } label: { Label(S.copy, systemImage: "doc.on.doc") }
                .help("\(S.copy) (⌘C)")
            Button { state.saveAs(from: canvas.window) } label: { Image(systemName: "square.and.arrow.down.on.square") }
                .help("\(S.saveAs) (⇧⌘S)")
            Button { state.saveToFolder() } label: { Label(S.save, systemImage: "square.and.arrow.down") }
                .buttonStyle(.borderedProminent)
                .help("\(S.save) (⌘S)")
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .padding(.leading, 84) // room for the window buttons
        .padding(.trailing, 14)
        .frame(height: 60)
        .background(WindowDragArea())
        .background(VisualEffectBackground(material: .titlebar))
    }

    private func colorButton(_ color: NSColor) -> some View {
        let selected = state.color == color
        return Button {
            state.color = color
        } label: {
            ZStack {
                Circle()
                    .fill(Color(nsColor: color))
                    .frame(width: 14, height: 14)
                    .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 0.5))
                if selected {
                    Circle()
                        .stroke(Color.accentColor, lineWidth: 2)
                        .frame(width: 20, height: 20)
                }
            }
            .frame(width: 20, height: 20)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

/// Zoom control at the bottom right: −, percentage (click = fit), +.
struct ZoomControl: View {
    @ObservedObject var state: EditorState
    let canvas: EditorCanvasView

    var body: some View {
        HStack(spacing: 2) {
            button("minus", help: "\(S.zoomOut) (⌘−)") { canvas.zoomOut() }
            Menu {
                Button(S.zoomFit) { canvas.zoomToFit() }
                Button(S.zoomActual) { canvas.zoomActualSize() }
                Divider()
                ForEach([50, 100, 200, 400], id: \.self) { percent in
                    Button("\(percent) %") {
                        let current = max(1, CGFloat(state.zoomPercent))
                        canvas.setZoom(state.zoom * CGFloat(percent) / current)
                    }
                }
            } label: {
                Text("\(state.zoomPercent) %")
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundColor(.white)
                    .frame(minWidth: 52)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(S.zoomFit)
            button("plus", help: "\(S.zoomIn) (⌘+)") { canvas.zoomIn() }
        }
        .padding(3)
        .background(Capsule().fill(Color.black.opacity(0.55)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5))
    }

    private func button(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .help(help)
    }
}

// MARK: - Window

@MainActor
final class EditorWindowController: NSWindowController, NSWindowDelegate {
    private static var instances: [EditorWindowController] = []
    let state: EditorState
    private let canvas: EditorCanvasView

    static func open(image: CGImage, scale: CGFloat) {
        let controller = EditorWindowController(image: image, scale: scale)
        instances.append(controller)
        NSApp.activate(ignoringOtherApps: true)
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        let canvas = controller.canvas
        Task { @MainActor in
            controller.window?.makeFirstResponder(canvas)
        }
    }

    init(image: CGImage, scale: CGFloat) {
        let state = EditorState(image: image, scale: scale)
        let canvas = EditorCanvasView(state: state)
        self.state = state
        self.canvas = canvas

        let visible = NSScreen.underMouse.visibleFrame
        let s = max(scale, 1)
        let points = CGSize(width: CGFloat(image.width) / s, height: CGFloat(image.height) / s)
        let width = min(max(points.width + 72, 1120), visible.width * 0.92)
        let height = min(max(points.height + 72 + 52, 520), visible.height * 0.9)

        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: width, height: height),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered,
                              defer: false)
        window.title = S.editorTitle
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(calibratedWhite: 0.11, alpha: 1)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: EditorView(state: state, canvas: canvas))
        window.center()
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    func windowWillClose(_ notification: Notification) {
        EditorWindowController.instances.removeAll { $0 === self }
    }
}
