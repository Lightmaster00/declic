import AppKit
import ApplicationServices
import Carbon
import CoreMedia
@preconcurrency import ScreenCaptureKit
import SwiftUI

// MARK: - Raw frames

/// A BGRA frame of the window.
struct RawFrame {
    let width: Int
    let height: Int
    let bytesPerRow: Int
    let data: Data

    init(width: Int, height: Int, bytesPerRow: Int, data: Data) {
        self.width = width
        self.height = height
        self.bytesPerRow = bytesPerRow
        self.data = data
    }

    init?(pixelBuffer: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        let w = CVPixelBufferGetWidth(pixelBuffer)
        let h = CVPixelBufferGetHeight(pixelBuffer)
        let bpr = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard w > 8, h > 8 else { return nil }
        self.init(width: w, height: h, bytesPerRow: bpr, data: Data(bytes: base, count: bpr * h))
    }

    /// Copy of a sub-area (in pixels, origin at top left).
    func cropped(x: Int, y: Int, width cw: Int, height ch: Int) -> RawFrame {
        let outBPR = cw * 4
        var out = Data(count: outBPR * ch)
        out.withUnsafeMutableBytes { dst in
            data.withUnsafeBytes { src in
                guard let d = dst.baseAddress, let s = src.baseAddress else { return }
                for row in 0..<ch {
                    memcpy(d + row * outBPR, s + (y + row) * bytesPerRow + x * 4, outBPR)
                }
            }
        }
        return RawFrame(width: cw, height: ch, bytesPerRow: outBPR, data: out)
    }

    func luminance(_ p: UnsafeBufferPointer<UInt8>, x: Int, y: Int) -> Int {
        let o = y * bytesPerRow + x * 4
        return (Int(p[o + 2]) * 77 + Int(p[o + 1]) * 150 + Int(p[o]) * 29) >> 8
    }
}

// MARK: - Stitching

enum ScrollResult {
    /// Nothing moved.
    case unchanged
    /// New rows were added.
    case added
    /// Content changed but no offset was found (scrolled too fast).
    case lost
    /// Maximum height reached.
    case full
}

/// A (cropped) frame ready for comparison: per row, the mean luminance of 64 blocks.
struct ScrollFrame {
    let raw: RawFrame
    let signature: [UInt8]
    let informative: [Bool]
    var width: Int { raw.width }
    var height: Int { raw.height }
}

/// Stitches successive frames of a scrolling area, scrolling down as well as up.
///
/// - For each frame, find the vertical offset `d` that aligns its rows
/// with the reference frame (ignoring fixed headers and footers).
/// - When several offsets are equally good (lists with similar rows), keep
/// the one that best continues the previous motion.
/// - Edge columns that don't follow the scroll (scroll bar,
/// floating buttons) are excluded from matching, then trimmed from the result.
final class CoreStitcher {
    static let blocks = 64
    static let maxHeight = 40_000

    /// Stitched pieces, placed on a vertical canvas (y down).
    /// They're painted in order: a newer piece covers an older one.
    private var pieces: [(y: Int, image: CGImage)] = []
    private var first: ScrollFrame?
    private var reference: ScrollFrame?
    /// Frame that provided the bottom of the canvas: the footer comes from it
    /// (otherwise, when scrolling up, the bottom of a higher frame would be pasted below).
    private var bottomFrame: ScrollFrame?
    /// Top and bottom of the canvas (the fixed footer is added below `canvasMax`).
    private var canvasMin = 0
    private var canvasMax = 0
    /// Canvas position of row 0 of the reference frame.
    private var viewTop = 0
    /// Number of fixed header rows at the top of the canvas.
    private var topHeader = 0
    private var footer = 0
    private var scrolled = false
    private(set) var previousShift = 0
    private var badBlocks = [Bool](repeating: false, count: CoreStitcher.blocks)

    /// Expected offset in pixels (auto-scroll), 0 if unknown.
    var expectedShift = 0
    /// Details of the last computation (diagnostic log).
    private(set) var lastInfo = ""

    var width: Int { reference?.width ?? 0 }
    var totalHeight: Int { canvasMax - canvasMin }

    static func blockEdges(width: Int) -> [Int] {
        (0...blocks).map { ($0 * width) / blocks }
    }

    static func makeFrame(_ raw: RawFrame) -> ScrollFrame {
        let n = blocks
        let w = raw.width, h = raw.height
        let edges = blockEdges(width: w)
        var signature = [UInt8](repeating: 0, count: h * n)
        var informative = [Bool](repeating: false, count: h)
        raw.data.withUnsafeBytes { buffer in
            let p = buffer.bindMemory(to: UInt8.self)
            for y in 0..<h {
                var lo = 255, hi = 0
                for b in 0..<n {
                    let x0 = edges[b], x1 = max(edges[b + 1], x0 + 1)
                    var sum = 0
                    for x in x0..<min(x1, w) { sum += raw.luminance(p, x: x, y: y) }
                    let avg = sum / max(1, min(x1, w) - x0)
                    signature[y * n + b] = UInt8(avg)
                    lo = min(lo, avg)
                    hi = max(hi, avg)
                }
                informative[y] = hi - lo > 4
            }
        }
        return ScrollFrame(raw: raw, signature: signature, informative: informative)
    }

    /// Compares a frame with the reference and adds the new rows.
    func process(_ cur: ScrollFrame) -> ScrollResult {
        guard let ref = reference else {
            first = cur
            reference = cur
            return .unchanged
        }
        guard cur.width == ref.width, cur.height == ref.height else { return .unchanged }
        guard totalHeight < Self.maxHeight else { return .full }

        let h = cur.height
        let n = Self.blocks
        let good = (0..<n).filter { !badBlocks[$0] }
        guard good.count >= 8 else { return .lost }

        return ref.signature.withUnsafeBufferPointer { rs -> ScrollResult in
            cur.signature.withUnsafeBufferPointer { cs -> ScrollResult in
                func diff(_ ry: Int, _ cy: Int) -> Int {
                    var sum = 0
                    let a = ry * n, b = cy * n
                    for c in good { sum += abs(Int(rs[a + c]) - Int(cs[b + c])) }
                    return sum
                }
                let sameTolerance = good.count

                // Fixed rows at the top and bottom (sticky header / footer).
                var top = 0
                while top < h, diff(top, top) <= sameTolerance { top += 1 }
                if top == h { return .unchanged } // nothing moved
                var bottom = 0
                while bottom < h - top, diff(h - 1 - bottom, h - 1 - bottom) <= sameTolerance { bottom += 1 }

                let usable = h - top - bottom
                lastInfo = "h=\(h) top=\(top) bottom=\(bottom) good=\(good.count)"
                let minOverlap = max(24, usable / 6)
                guard usable > minOverlap + 1 else { return .lost }
                let maxShift = usable - minOverlap

                // Informative rows (with detail) of the current frame.
                var rows: [Int] = []
                rows.reserveCapacity(usable)
                for y in top..<(h - bottom) where cur.informative[y] { rows.append(y) }
                lastInfo += " rows=\(rows.count)"
                guard rows.count >= 8 else { return .lost }

                /// Rows y of the current frame such that y and y + d are in the scrolling area.
                func range(_ d: Int) -> (lo: Int, hi: Int) {
                    (max(top, top - d), min(h - bottom, h - bottom - d))
                }

                /// Mean cost (×100) of offset d (positive: scrolling down,
                /// negative: scrolling up), over a sample of rows.
                func cost(_ d: Int, stride: Int) -> Int? {
                    let (lo, hi) = range(d)
                    var sum = 0
                    var count = 0
                    var i = 0
                    while i < rows.count {
                        let y = rows[i]
                        if y >= hi { break }
                        if y >= lo {
                            sum += diff(y + d, y)
                            count += 1
                        }
                        i += stride
                    }
                    return count >= 8 ? sum * 100 / count : nil
                }

                // 1) Every offset, both directions, on ~150 rows: fast even for a large window.
                let coarseStride = max(1, rows.count / 150)
                var coarse: [(d: Int, c: Int)] = []
                coarse.reserveCapacity(maxShift * 2)
                for d in -maxShift...maxShift where d != 0 {
                    if let c = cost(d, stride: coarseStride) { coarse.append((d, c)) }
                }
                guard let coarseBest = coarse.map({ $0.c }).min() else { return .lost }

                // 2) The best candidates, on every row.
                let candidates = coarse
                    .filter { $0.c <= coarseBest + coarseBest / 2 + good.count * 100 }
                    .sorted { $0.c < $1.c }
                    .prefix(24)
                var fine: [(d: Int, c: Int)] = []
                for candidate in candidates {
                    if let c = cost(candidate.d, stride: 1) { fine.append((candidate.d, c)) }
                }
                let bestCost = fine.map({ $0.c }).min()
                lastInfo += " best=\(bestCost.map(String.init) ?? "-") limit=\(good.count * 800)"
                guard let best = bestCost, best <= good.count * 800 else { return .lost }

                // Nearly-as-good offsets: keep the one most consistent with the motion.
                let threshold = best + best * 15 / 100 + good.count * 50
                let near = fine.filter { $0.c <= threshold }.map { $0.d }
                let hint = expectedShift > 0 ? expectedShift : previousShift
                let shift: Int
                if hint != 0 {
                    shift = near.min { abs($0 - hint) < abs($1 - hint) } ?? 0
                } else {
                    shift = near.max() ?? 0
                }
                lastInfo += " shift=\(shift) near=\(near.count)"
                guard shift != 0 else { return .lost }

                // Edge columns that don't follow the scroll (scroll bar…) → excluded.
                var errors = [Int](repeating: 0, count: n)
                var counted = 0
                let valid = range(shift)
                for y in rows where y >= valid.lo && y < valid.hi {
                    let a = (y + shift) * n, b = y * n
                    for c in 0..<n { errors[c] += abs(Int(rs[a + c]) - Int(cs[b + c])) }
                    counted += 1
                }
                if counted > 0 {
                    let goodErrors = good.map { errors[$0] / counted }.sorted()
                    let median = goodErrors[goodErrors.count / 2]
                    for c in stride(from: n - 1, through: 0, by: -1) {
                        if errors[c] / counted > median + 6 { badBlocks[c] = true } else { break }
                    }
                    for c in 0..<n {
                        if errors[c] / counted > median + 6 { badBlocks[c] = true } else { break }
                    }
                }
                previousShift = shift

                var end = h - footer
                if !scrolled {
                    // First scroll: the canvas starts with the first frame, without its footer.
                    scrolled = true
                    footer = bottom
                    end = h - footer
                    if let first, let image = Self.image(from: first.raw, rows: 0..<end) {
                        pieces.append((0, image))
                    }
                    canvasMin = 0
                    canvasMax = end
                    viewTop = 0
                    topHeader = top
                    bottomFrame = first
                }
                viewTop += shift

                // New content at the bottom.
                if viewTop + end > canvasMax {
                    let start = max(0, canvasMax - viewTop)
                    if end > start, let image = Self.image(from: cur.raw, rows: start..<end) {
                        pieces.append((viewTop + start, image))
                    }
                    canvasMax = viewTop + end
                    bottomFrame = cur
                }
                // New content at the top: the header is taken too and moves to the top of the canvas.
                if viewTop + top < canvasMin + topHeader {
                    let stop = min(end, canvasMin + topHeader - viewTop)
                    if stop > 0, let image = Self.image(from: cur.raw, rows: 0..<stop) {
                        pieces.append((viewTop, image))
                    }
                    canvasMin = viewTop
                    topHeader = top
                }
                reference = cur
                return .added
            }
        }
    }

    /// Columns to keep (without the excluded edges).
    private var keptColumns: Range<Int> {
        let w = width
        let edges = Self.blockEdges(width: w)
        var left = 0, right = w
        for b in 0..<Self.blocks { if badBlocks[b] { left = edges[b + 1] } else { break } }
        for b in stride(from: Self.blocks - 1, through: 0, by: -1) { if badBlocks[b] { right = edges[b] } else { break } }
        return right > left ? left..<right : 0..<w
    }

    /// Final image: stitched canvas + footer.
    func compose() -> CGImage? {
        guard let reference else { return nil }
        guard scrolled else {
            return Self.image(from: reference.raw, rows: 0..<reference.height)
        }
        let bottom = bottomFrame ?? reference
        let footerImage = footer > 0
            ? Self.image(from: bottom.raw, rows: (bottom.height - footer)..<bottom.height) : nil
        guard let full = render(from: canvasMin, to: canvasMax, footer: footerImage,
                                width: reference.width, scale: 1) else { return nil }
        let keep = keptColumns
        if keep.count == full.width { return full }
        return full.cropping(to: CGRect(x: keep.lowerBound, y: 0, width: keep.count, height: full.height)) ?? full
    }

    /// Small version of the current area (around the current position), for the live preview.
    func preview(width: Int) -> CGImage? {
        let sourceWidth = self.width
        guard sourceWidth > 0 else { return nil }
        guard scrolled else {
            guard let first, let image = Self.image(from: first.raw, rows: 0..<first.height) else { return nil }
            return render(parts: [(0, image)], from: 0, to: first.height, footer: nil,
                          width: width, scale: CGFloat(width) / CGFloat(sourceWidth))
        }
        let frameHeight = reference?.height ?? 0
        let span = sourceWidth * 6
        var lo = viewTop + frameHeight - span
        lo = max(canvasMin, min(lo, canvasMax - span))
        let hi = min(canvasMax, lo + span)
        return render(from: lo, to: hi, footer: nil, width: width, scale: CGFloat(width) / CGFloat(sourceWidth))
    }

    private func render(from lo: Int, to hi: Int, footer: CGImage?, width: Int, scale: CGFloat) -> CGImage? {
        render(parts: pieces, from: lo, to: hi, footer: footer, width: width, scale: scale)
    }

    /// Paints the pieces (in order) over canvas range [lo, hi), then the footer.
    private func render(parts: [(y: Int, image: CGImage)], from lo: Int, to hi: Int,
                        footer: CGImage?, width: Int, scale: CGFloat) -> CGImage? {
        let rows = hi - lo + (footer?.height ?? 0)
        let height = max(1, Int((CGFloat(rows) * scale).rounded()))
        guard rows > 0, let ctx = Self.context(width: width, height: height) else { return nil }
        ctx.interpolationQuality = scale == 1 ? .none : .medium
        let canvasWidth = CGFloat(self.width > 0 ? self.width : width) * scale
        // canvas y (down) → context y (up).
        func rect(_ y: Int, _ h: Int) -> CGRect {
            CGRect(x: 0, y: CGFloat(height) - CGFloat(y - lo + h) * scale, width: canvasWidth, height: CGFloat(h) * scale)
        }
        for part in parts where part.y < hi && part.y + part.image.height > lo {
            ctx.draw(part.image, in: rect(part.y, part.image.height))
        }
        if let footer {
            ctx.draw(footer, in: rect(hi, footer.height))
        }
        return ctx.makeImage()
    }

    // MARK: Tools

    static let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue

    static func image(from frame: RawFrame, rows: Range<Int>) -> CGImage? {
        guard !rows.isEmpty, rows.lowerBound >= 0, rows.upperBound <= frame.height else { return nil }
        let sub = frame.data.subdata(in: (rows.lowerBound * frame.bytesPerRow)..<(rows.upperBound * frame.bytesPerRow))
        guard let provider = CGDataProvider(data: sub as CFData) else { return nil }
        return CGImage(width: frame.width, height: rows.count,
                       bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: frame.bytesPerRow,
                       space: ImageTools.sRGB, bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    static func context(width: Int, height: Int) -> CGContext? {
        CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                  space: ImageTools.sRGB, bitmapInfo: bitmapInfo)
    }

    static func stack(_ parts: [CGImage], width: Int) -> CGImage? {
        let total = parts.reduce(0) { $0 + $1.height }
        guard total > 0, let ctx = context(width: width, height: total) else { return nil }
        var y = total
        for part in parts {
            y -= part.height
            ctx.draw(part, in: CGRect(x: 0, y: y, width: part.width, height: part.height))
        }
        return ctx.makeImage()
    }
}

/// Scrolling capture of a window: finds the scrolling area automatically
/// (ignoring the toolbar, sidebar, etc.) and stitches its content.
final class WindowScrollStitcher {
    private var firstRaw: RawFrame?
    /// Scrolling area, in pixels (origin at top left).
    private(set) var crop: (x: Int, y: Int, w: Int, h: Int)?
    private var core = CoreStitcher()
    private var failedDetections = 0
    let log = ScrollDebugLog()

    var totalHeight: Int { core.totalHeight }

    /// Pointer position in the frame (pixels, origin at top left), when it's over the window.
    /// The scrolling area picked is the one under the pointer (e.g. the message in Mail, not the list).
    var focus: (x: Int, y: Int)?

    /// Expected offset in pixels during auto-scroll.
    var expectedShift: Int {
        get { core.expectedShift }
        set { core.expectedShift = newValue }
    }

    func process(_ raw: RawFrame) -> ScrollResult {
        guard let first = firstRaw else {
            firstRaw = raw
            return .unchanged
        }
        guard raw.width == first.width, raw.height == first.height else { return .unchanged }
        if crop == nil {
            // The scrolling area must be large enough (otherwise it's a hover effect, a blinking caret…).
            guard let changed = Self.changedBox(first, raw, focus: focus),
                  changed.w >= raw.width / 4, changed.h >= raw.height / 4 else { return .unchanged }
            // Two side-by-side panes can change at once (e.g. Mail: the list and the
            // message): only keep the columns that scroll like the ones under the pointer.
            let box = Self.scrollingColumns(first, raw, in: changed, focus: focus) ?? changed
            guard box.w >= raw.width / 4 else { return .unchanged }
            // Make sure it really is a scroll (not an image loading, an animation,
            // a banner appearing…): otherwise, after a few tries, restart from the current frame.
            let trial = CoreStitcher()
            trial.expectedShift = core.expectedShift
            _ = trial.process(CoreStitcher.makeFrame(first.cropped(x: box.x, y: box.y, width: box.w, height: box.h)))
            let result = trial.process(CoreStitcher.makeFrame(raw.cropped(x: box.x, y: box.y, width: box.w, height: box.h)))
            log.write("detect box=\(box) focus=\(String(describing: focus)) result=\(result) \(trial.lastInfo)")
            guard result == .added else {
                failedDetections += 1
                if failedDetections >= 3 {
                    log.write("rebaseline")
                    firstRaw = raw
                    failedDetections = 0
                }
                return .unchanged
            }
            log.saveImage(first, name: "first")
            log.saveImage(raw, name: "second")
            crop = box
            core = trial
            return .added
        }
        guard let c = crop else { return .unchanged }
        let result = core.process(CoreStitcher.makeFrame(raw.cropped(x: c.x, y: c.y, width: c.w, height: c.h)))
        if result != .unchanged { log.write("frame result=\(result) height=\(core.totalHeight) \(core.lastInfo)") }
        return result
    }

    func compose() -> CGImage? {
        if crop == nil {
            guard let first = firstRaw else { return nil }
            return CoreStitcher.image(from: first, rows: 0..<first.height)
        }
        return core.compose()
    }

    func preview(width: Int) -> CGImage? {
        if crop == nil {
            guard let first = firstRaw, let image = CoreStitcher.image(from: first, rows: 0..<first.height) else { return nil }
            let scale = CGFloat(width) / CGFloat(first.width)
            let h = max(1, Int(CGFloat(first.height) * scale))
            guard let ctx = CoreStitcher.context(width: width, height: h) else { return nil }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: h))
            return ctx.makeImage()
        }
        return core.preview(width: width)
    }

    /// Bounding box of the pixels that changed between two frames,
    /// extended to neighbouring plain rows (margins of the scrolling view).
    static func changedBox(_ a: RawFrame, _ b: RawFrame,
                           focus: (x: Int, y: Int)? = nil) -> (x: Int, y: Int, w: Int, h: Int)? {
        let w = a.width, h = a.height
        // 1) Grid of 16 px cells: cells where pixels changed.
        let cell = 16
        let gw = (w + cell - 1) / cell, gh = (h + cell - 1) / cell
        var grid = [Int](repeating: 0, count: gw * gh)
        a.data.withUnsafeBytes { ra in
            b.data.withUnsafeBytes { rb in
                let pa = ra.bindMemory(to: UInt8.self)
                let pb = rb.bindMemory(to: UInt8.self)
                var y = 0
                while y < h {
                    var x = 0
                    while x < w {
                        if abs(a.luminance(pa, x: x, y: y) - b.luminance(pb, x: x, y: y)) > 24 {
                            grid[(y / cell) * gw + x / cell] += 1
                        }
                        x += 3
                    }
                    y += 2
                }
            }
        }

        // 2) Connected regions (bridging small gaps: line spacing, margins).
        var label = [Int](repeating: -1, count: gw * gh)
        var regions: [(cells: [Int], count: Int)] = []
        let reach = 2
        for start in 0..<(gw * gh) where grid[start] > 0 && label[start] < 0 {
            let id = regions.count
            var stack = [start]
            var cells: [Int] = []
            var count = 0
            label[start] = id
            while let c = stack.popLast() {
                cells.append(c)
                count += grid[c]
                let cx = c % gw, cy = c / gw
                for dy in -reach...reach {
                    for dx in -reach...reach {
                        let nx = cx + dx, ny = cy + dy
                        guard nx >= 0, ny >= 0, nx < gw, ny < gh else { continue }
                        let n = ny * gw + nx
                        if grid[n] > 0 && label[n] < 0 {
                            label[n] = id
                            stack.append(n)
                        }
                    }
                }
            }
            regions.append((cells, count))
        }
        guard !regions.isEmpty else { return nil }

        // 3) Among regions large enough to be a scroll view: the one under the pointer
        // (or the closest), otherwise the largest.
        func bounds(_ cells: [Int]) -> (minX: Int, maxX: Int, minY: Int, maxY: Int) {
            var x0 = Int.max, x1 = -1, y0 = Int.max, y1 = -1
            for c in cells {
                let cx = (c % gw) * cell, cy = (c / gw) * cell
                x0 = min(x0, cx); x1 = max(x1, min(w - 1, cx + cell - 1))
                y0 = min(y0, cy); y1 = max(y1, min(h - 1, cy + cell - 1))
            }
            return (x0, x1, y0, y1)
        }
        let eligible = regions.indices.filter { i in
            let r = bounds(regions[i].cells)
            return regions[i].count >= 40 && r.maxX - r.minX >= max(60, w / 4) && r.maxY - r.minY >= max(60, h / 4)
        }
        guard var chosen = eligible.max(by: { regions[$0].count < regions[$1].count }) else { return nil }
        if let focus, focus.x >= 0, focus.y >= 0, focus.x < w, focus.y < h {
            let fx = focus.x / cell, fy = focus.y / cell
            var bestDistance = Int.max
            for index in eligible {
                var d = Int.max
                for c in regions[index].cells {
                    let dx = c % gw - fx, dy = c / gw - fy
                    d = min(d, dx * dx + dy * dy)
                    if d == 0 { break }
                }
                if d < bestDistance { bestDistance = d; chosen = index }
            }
        }
        var (minX, maxX, minY, maxY) = bounds(regions[chosen].cells)
        guard maxX - minX >= 60, maxY - minY >= 60 else { return nil }
        // Cells overshoot a little: tighten to the pixels that actually changed.
        a.data.withUnsafeBytes { ra in
            b.data.withUnsafeBytes { rb in
                let pa = ra.bindMemory(to: UInt8.self)
                let pb = rb.bindMemory(to: UInt8.self)
                func columnChanged(_ x: Int) -> Bool {
                    var y = minY
                    while y <= maxY {
                        if abs(a.luminance(pa, x: x, y: y) - b.luminance(pb, x: x, y: y)) > 24 { return true }
                        y += 1
                    }
                    return false
                }
                func rowChanged(_ y: Int) -> Bool {
                    var x = minX
                    while x <= maxX {
                        if abs(a.luminance(pa, x: x, y: y) - b.luminance(pb, x: x, y: y)) > 24 { return true }
                        x += 1
                    }
                    return false
                }
                while minX < maxX, !columnChanged(minX) { minX += 1 }
                while maxX > minX, !columnChanged(maxX) { maxX -= 1 }
                while minY < maxY, !rowChanged(minY) { minY += 1 }
                while maxY > minY, !rowChanged(maxY) { maxY -= 1 }
            }
        }
        guard maxX - minX >= 60, maxY - minY >= 60 else { return nil }

        // Refine edges to the pixel (the sampling above skips columns/rows).
        a.data.withUnsafeBytes { ra in
            b.data.withUnsafeBytes { rb in
                let pa = ra.bindMemory(to: UInt8.self)
                let pb = rb.bindMemory(to: UInt8.self)
                func columnChanged(_ x: Int) -> Bool {
                    for y in minY...maxY where abs(a.luminance(pa, x: x, y: y) - b.luminance(pb, x: x, y: y)) > 24 {
                        return true
                    }
                    return false
                }
                func rowChanged(_ y: Int) -> Bool {
                    for x in minX...maxX where abs(a.luminance(pa, x: x, y: y) - b.luminance(pb, x: x, y: y)) > 24 {
                        return true
                    }
                    return false
                }
                for x in stride(from: minX - 1, to: max(-1, minX - 4), by: -1) where columnChanged(x) { minX = x }
                for x in stride(from: maxX + 1, to: min(w, maxX + 4), by: 1) where columnChanged(x) { maxX = x }
                for y in stride(from: minY - 1, to: max(-1, minY - 3), by: -1) where rowChanged(y) { minY = y }
                for y in stride(from: maxY + 1, to: min(h, maxY + 3), by: 1) where rowChanged(y) { maxY = y }
            }
        }

        // Extend vertically over plain rows (view background) in both frames.
        func uniform(_ f: RawFrame, _ p: UnsafeBufferPointer<UInt8>, row: Int) -> Bool {
            var lo = 255, hi = 0
            var x = minX
            while x <= maxX {
                let l = f.luminance(p, x: x, y: row)
                lo = min(lo, l)
                hi = max(hi, l)
                if hi - lo > 10 { return false }
                x += 4
            }
            return true
        }
        a.data.withUnsafeBytes { ra in
            b.data.withUnsafeBytes { rb in
                let pa = ra.bindMemory(to: UInt8.self)
                let pb = rb.bindMemory(to: UInt8.self)
                while minY > 0, uniform(a, pa, row: minY - 1), uniform(b, pb, row: minY - 1) { minY -= 1 }
                while maxY < h - 1, uniform(a, pa, row: maxY + 1), uniform(b, pb, row: maxY + 1) { maxY += 1 }
            }
        }
        let x0 = max(0, minX), x1 = min(w, maxX + 1)
        let y0 = max(0, minY), y1 = min(h, maxY + 1)
        return (x0, y0, x1 - x0, y1 - y0)
    }

    /// Inside `box`, splits the bands of changed columns (separated by unchanged
    /// columns: border, margin, divider). Measures the scroll of the band under the pointer,
    /// then keeps only the bands that moved the same way.
    static func scrollingColumns(_ a: RawFrame, _ b: RawFrame, in box: (x: Int, y: Int, w: Int, h: Int),
                                 focus: (x: Int, y: Int)?) -> (x: Int, y: Int, w: Int, h: Int)? {
        let x0 = box.x, x1 = box.x + box.w, y0 = box.y, y1 = box.y + box.h
        guard box.w > 8, box.h > 32 else { return nil }
        return a.data.withUnsafeBytes { ra -> (x: Int, y: Int, w: Int, h: Int)? in
            b.data.withUnsafeBytes { rb -> (x: Int, y: Int, w: Int, h: Int)? in
                let pa = ra.bindMemory(to: UInt8.self)
                let pb = rb.bindMemory(to: UInt8.self)

                // 1) Changed columns.
                var changed = [Bool](repeating: false, count: box.w)
                for x in x0..<x1 {
                    var y = y0
                    while y < y1 {
                        if abs(a.luminance(pa, x: x, y: y) - b.luminance(pb, x: x, y: y)) > 24 {
                            changed[x - x0] = true
                            break
                        }
                        y += 2
                    }
                }
                var bands: [Range<Int>] = []
                var start: Int?
                for i in 0...box.w {
                    let on = i < box.w && changed[i]
                    if on, start == nil { start = i }
                    if !on, let s = start {
                        if i - s >= 4 { bands.append((x0 + s)..<(x0 + i)) }
                        start = nil
                    }
                }
                guard bands.count > 1 else { return nil }

                // 2) Reference band: under the pointer (or the closest), otherwise the widest.
                func distance(_ r: Range<Int>, _ x: Int) -> Int {
                    r.contains(x) ? 0 : min(abs(r.lowerBound - x), abs(r.upperBound - 1 - x))
                }
                let reference: Range<Int>
                if let focus, focus.y >= y0, focus.y < y1 {
                    reference = bands.min { distance($0, focus.x) < distance($1, focus.x) }!
                } else {
                    reference = bands.max { $0.count < $1.count }!
                }

                // 3) Scroll offset of the reference band.
                let refFirst = CoreStitcher.makeFrame(a.cropped(x: reference.lowerBound, y: y0,
                                                                width: reference.count, height: box.h))
                let refSecond = CoreStitcher.makeFrame(b.cropped(x: reference.lowerBound, y: y0,
                                                                 width: reference.count, height: box.h))
                let probe = CoreStitcher()
                _ = probe.process(refFirst)
                guard probe.process(refSecond) == .added else { return nil }
                let d = probe.previousShift

                /// Mean difference between the band shifted by d in frame a and the same band in b.
                func error(_ r: Range<Int>) -> Int {
                    var sum = 0, count = 0
                    var y = max(y0, y0 - d)
                    let yEnd = min(y1, y1 - d)
                    while y < yEnd {
                        var x = r.lowerBound
                        while x < r.upperBound {
                            sum += abs(a.luminance(pa, x: x, y: y + d) - b.luminance(pb, x: x, y: y))
                            count += 1
                            x += 2
                        }
                        y += 2
                    }
                    return count > 0 ? sum / count : 255
                }
                let refError = error(reference)
                let limit = max(6, refError * 2 + 3)
                let kept = bands.filter { $0 == reference || error($0) <= limit }
                let lo = kept.map(\.lowerBound).min()!, hi = kept.map(\.upperBound).max()!
                return (lo, y0, hi - lo, box.h)
            }
        }
    }
}

// MARK: - Diagnostic log

/// Scrolling capture log, to understand failures: every computation is written there,
/// along with the first two analysed frames.
/// Development build: `<sources>/build/debug/`. Otherwise: `~/Library/Logs/Declic/`.
final class ScrollDebugLog {
    private let folder: URL
    private let handle: FileHandle?
    private let start = Date()
    /// Frames are only written in development builds: they may show private content.
    private let savesImages: Bool

    init() {
        let base: URL
        let sourceDir = Bundle.main.object(forInfoDictionaryKey: "DeclicSourceDir") as? String
        savesImages = sourceDir != nil
        if let dir = sourceDir {
            base = URL(fileURLWithPath: dir).appendingPathComponent("build/debug", isDirectory: true)
        } else {
            base = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Logs/Declic", isDirectory: true)
        }
        folder = base
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let file = base.appendingPathComponent("scroll.log")
        FileManager.default.createFile(atPath: file.path, contents: nil)
        handle = try? FileHandle(forWritingTo: file)
    }

    deinit { try? handle?.close() }

    func write(_ line: String) {
        let t = String(format: "%7.2f", Date().timeIntervalSince(start))
        handle?.write(Data("\(t) \(line)\n".utf8))
    }

    func saveImage(_ frame: RawFrame, name: String) {
        guard savesImages, let image = CoreStitcher.image(from: frame, rows: 0..<frame.height),
              let data = FileUtil.pngData(image) else { return }
        try? data.write(to: folder.appendingPathComponent("\(name).png"))
    }
}

// MARK: - Stream

/// Captures the window ~15 times per second. Frames arriving during a computation
/// are dropped: the queue never grows, even for a very large window.
final class ScrollRecorder: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let captureQueue = DispatchQueue(label: "com.lightmaster.declic.scroll.capture")
    private let processQueue = DispatchQueue(label: "com.lightmaster.declic.scroll.process", qos: .userInitiated)
    private let lock = NSLock()
    private var busy = false
    private let stitcher = WindowScrollStitcher()
    private var stream: SCStream?
    private var lastPreview: TimeInterval = 0
    private var lostCount = 0
    /// Captured window (CG coordinates, in points) and scale, to locate the pointer.
    var windowFrame: CGRect = .zero
    var pixelScale: CGFloat = 2

    /// (height in pixels, optional preview, content added, scrolled too fast, max height reached)
    var onUpdate: (@Sendable (Int, CGImage?, Bool, Bool, Bool) -> Void)?

    func start(filter: SCContentFilter, configuration: SCStreamConfiguration) async throws {
        let s = SCStream(filter: filter, configuration: configuration, delegate: self)
        try s.addStreamOutput(self, type: .screen, sampleHandlerQueue: captureQueue)
        stream = s
        try await s.startCapture()
    }

    /// Sets the expected offset (auto-scroll), or 0.
    func setExpectedShift(_ pixels: Int) {
        processQueue.async { self.stitcher.expectedShift = pixels }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let rawStatus = attachments.first?[.status] as? Int,
              let status = SCFrameStatus(rawValue: rawStatus), status == .complete,
              let pixelBuffer = sampleBuffer.imageBuffer else { return }

        lock.lock()
        if busy {
            lock.unlock()
            return
        }
        busy = true
        lock.unlock()

        guard let frame = RawFrame(pixelBuffer: pixelBuffer) else {
            lock.lock(); busy = false; lock.unlock()
            return
        }
        let mouse = CGEvent(source: nil)?.location
        let frameRect = windowFrame, scale = pixelScale
        processQueue.async {
            if let mouse, frameRect.contains(mouse) {
                self.stitcher.focus = (Int((mouse.x - frameRect.minX) * scale), Int((mouse.y - frameRect.minY) * scale))
            } else {
                self.stitcher.focus = nil
            }
            self.handle(frame)
            self.lock.lock()
            self.busy = false
            self.lock.unlock()
        }
    }

    private func handle(_ frame: RawFrame) {
        let result = stitcher.process(frame)
        let added = result == .added
        switch result {
        case .added: lostCount = 0
        case .lost: lostCount += 1
        case .unchanged, .full: break
        }
        let tooFast = lostCount >= 3
        let now = ProcessInfo.processInfo.systemUptime
        let height = max(stitcher.totalHeight, frame.height)
        if (added || lastPreview == 0), now - lastPreview > 0.25 {
            lastPreview = now
            onUpdate?(height, stitcher.preview(width: 180), added, tooFast, result == .full)
        } else {
            onUpdate?(height, nil, added, tooFast, result == .full)
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        NSLog("Declic: scrolling capture stopped: \(error)")
    }

    func finish() async -> CGImage? {
        if let s = stream {
            stream = nil
            try? await s.stopCapture()
        }
        return await withCheckedContinuation { (cont: CheckedContinuation<CGImage?, Never>) in
            processQueue.async {
                cont.resume(returning: self.stitcher.compose())
            }
        }
    }

    func cancel() async {
        if let s = stream {
            stream = nil
            try? await s.stopCapture()
        }
    }
}

// MARK: - Interface

final class ScrollModel: ObservableObject {
    @Published var height = 0
    @Published var preview: NSImage?
    @Published var autoScrolling = false
    @Published var tooFast = false
    @Published var full = false
}

struct ScrollControlView: View {
    @ObservedObject var model: ScrollModel
    let onAuto: () -> Void
    let onDone: () -> Void
    let onCancel: () -> Void

    private var status: String {
        if model.full { return S.maxHeightReached }
        if model.tooFast { return S.tooFast }
        return model.autoScrolling ? S.autoScrolling : S.scrollInstruction
    }

    var body: some View {
        HStack(spacing: 12) {
            HUDIconButton(symbol: "xmark", help: "\(S.cancel) (Esc)", action: onCancel)
            VStack(alignment: .leading, spacing: 1) {
                Text(status)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(model.tooFast ? .orange : .white)
                Text("\(model.height) px")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundColor(.white.opacity(0.55))
            }
            .frame(minWidth: 170, alignment: .leading)
            PillButton(title: S.autoScroll,
                       symbol: model.autoScrolling ? "pause.fill" : "arrow.down.to.line",
                       action: onAuto)
            HUDTextButton(title: S.done, symbol: "checkmark", action: onDone)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .hudBackground(cornerRadius: 18)
        .padding(16)
    }
}

struct ScrollPreviewView: View {
    @ObservedObject var model: ScrollModel

    var body: some View {
        VStack {
            if let preview = model.preview {
                Image(nsImage: preview)
                    .resizable()
                    .interpolation(.medium)
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .frame(maxHeight: .infinity, alignment: .bottom)
            } else {
                ProgressView().controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(8)
        .hudBackground(cornerRadius: 14)
        .padding(16)
    }
}

@MainActor
final class ScrollCaptureController {
    static let shared = ScrollCaptureController()

    private var recorder: ScrollRecorder?
    private var candidate: WindowCandidate?
    private var scale: CGFloat = 2
    private var controlPanel: FloatingPanel?
    private var previewPanel: FloatingPanel?
    private var escKey: UInt32?
    private var autoTimer: Timer?
    private var lastGrowth = Date()
    private let model = ScrollModel()
    private(set) var active = false
    /// Frontmost app before the capture: we return to it at the end.
    private var previousApp: NSRunningApplication?

    /// Shortcut: pick a window in the gallery, or finish the current capture.
    func start() {
        if recorder != nil { finish(); return }
        guard !active, !CaptureCoordinator.shared.busy else { return }
        active = true
        MissionControlPicker.shared.pick { [weak self] candidate in
            guard let self else { return }
            guard let candidate else { self.active = false; return }
            Task { await self.begin(candidate) }
        }
    }

    private func begin(_ candidate: WindowCandidate) async {
        do {
            // To scroll the window, it has to be in front of the others.
            // We'll return to the original app once the capture is done.
            previousApp = NSWorkspace.shared.frontmostApplication
            WindowRaiser.raise(candidate)
            try? await Task.sleep(nanoseconds: 250_000_000)

            let filter = SCContentFilter(desktopIndependentWindow: candidate.window)
            let s = CGFloat(filter.pointPixelScale)
            let config = SCStreamConfiguration()
            config.width = Int(filter.contentRect.width * s)
            config.height = Int(filter.contentRect.height * s)
            config.minimumFrameInterval = CMTime(value: 1, timescale: 15)
            config.showsCursor = false
            config.pixelFormat = kCVPixelFormatType_32BGRA
            config.colorSpaceName = CGColorSpace.sRGB
            config.ignoreShadowsSingleWindow = true
            config.queueDepth = 3

            model.height = config.height
            model.preview = nil
            model.autoScrolling = false
            model.tooFast = false
            model.full = false

            let recorder = ScrollRecorder()
            recorder.windowFrame = candidate.window.frame
            recorder.pixelScale = s
            recorder.onUpdate = { height, preview, grew, tooFast, full in
                Task { @MainActor in
                    let controller = ScrollCaptureController.shared
                    let m = controller.model
                    m.height = height
                    if let preview { m.preview = NSImage(cgImage: preview, size: .zero) }
                    if grew { controller.lastGrowth = Date() }
                    if m.tooFast != tooFast { m.tooFast = tooFast }
                    if full && !m.full {
                        m.full = true
                        controller.stopAutoScroll()
                    }
                }
            }
            try await recorder.start(filter: filter, configuration: config)
            self.recorder = recorder
            self.candidate = candidate
            self.scale = s
            showUI(for: candidate)
        } catch {
            active = false
            Capturer.presentError(error)
        }
    }

    /// Controls placed outside the window (so they don't appear in the capture).
    private func showUI(for candidate: WindowCandidate) {
        let rect = candidate.frame
        let screen = NSScreen.best(for: rect)
        let vf = screen.visibleFrame

        let control = FirstMouseHostingView(rootView: ScrollControlView(
            model: model,
            onAuto: { [weak self] in self?.toggleAutoScroll() },
            onDone: { [weak self] in self?.finish() },
            onCancel: { [weak self] in self?.cancel() }
        ))
        let size = control.fittingSize
        let panel = FloatingPanel(size: CGSize(width: size.width + 80, height: size.height))
        panel.level = .statusBar
        control.frame = CGRect(origin: .zero, size: panel.frame.size)
        panel.contentView = control
        panel.setFrameOrigin(CGPoint(x: vf.midX - panel.frame.width / 2, y: vf.minY + 8))
        panel.orderFrontRegardless()
        controlPanel = panel

        let previewWidth: CGFloat = 180 + 16 + 32
        let previewHeight = min(max(vf.height * 0.55, 260), vf.height - 40)
        let pp = FloatingPanel(size: CGSize(width: previewWidth, height: previewHeight))
        let preview = FirstMouseHostingView(rootView: ScrollPreviewView(model: model))
        pp.level = .statusBar
        pp.ignoresMouseEvents = true
        preview.frame = CGRect(origin: .zero, size: pp.frame.size)
        pp.contentView = preview
        // On the right of the screen, or on the left if the window covers that side.
        let right = rect.maxX < vf.maxX - previewWidth
        let px = right ? vf.maxX - previewWidth : vf.minX
        pp.setFrameOrigin(CGPoint(x: px, y: vf.midY - previewHeight / 2))
        pp.orderFrontRegardless()
        previewPanel = pp

        escKey = HotKeyCenter.shared.register(keyCode: kVK_Escape, modifiers: 0) { [weak self] in
            self?.cancel()
        }
    }

    // MARK: Auto-scroll

    private func toggleAutoScroll() {
        if autoTimer != nil {
            stopAutoScroll()
            return
        }
        // Posting scroll events requires Accessibility permission.
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else { return }
        guard let candidate, let recorder else { return }

        // Scroll under the pointer if it's over the window (the chosen area, e.g. the message
        // in Mail); otherwise move it to the center (CG coordinates, origin at top left).
        let f = candidate.window.frame
        var point = CGPoint(x: f.midX, y: f.midY)
        if let mouse = CGEvent(source: nil)?.location, f.insetBy(dx: 4, dy: 4).contains(mouse) {
            point = mouse
        } else {
            CGWarpMouseCursorPosition(point)
        }
        let stepPoints = Int32(max(60, min(300, f.height * 0.25)))
        recorder.setExpectedShift(Int(CGFloat(stepPoints) * scale))
        lastGrowth = Date()
        model.autoScrolling = true
        autoTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in
            MainActor.assumeIsolated {
                let controller = ScrollCaptureController.shared
                // End of page: nothing has been added for a while.
                if Date().timeIntervalSince(controller.lastGrowth) > 2.4 {
                    controller.stopAutoScroll()
                    controller.finish()
                    return
                }
                let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
                                    wheel1: -stepPoints, wheel2: 0, wheel3: 0)
                event?.location = point
                event?.post(tap: .cghidEventTap)
            }
        }
    }

    private func stopAutoScroll() {
        autoTimer?.invalidate()
        autoTimer = nil
        model.autoScrolling = false
        recorder?.setExpectedShift(0)
    }

    // MARK: End

    private func hideUI() {
        stopAutoScroll()
        HotKeyCenter.shared.unregister(escKey)
        escKey = nil
        controlPanel?.orderOut(nil)
        controlPanel = nil
        previewPanel?.orderOut(nil)
        previewPanel = nil
    }

    func finish() {
        guard let recorder else { return }
        hideUI()
        self.recorder = nil
        let scale = self.scale
        Task {
            let image = await recorder.finish()
            self.active = false
            self.candidate = nil
            self.restorePreviousApp()
            if let image {
                CaptureCoordinator.shared.deliver(image, scale: scale, origin: nil)
            }
        }
    }

    func cancel() {
        guard let recorder else { return }
        hideUI()
        self.recorder = nil
        Task {
            await recorder.cancel()
            self.active = false
            self.candidate = nil
            self.restorePreviousApp()
        }
    }

    private func restorePreviousApp() {
        defer { previousApp = nil }
        guard let previousApp, previousApp != NSRunningApplication.current,
              NSWorkspace.shared.frontmostApplication != previousApp else { return }
        previousApp.activate()
    }
}
