import AppKit
import CoreImage
import UniformTypeIdentifiers

enum EditorTool: String, CaseIterable, Identifiable {
    case select, arrow, line, rectangle, ellipse, text, highlight, pixelate, counter, crop

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .select: return "cursorarrow"
        case .arrow: return "arrow.up.right"
        case .line: return "line.diagonal"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .text: return "textformat"
        case .highlight: return "highlighter"
        case .pixelate: return "checkerboard.rectangle"
        case .counter: return "1.circle"
        case .crop: return "crop"
        }
    }

    var shortcut: String {
        switch self {
        case .select: return "V"
        case .arrow: return "A"
        case .line: return "L"
        case .rectangle: return "R"
        case .ellipse: return "O"
        case .text: return "T"
        case .highlight: return "H"
        case .pixelate: return "P"
        case .counter: return "N"
        case .crop: return "C"
        }
    }

    var label: String {
        let name: String
        switch self {
        case .select: name = S.toolSelect
        case .arrow: name = S.toolArrow
        case .line: name = S.toolLine
        case .rectangle: name = S.toolRectangle
        case .ellipse: name = S.toolEllipse
        case .text: name = S.toolText
        case .highlight: name = S.toolHighlight
        case .pixelate: name = S.toolPixelate
        case .counter: name = S.toolCounter
        case .crop: name = S.toolCrop
        }
        return "\(name) (\(shortcut))"
    }

    static func forKey(_ key: String) -> EditorTool? {
        allCases.first { $0.shortcut.lowercased() == key }
    }
}

enum AnnotationKind: Equatable {
    case arrow, line, rectangle, ellipse, highlight, pixelate
    case text(String)
    case counter(Int)
}

/// Annotation, in image pixels, origin at top left.
struct Annotation: Identifiable {
    let id = UUID()
    var kind: AnnotationKind
    var start: CGPoint
    var end: CGPoint
    var color: NSColor
    var width: CGFloat

    var rect: CGRect {
        CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
               width: abs(end.x - start.x), height: abs(end.y - start.y))
    }
}

enum EditorPalette {
    static let colors: [NSColor] = [
        .systemRed, .systemOrange, .systemYellow, .systemGreen,
        .systemBlue, .systemPurple, .black, .white,
    ]
}

@MainActor
final class EditorState: ObservableObject {
    @Published var tool: EditorTool = .arrow
    @Published var color: NSColor = .systemRed {
        didSet { updateSelected { $0.color = color } }
    }
    @Published var widthLevel: Int = 2 {
        didSet { updateSelected { $0.width = strokeWidth } }
    }
    @Published private(set) var image: CGImage
    @Published var annotations: [Annotation] = []
    @Published var selectedID: UUID?
    @Published var draft: Annotation?
    @Published var cropRect: CGRect?
    @Published var toast: String?
    /// Zoom relative to the fitted image (1 = fit), and view offset in points.
    @Published var zoom: CGFloat = 1
    @Published var pan: CGPoint = .zero
    /// Actual zoom in % (100% = actual size), updated by the canvas.
    @Published var zoomPercent: Int = 100

    /// Pixels per point of the capture (2 on a Retina display).
    let pixelScale: CGFloat

    private struct Snapshot {
        let image: CGImage
        let annotations: [Annotation]
        let nextCounter: Int
    }

    private var nextCounter = 1
    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []
    private var pixelatedCache: CGImage?

    init(image: CGImage, scale: CGFloat) {
        self.image = image
        self.pixelScale = max(1, scale)
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var imageSize: CGSize { CGSize(width: image.width, height: image.height) }
    var imageBounds: CGRect { CGRect(origin: .zero, size: imageSize) }

    var strokeWidth: CGFloat {
        let levels: [CGFloat] = [2, 3, 5, 8]
        return levels[min(max(widthLevel, 1), 4) - 1] * pixelScale
    }

    // MARK: History

    private var snapshot: Snapshot {
        Snapshot(image: image, annotations: annotations, nextCounter: nextCounter)
    }

    func registerUndo() {
        undoStack.append(snapshot)
        if undoStack.count > 200 { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    private func restore(_ s: Snapshot) {
        if s.image !== image { pixelatedCache = nil }
        image = s.image
        annotations = s.annotations
        nextCounter = s.nextCounter
        selectedID = nil
    }

    func undo() {
        guard let s = undoStack.popLast() else { return }
        redoStack.append(snapshot)
        restore(s)
    }

    func redo() {
        guard let s = redoStack.popLast() else { return }
        undoStack.append(snapshot)
        restore(s)
    }

    // MARK: Annotations

    func makeAnnotation(_ kind: AnnotationKind, at p: CGPoint) -> Annotation {
        Annotation(kind: kind, start: p, end: p, color: color, width: strokeWidth)
    }

    func takeCounterValue() -> Int {
        defer { nextCounter += 1 }
        return nextCounter
    }

    func add(_ annotation: Annotation) {
        registerUndo()
        annotations.append(annotation)
    }

    func moveAnnotation(_ id: UUID, dx: CGFloat, dy: CGFloat) {
        guard let i = annotations.firstIndex(where: { $0.id == id }) else { return }
        annotations[i].start.x += dx
        annotations[i].start.y += dy
        annotations[i].end.x += dx
        annotations[i].end.y += dy
    }

    func deleteSelected() {
        guard let id = selectedID, let i = annotations.firstIndex(where: { $0.id == id }) else { return }
        registerUndo()
        annotations.remove(at: i)
        selectedID = nil
    }

    private func updateSelected(_ change: (inout Annotation) -> Void) {
        guard let id = selectedID, let i = annotations.firstIndex(where: { $0.id == id }) else { return }
        registerUndo()
        change(&annotations[i])
    }

    func applyCrop(_ rect: CGRect) {
        let r = rect.intersection(imageBounds).integral
        guard r.width >= 2, r.height >= 2, let cropped = image.cropping(to: r) else { return }
        registerUndo()
        image = cropped
        pixelatedCache = nil
        annotations = annotations.map { a in
            var a = a
            a.start.x -= r.minX; a.start.y -= r.minY
            a.end.x -= r.minX; a.end.y -= r.minY
            return a
        }
        selectedID = nil
    }

    /// Pixelated version of the whole image (only the blurred areas show it).
    func pixelatedImage() -> CGImage? {
        if let pixelatedCache { return pixelatedCache }
        let input = CIImage(cgImage: image)
        guard let filter = CIFilter(name: "CIPixellate") else { return nil }
        filter.setValue(input.clampedToExtent(), forKey: kCIInputImageKey)
        filter.setValue(max(8 * pixelScale, CGFloat(image.width) / 120), forKey: kCIInputScaleKey)
        guard let output = filter.outputImage?.cropped(to: input.extent),
              let cg = CIContext().createCGImage(output, from: input.extent) else { return nil }
        pixelatedCache = cg
        return cg
    }

    // MARK: Export

    func renderFlattened() -> CGImage? {
        let w = image.width, h = image.height
        let space: CGColorSpace = {
            if let cs = image.colorSpace, cs.model == .rgb, cs.supportsOutput { return cs }
            return CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        }()
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        AnnotationRenderer.draw(state: self, in: ctx, includeDraft: false, showSelection: false)
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()
    }

    func copyToClipboard() {
        guard let img = renderFlattened() else { return }
        Clipboard.copy(image: img, scale: pixelScale)
        flash(S.copied)
    }

    func saveToFolder() {
        guard let img = renderFlattened() else { return }
        do {
            let url = try FileUtil.savePNG(img)
            flash(S.saved(url.lastPathComponent))
        } catch {
            flash(S.error(error.localizedDescription))
        }
    }

    func saveAs(from window: NSWindow?) {
        guard let img = renderFlattened() else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "\(S.screenshotPrefix) \(FileUtil.timestamp()).png"
        panel.directoryURL = Prefs.shared.saveFolder
        let handler: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let url = panel.url, let data = FileUtil.pngData(img) else { return }
            do {
                try data.write(to: url)
                self?.flash(S.saved(url.lastPathComponent))
            } catch {
                self?.flash(S.error(error.localizedDescription))
            }
        }
        if let window { panel.beginSheetModal(for: window, completionHandler: handler) }
        else { handler(panel.runModal()) }
    }

    func flash(_ message: String) {
        toast = message
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if self?.toast == message { self?.toast = nil }
        }
    }
}

/// Draws annotations in a y-down context, in image pixels.
@MainActor
enum AnnotationRenderer {
    static func draw(state: EditorState, in ctx: CGContext, includeDraft: Bool, showSelection: Bool) {
        drawImage(state.image, in: state.imageBounds, ctx: ctx)
        var list = state.annotations
        if includeDraft, let draft = state.draft { list.append(draft) }
        for a in list { draw(a, state: state, ctx: ctx) }

        if showSelection, let id = state.selectedID, let a = list.first(where: { $0.id == id }) {
            let s = state.pixelScale
            let r = bounds(of: a, scale: s).insetBy(dx: -5 * s, dy: -5 * s)
            ctx.saveGState()
            ctx.setStrokeColor(NSColor.controlAccentColor.cgColor)
            ctx.setLineWidth(1.5 * s)
            ctx.setLineDash(phase: 0, lengths: [5 * s, 4 * s])
            ctx.addPath(CGPath(roundedRect: r, cornerWidth: 4 * s, cornerHeight: 4 * s, transform: nil))
            ctx.strokePath()
            ctx.setLineDash(phase: 0, lengths: [])
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.setStrokeColor(NSColor.controlAccentColor.cgColor)
            for p in [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
                      CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.maxX, y: r.maxY)] {
                let dot = CGRect(x: p.x - 3.5 * s, y: p.y - 3.5 * s, width: 7 * s, height: 7 * s)
                ctx.fillEllipse(in: dot)
                ctx.strokeEllipse(in: dot)
            }
            ctx.restoreGState()
        }
    }

    /// Draws a CGImage upright in a flipped context.
    static func drawImage(_ image: CGImage, in rect: CGRect, ctx: CGContext) {
        ctx.saveGState()
        ctx.translateBy(x: rect.minX, y: rect.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(image, in: CGRect(origin: .zero, size: rect.size))
        ctx.restoreGState()
    }

    static func fontSize(width: CGFloat, scale: CGFloat) -> CGFloat {
        max(14 * scale, width * 5)
    }

    static func textString(_ text: String, _ a: Annotation, scale: CGFloat) -> NSAttributedString {
        let shadow = NSShadow()
        shadow.shadowBlurRadius = 3 * scale
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
        return NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: fontSize(width: a.width, scale: scale), weight: .bold),
            .foregroundColor: a.color,
            .shadow: shadow,
        ])
    }

    static func counterRadius(_ a: Annotation) -> CGFloat { max(12, a.width * 4) }

    static func bounds(of a: Annotation, scale: CGFloat) -> CGRect {
        switch a.kind {
        case .text(let s):
            return CGRect(origin: a.start, size: textString(s, a, scale: scale).size())
        case .counter:
            let r = counterRadius(a)
            return CGRect(x: a.start.x - r, y: a.start.y - r, width: r * 2, height: r * 2)
        default:
            return a.rect.insetBy(dx: -a.width / 2, dy: -a.width / 2)
        }
    }

    static func draw(_ a: Annotation, state: EditorState, ctx: CGContext) {
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.setStrokeColor(a.color.cgColor)
        ctx.setFillColor(a.color.cgColor)
        ctx.setLineWidth(a.width)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        switch a.kind {
        case .line:
            ctx.move(to: a.start)
            ctx.addLine(to: a.end)
            ctx.strokePath()

        case .arrow:
            drawArrow(a, ctx: ctx)

        case .rectangle:
            let radius = min(a.width, a.rect.width / 2, a.rect.height / 2)
            ctx.addPath(CGPath(roundedRect: a.rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
            ctx.strokePath()

        case .ellipse:
            ctx.strokeEllipse(in: a.rect)

        case .highlight:
            ctx.setBlendMode(.multiply)
            ctx.setFillColor(a.color.withAlphaComponent(0.45).cgColor)
            ctx.fill(a.rect)

        case .pixelate:
            if let pixelated = state.pixelatedImage() {
                ctx.clip(to: a.rect)
                drawImage(pixelated, in: state.imageBounds, ctx: ctx)
            }

        case .text(let s):
            textString(s, a, scale: state.pixelScale).draw(at: a.start)

        case .counter(let n):
            let r = counterRadius(a)
            let circle = CGRect(x: a.start.x - r, y: a.start.y - r, width: r * 2, height: r * 2)
            ctx.setShadow(offset: CGSize(width: 0, height: r * 0.08), blur: r * 0.3,
                          color: NSColor.black.withAlphaComponent(0.3).cgColor)
            ctx.fillEllipse(in: circle)
            ctx.setShadow(offset: .zero, blur: 0, color: nil)
            let light = a.color == .white || a.color == .systemYellow
            let str = NSAttributedString(string: "\(n)", attributes: [
                .font: NSFont.systemFont(ofSize: r * 1.1, weight: .bold),
                .foregroundColor: light ? NSColor.black : NSColor.white,
            ])
            let size = str.size()
            str.draw(at: CGPoint(x: a.start.x - size.width / 2, y: a.start.y - size.height / 2))
        }
    }

    private static func drawArrow(_ a: Annotation, ctx: CGContext) {
        let dx = a.end.x - a.start.x, dy = a.end.y - a.start.y
        let length = hypot(dx, dy)
        guard length > 1 else { return }
        let angle = atan2(dy, dx)
        let head = min(max(a.width * 4, 12), length * 0.6)
        let spread: CGFloat = .pi / 7
        let base = CGPoint(x: a.end.x - cos(angle) * head * 0.8, y: a.end.y - sin(angle) * head * 0.8)
        ctx.move(to: a.start)
        ctx.addLine(to: base)
        ctx.strokePath()
        let p1 = CGPoint(x: a.end.x - head * cos(angle - spread), y: a.end.y - head * sin(angle - spread))
        let p2 = CGPoint(x: a.end.x - head * cos(angle + spread), y: a.end.y - head * sin(angle + spread))
        ctx.move(to: a.end)
        ctx.addLine(to: p1)
        ctx.addLine(to: p2)
        ctx.closePath()
        ctx.fillPath()
    }
}
