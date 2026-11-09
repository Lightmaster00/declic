import AppKit
import SwiftUI

/// Declic's visual identity.
///
/// - Coral #FF5B3A (primary), apricot #FF8A3D and raspberry #E8344E (icon gradient).
/// - Ink #16151D for text on light backgrounds, paper #FBF7F2 for light backgrounds.
/// - Symbol: a viewfinder (four rounded corners).
enum Brand {
    static let coral = Color(red: 1.0, green: 0.357, blue: 0.227)        // #FF5B3A
    static let apricot = Color(red: 1.0, green: 0.541, blue: 0.239)      // #FF8A3D
    static let raspberry = Color(red: 0.910, green: 0.204, blue: 0.306)  // #E8344E
    static let ink = Color(red: 0.086, green: 0.082, blue: 0.114)        // #16151D
    static let paper = Color(red: 0.984, green: 0.969, blue: 0.949)      // #FBF7F2

    static let gradient = LinearGradient(colors: [apricot, coral, raspberry],
                                         startPoint: .topLeading, endPoint: .bottomTrailing)

    /// Menu bar icon (template image): the viewfinder corners of the app icon.
    /// Same grammar as the other Lightmaster apps: 1.6 pt round strokes in a 14 pt box, no fills.
    static func menuBarIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            let path = NSBezierPath()
            path.lineWidth = 1.6
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            let arm: CGFloat = 4.4, radius: CGFloat = 2.4
            func corner(_ x: CGFloat, _ y: CGFloat, _ dx: CGFloat, _ dy: CGFloat) {
                path.move(to: NSPoint(x: x, y: y + dy * arm))
                path.line(to: NSPoint(x: x, y: y + dy * radius))
                path.curve(to: NSPoint(x: x + dx * radius, y: y), controlPoint1: NSPoint(x: x, y: y), controlPoint2: NSPoint(x: x, y: y))
                path.line(to: NSPoint(x: x + dx * arm, y: y))
            }
            corner(2.3, 2.3, 1, 1)
            corner(15.7, 2.3, -1, 1)
            corner(15.7, 15.7, -1, -1)
            corner(2.3, 15.7, 1, -1)
            NSColor.black.setStroke()
            path.stroke()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Declic"
        return image
    }
}
