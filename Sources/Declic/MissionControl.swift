import AppKit
import ApplicationServices

/// Choix d'une fenêtre avec le « Mission Control » de Déclic (voir WindowGallery).
/// Rien ne change à l'écran une fois le choix fait : pas d'app activée, pas de bureau changé.
@MainActor
final class MissionControlPicker {
    static let shared = MissionControlPicker()

    private var gallery: WindowGallery?
    private(set) var isPicking = false

    func pick(_ completion: @escaping (WindowCandidate?) -> Void) {
        cancel()
        isPicking = true
        Task {
            do {
                let content = try await Capturer.content()
                let candidates = Capturer.windowCandidates(content)
                guard !candidates.isEmpty else {
                    self.isPicking = false
                    completion(nil)
                    return
                }
                self.gallery = WindowGallery(candidates: candidates, title: S.galleryHint) { candidate in
                    let picker = MissionControlPicker.shared
                    picker.gallery = nil
                    picker.isPicking = false
                    completion(candidate)
                }
            } catch {
                self.isPicking = false
                completion(nil)
                Capturer.presentError(error)
            }
        }
    }

    /// Ferme la galerie en cours (le rappel reçoit nil).
    func cancel() {
        gallery?.cancel()
        gallery = nil
    }
}

/// Met une fenêtre précise au premier plan (utile pour la faire défiler), puis permet
/// de revenir à l'app d'origine.
@MainActor
enum WindowRaiser {
    static func raise(_ candidate: WindowCandidate) {
        guard let pid = candidate.window.owningApplication?.processID,
              let app = NSRunningApplication(processIdentifier: pid) else { return }
        app.activate()

        // Avec l'autorisation d'accessibilité, on remonte la fenêtre exacte (pas seulement l'app).
        guard AXIsProcessTrusted() else { return }
        let axApp = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return }
        let target = candidate.window.frame // coordonnées CG (origine en haut à gauche)
        for window in windows {
            guard let frame = frame(of: window) else { continue }
            if abs(frame.minX - target.minX) < 4, abs(frame.minY - target.minY) < 4,
               abs(frame.width - target.width) < 4, abs(frame.height - target.height) < 4 {
                AXUIElementPerformAction(window, kAXRaiseAction as CFString)
                AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
                break
            }
        }
    }

    private static func frame(of window: AXUIElement) -> CGRect? {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionRef) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let positionRef, let sizeRef,
              CFGetTypeID(positionRef) == AXValueGetTypeID(),
              CFGetTypeID(sizeRef) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(positionRef as! AXValue, .cgPoint, &point)
        AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        return CGRect(origin: point, size: size)
    }
}
