import AppKit
import SwiftUI

/// Déclic's visual identity.
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

    /// Menu bar icon: the viewfinder, as a template image
    /// (macOS tints it black or white depending on the appearance).
    static func menuBarIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setStroke()
            let inset: CGFloat = 2.5
            let r = rect.insetBy(dx: inset, dy: inset)
            let arm: CGFloat = 4.6
            let radius: CGFloat = 2.2
            let corners = NSBezierPath()
            corners.lineWidth = 1.7
            corners.lineCapStyle = .round
            corners.lineJoinStyle = .round
            // Bottom left, bottom right, top right, top left (unflipped coordinates).
            func corner(_ origin: NSPoint, _ dx: CGFloat, _ dy: CGFloat) {
                corners.move(to: NSPoint(x: origin.x, y: origin.y + dy * arm))
                corners.line(to: NSPoint(x: origin.x, y: origin.y + dy * radius))
                corners.curve(to: NSPoint(x: origin.x + dx * radius, y: origin.y),
                              controlPoint1: origin, controlPoint2: origin)
                corners.line(to: NSPoint(x: origin.x + dx * arm, y: origin.y))
            }
            corner(NSPoint(x: r.minX, y: r.minY), 1, 1)
            corner(NSPoint(x: r.maxX, y: r.minY), -1, 1)
            corner(NSPoint(x: r.maxX, y: r.maxY), -1, -1)
            corner(NSPoint(x: r.minX, y: r.maxY), 1, -1)
            corners.stroke()

            return true
        }
        image.isTemplate = true
        return image
    }
}
