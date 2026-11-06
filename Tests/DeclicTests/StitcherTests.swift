import XCTest
@testable import Declic

final class StitcherTests: XCTestCase {
    let width = 240
    let height = 360
    let headerHeight = 40
    let footerHeight = 30
    var doc: [[UInt8]] = []
    var header: [[UInt8]] = []
    var footer: [[UInt8]] = []

    override func setUp() {
        var gen = Synthetic()
        doc = gen.document(width: width, height: 5000)
        header = gen.band(width: width, height: headerHeight, base: 90, stripe: 7)
        footer = gen.band(width: width, height: footerHeight, base: 60, stripe: 5)
    }

    /// Ce qu'affiche la vue quand le document est défilé à la ligne `pos`.
    func view(_ pos: Int) -> [[UInt8]] {
        header + Array(doc[pos..<(pos + height - headerHeight - footerHeight)]) + footer
    }

    /// Résultat attendu : en-tête + tout le contenu parcouru + pied de page.
    func expected(_ positions: [Int]) -> [[UInt8]] {
        let lo = positions.min()!, hi = positions.max()!
        return header + Array(doc[lo..<(hi + height - headerHeight - footerHeight)]) + footer
    }

    func stitch(_ positions: [Int]) -> [[UInt8]] {
        let stitcher = CoreStitcher()
        for p in positions {
            _ = stitcher.process(CoreStitcher.makeFrame(Synthetic.frame(view(p))))
        }
        guard let image = stitcher.compose() else { return [] }
        return Synthetic.gray(image)
    }

    func assertStitched(_ positions: [Int], file: StaticString = #filePath, line: UInt = #line) {
        let result = stitch(positions)
        let truth = expected(positions)
        XCTAssertEqual(result.count, truth.count, "hauteur", file: file, line: line)
        if result.count == truth.count {
            let wrong = zip(result, truth).enumerated().filter { $0.element.0 != $0.element.1 }.map(\.offset)
            XCTAssertTrue(wrong.isEmpty, "lignes différentes : \(wrong.prefix(10))", file: file, line: line)
        }
    }

    func testScrollDown() {
        assertStitched(Array(stride(from: 0, to: 2400, by: 111)))
    }

    func testScrollUpFromTheMiddle() {
        assertStitched(Array(stride(from: 2000, to: 900, by: -90)))
    }

    func testDownThenUpPastStartThenDown() {
        let positions = [1500] + Array(stride(from: 1560, to: 2100, by: 60))
            + Array(stride(from: 2040, to: 900, by: -70)) + Array(stride(from: 970, to: 1400, by: 50))
        assertStitched(positions)
    }

    func testNoScrollGivesSingleFrame() {
        let stitcher = CoreStitcher()
        for _ in 0..<4 { _ = stitcher.process(CoreStitcher.makeFrame(Synthetic.frame(view(300)))) }
        XCTAssertEqual(stitcher.compose()?.height, height)
    }

    func testTooFastIsReportedAsLost() {
        let stitcher = CoreStitcher()
        _ = stitcher.process(CoreStitcher.makeFrame(Synthetic.frame(view(0))))
        let result = stitcher.process(CoreStitcher.makeFrame(Synthetic.frame(view(height * 2))))
        XCTAssertEqual(result, .lost)
    }

    /// Fenêtre avec une barre d'outils fixe et deux panneaux : la liste à gauche change aussi
    /// (sélection), mais le pointeur est sur le contenu à droite → c'est lui qui est capturé.
    func testWindowPicksPaneUnderPointer() {
        var gen = Synthetic(rng: SplitMix(seed: 7))
        let toolbar = gen.band(width: 400, height: 50, base: 200, stripe: 9)
        let list1 = gen.document(width: 150, height: 400)
        let list2 = gen.document(width: 150, height: 400)
        let paneWidth = width
        func window(_ pos: Int, list: [[UInt8]]) -> [[UInt8]] {
            let pane = Array(doc[pos..<(pos + 400)])
            let divider = [UInt8](repeating: 120, count: 10)
            return toolbar.map { $0 } + (0..<400).map { y in list[y] + divider + pane[y] }
        }
        _ = paneWidth
        let stitcher = WindowScrollStitcher()
        stitcher.focus = (330, 250)
        XCTAssertEqual(stitcher.process(Synthetic.frame(window(1000, list: list1))), .unchanged)
        let result = stitcher.process(Synthetic.frame(window(1080, list: list2)))
        XCTAssertEqual(result, .added)
        let crop = try? XCTUnwrap(stitcher.crop)
        XCTAssertGreaterThanOrEqual(crop?.x ?? 0, 155, "la zone doit être le panneau de droite")
        XCTAssertGreaterThanOrEqual(crop?.y ?? 0, 45, "la barre d'outils est exclue")
    }

    /// Un changement qui n'est pas un défilement (image qui se charge) ne fige pas la zone.
    func testNonScrollChangeDoesNotLockCrop() {
        var gen = Synthetic(rng: SplitMix(seed: 9))
        let a = gen.document(width: 300, height: 300)
        let b = gen.document(width: 300, height: 300)
        let stitcher = WindowScrollStitcher()
        _ = stitcher.process(Synthetic.frame(a))
        XCTAssertEqual(stitcher.process(Synthetic.frame(b)), .unchanged)
        XCTAssertNil(stitcher.crop)
    }
}
