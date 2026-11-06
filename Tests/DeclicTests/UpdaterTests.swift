import XCTest
@testable import Declic

@MainActor
final class UpdaterTests: XCTestCase {
    func testVersionComparison() {
        XCTAssertTrue(Updater.isNewer("1.0.1", than: "1.0.0"))
        XCTAssertTrue(Updater.isNewer("1.10.0", than: "1.9.9"))
        XCTAssertTrue(Updater.isNewer("2", than: "1.99"))
        XCTAssertFalse(Updater.isNewer("1.0.0", than: "1.0.0"))
        XCTAssertFalse(Updater.isNewer("1.0", than: "1.0.0"))
        XCTAssertFalse(Updater.isNewer("0.9.9", than: "1.0.0"))
    }
}

@MainActor
final class GalleryLayoutTests: XCTestCase {
    func testLayoutFitsAndDoesNotOverlap() {
        let area = CGRect(x: 70, y: 70, width: 1300, height: 700)
        let sizes = (0..<9).map { i in CGSize(width: 600 + i * 90, height: 400 + (i % 3) * 120) }
        let frames = WindowGallery.layout(sizes, in: area)
        XCTAssertEqual(frames.count, sizes.count)
        for (i, f) in frames.enumerated() {
            XCTAssertTrue(area.insetBy(dx: -1, dy: -1).contains(f), "tile \(i) outside the area: \(f)")
            for g in frames[(i + 1)...] {
                XCTAssertFalse(f.insetBy(dx: 1, dy: 1).intersects(g), "overlapping tiles")
            }
        }
    }

    func testEmptyLayout() {
        XCTAssertTrue(WindowGallery.layout([], in: CGRect(x: 0, y: 0, width: 100, height: 100)).isEmpty)
    }
}
