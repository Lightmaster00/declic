import AppKit
import SwiftUI

/// Ce que contient une vignette.
enum QuickItemKind {
    /// `origin` : position d'origine à l'écran (coordonnées Cocoa), pour épingler au même endroit.
    case image(CGImage, scale: CGFloat, origin: CGRect?)
    case video(URL, isGIF: Bool, thumbnail: NSImage?)
}

enum QuickLayout {
    static let pad: CGFloat = 12
    static let spacing: CGFloat = 10
    static let maxCards = 40
}

/// Confirmation affichée sur la vignette après une action.
struct QuickFeedback: Equatable {
    let symbol: String
    let text: String
}

final class QuickCardModel: ObservableObject {
    @Published var hover = false
    /// Épinglée : la vignette reste affichée après Copier / Enregistrer.
    @Published var pinned = false
    @Published var feedback: QuickFeedback?
}

struct QuickCardActions {
    var preview: () -> Void
    var copy: () -> Void
    var save: () -> Void
    var close: () -> Void
    var edit: (() -> Void)?
    var pin: (() -> Void)?
    var open: (() -> Void)?
}

struct QuickCardView: View {
    @ObservedObject var model: QuickCardModel
    let size: CGSize
    let thumbnail: NSImage
    let badge: String
    let isVideo: Bool
    let dragURL: URL?
    let actions: QuickCardActions

    var body: some View {
        ZStack {
            Rectangle().fill(Color(white: 0.1))
            Image(nsImage: thumbnail)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)

            if let feedback = model.feedback {
                FeedbackBadge(feedback: feedback)
            } else if model.hover {
                Color.black.opacity(0.38)
                    .transition(.opacity)

                VStack(spacing: 8) {
                    PillButton(title: S.copy, symbol: "doc.on.doc", action: actions.copy)
                    PillButton(title: S.save, symbol: "square.and.arrow.down", prominent: true, action: actions.save)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity) // centrés dans la vignette
                .transition(.opacity)

                VStack {
                    HStack(spacing: 5) {
                        CircleIconButton(symbol: "xmark", help: S.close, action: actions.close)
                        Spacer()
                        if let pin = actions.pin {
                            CircleIconButton(symbol: model.pinned ? "pin.fill" : "pin",
                                             help: model.pinned ? S.unpinCard : S.pinCard,
                                             active: model.pinned, action: pin)
                        }
                        if let edit = actions.edit {
                            CircleIconButton(symbol: "pencil", help: S.annotate, action: edit)
                        }
                        if let open = actions.open {
                            CircleIconButton(symbol: "play.fill", help: S.open, action: open)
                        }
                    }
                    Spacer()
                }
                .padding(8)
                .transition(.opacity)
            } else {
                if model.pinned {
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "pin.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 22, height: 22)
                                .background(Circle().fill(Color.accentColor))
                                .shadow(color: .black.opacity(0.3), radius: 3)
                        }
                        Spacer()
                    }
                    .padding(8)
                }
                if isVideo {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 30, weight: .light))
                        .foregroundColor(.white.opacity(0.9))
                        .shadow(color: .black.opacity(0.35), radius: 5)
                }
                VStack {
                    Spacer()
                    HStack {
                        Text(badge)
                            .font(.system(size: 9.5, weight: .medium).monospacedDigit())
                            .foregroundColor(.white.opacity(0.92))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2.5)
                            .background(Capsule().fill(Color.black.opacity(0.5)))
                        Spacer()
                    }
                }
                .padding(7)
                .transition(.opacity)
            }
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .onTapGesture { actions.preview() }
        .help(S.clickToAnnotate)
        .environment(\.colorScheme, .dark)
        .activeControls()
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 3)
        .onDrag {
            if let dragURL, let provider = NSItemProvider(contentsOf: dragURL) { return provider }
            return NSItemProvider()
        }
        .padding(QuickLayout.pad)
        .animation(.easeOut(duration: 0.14), value: model.hover)
        .animation(.spring(response: 0.32, dampingFraction: 0.62), value: model.feedback)
    }
}

/// Coche animée « Copié » / « Enregistré ».
struct FeedbackBadge: View {
    let feedback: QuickFeedback
    @State private var appeared = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
            VStack(spacing: 10) {
                ZStack {
                    Circle().fill(Color.green)
                    Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
                    Image(systemName: feedback.symbol)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                        .scaleEffect(appeared ? 1 : 0.3)
                }
                .frame(width: 54, height: 54)
                .shadow(color: .green.opacity(0.5), radius: appeared ? 14 : 0)
                .scaleEffect(appeared ? 1 : 0.4)
                Text(feedback.text)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 6)
            }
        }
        .transition(.opacity)
        .onAppear {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.55)) { appeared = true }
        }
    }
}

/// Hosting view qui détecte le survol même quand l'app n'est pas active.
final class QuickHostingView: NSHostingView<QuickCardView> {
    var onHover: ((Bool) -> Void)?
    var onScroll: ((NSEvent) -> Void)?

    override func scrollWheel(with event: NSEvent) {
        if let onScroll { onScroll(event) } else { super.scrollWheel(with: event) }
    }
    private var hoverArea: NSTrackingArea?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea, trackingAreas.contains(hoverArea) { return }
        let area = NSTrackingArea(rect: .zero,
                                  options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self,
                                  userInfo: nil)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        onHover?(true)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onHover?(false)
    }
}

/// Pile de vignettes dans un coin de l'écran. Une vignette reste affichée jusqu'à
/// ce qu'on choisisse une action (ou jusqu'au délai réglé dans les réglages).
@MainActor
final class QuickAccessManager {
    static let shared = QuickAccessManager()

    private final class Entry {
        let panel: FloatingPanel
        let kind: QuickItemKind
        let model: QuickCardModel
        var timer: Timer?
        init(panel: FloatingPanel, kind: QuickItemKind, model: QuickCardModel) {
            self.panel = panel
            self.kind = kind
            self.model = model
        }
    }

    private var entries: [Entry] = []
    private var anchorScreen: NSScreen?
    /// Défilement de la pile (quand elle dépasse la hauteur de l'écran).
    private var scrollOffset: CGFloat = 0

    func show(_ kind: QuickItemKind) {
        let prefs = Prefs.shared
        let box = prefs.qaSize.card
        let thumbnail: NSImage
        let dragURL: URL?
        let isImage: Bool
        let badge: String
        switch kind {
        case .image(let image, _, _):
            thumbnail = NSImage(cgImage: ImageTools.downscaled(image, maxPixel: 900), size: .zero)
            dragURL = try? FileUtil.writeTempImage(image)
            isImage = true
            badge = "\(image.width) × \(image.height)"
        case .video(let url, let isGIF, let thumb):
            thumbnail = thumb ?? NSImage(systemSymbolName: "film", accessibilityDescription: nil) ?? NSImage()
            dragURL = url
            isImage = false
            badge = isGIF ? "GIF" : "MP4"
        }

        // Toutes les vignettes ont la même taille ; l'image s'y adapte.
        let card = box
        let size = CGSize(width: card.width + QuickLayout.pad * 2, height: card.height + QuickLayout.pad * 2)
        let panel = FloatingPanel(size: size)
        let model = QuickCardModel()
        let entry = Entry(panel: panel, kind: kind, model: model)

        var actions = QuickCardActions(
            preview: { [weak self, weak entry] in
                guard let self, let entry else { return }
                self.preview(entry)
            },
            copy: { [weak self, weak entry] in
                guard let self, let entry else { return }
                self.copy(entry)
            },
            save: { [weak self, weak entry] in
                guard let self, let entry else { return }
                self.save(entry)
            },
            close: { [weak self, weak entry] in
                guard let self, let entry else { return }
                self.dismiss(entry)
            }
        )
        if isImage {
            actions.pin = { [weak entry] in
                guard let entry else { return }
                entry.model.pinned.toggle()
            }
        } else {
            actions.open = { [weak self, weak entry] in
                guard let self, let entry else { return }
                self.open(entry)
            }
        }

        let view = QuickCardView(model: model, size: card, thumbnail: thumbnail, badge: badge,
                                 isVideo: !isImage, dragURL: dragURL, actions: actions)
        let host = QuickHostingView(rootView: view)
        host.frame = CGRect(origin: .zero, size: size)
        host.onHover = { [weak self, weak entry] hovering in
            model.hover = hovering
            guard let self, let entry, !hovering else { return }
            self.scheduleAutoClose(entry)
        }
        host.onScroll = { [weak self] event in self?.scroll(event) }
        panel.contentView = host

        if entries.isEmpty { anchorScreen = NSScreen.underMouse }
        scrollOffset = 0
        entries.insert(entry, at: 0)
        while entries.count > QuickLayout.maxCards, let oldest = entries.last {
            dismiss(oldest)
        }
        layout(newEntry: entry)
        scheduleAutoClose(entry)
    }

    static func cardSize(for imageSize: CGSize, in box: CGSize) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0 else { return box }
        let aspect = imageSize.width / imageSize.height
        var w = box.width
        var h = w / aspect
        if h > box.height {
            h = box.height
            w = h * aspect
        }
        // Assez de place pour les boutons, même pour une image très étroite ou très plate.
        return CGSize(width: max(w, 176).rounded(), height: max(h, 128).rounded())
    }

    private func scheduleAutoClose(_ entry: Entry) {
        entry.timer?.invalidate()
        entry.timer = nil
        let seconds = Prefs.shared.qaAutoClose
        guard seconds > 0 else { return }
        let id = ObjectIdentifier(entry)
        entry.timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(seconds), repeats: false) { _ in
            MainActor.assumeIsolated {
                QuickAccessManager.shared.autoClose(id)
            }
        }
    }

    private func autoClose(_ id: ObjectIdentifier) {
        guard let entry = entries.first(where: { ObjectIdentifier($0) == id }),
              !entry.model.hover, !entry.model.pinned, entry.model.feedback == nil else { return }
        dismiss(entry)
    }

    private var step: CGFloat {
        Prefs.shared.qaSize.card.height + QuickLayout.spacing
    }

    private var maxScroll: CGFloat {
        guard let first = entries.first else { return 0 }
        let vf = (anchorScreen ?? NSScreen.underMouse).visibleFrame
        let cardHeight = first.panel.frame.height - QuickLayout.pad * 2
        let top = vf.minY + 2 + QuickLayout.pad + CGFloat(entries.count - 1) * step + cardHeight
        return max(0, top - (vf.maxY - 6))
    }

    /// Molette / trackpad au-dessus d'une vignette : fait défiler toute la pile.
    private func scroll(_ event: NSEvent) {
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 12
        let limit = maxScroll
        guard limit > 0 else { return }
        scrollOffset = min(max(0, scrollOffset + delta), limit)
        layout(animated: false)
    }

    private func layout(newEntry: Entry? = nil, animated: Bool = true) {
        let screen = anchorScreen ?? NSScreen.underMouse
        let vf = screen.visibleFrame
        let right = Prefs.shared.qaPosition == .bottomRight
        scrollOffset = min(scrollOffset, maxScroll)
        var y = vf.minY + 2 - scrollOffset
        for entry in entries {
            let size = entry.panel.frame.size
            let x = right ? vf.maxX - size.width - 2 : vf.minX + 2
            let target = CGRect(x: x, y: y, width: size.width, height: size.height)
            // Vignettes hors de l'écran (pile qui défile) : estompées puis masquées.
            let card = target.insetBy(dx: QuickLayout.pad, dy: QuickLayout.pad)
            let visible = card.intersection(vf.insetBy(dx: 0, dy: -2))
            let fraction = card.height > 0 ? max(0, visible.height) / card.height : 0
            let alpha = fraction >= 0.999 ? 1 : max(0, fraction * 1.4 - 0.4)
            entry.panel.ignoresMouseEvents = alpha < 0.5

            if entry === newEntry {
                let offset = right ? size.width + 30 : -size.width - 30
                entry.panel.setFrame(target.offsetBy(dx: offset, dy: 0), display: false)
                entry.panel.alphaValue = alpha
                entry.panel.orderFrontRegardless()
            }
            if animated {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = entry === newEntry ? 0.32 : 0.22
                    ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
                    entry.panel.animator().setFrame(target, display: true)
                    entry.panel.animator().alphaValue = alpha
                }
            } else {
                entry.panel.setFrame(target, display: true)
                entry.panel.alphaValue = alpha
            }
            y += step
        }
    }

    private func dismiss(_ entry: Entry) {
        guard let index = entries.firstIndex(where: { $0 === entry }) else { return }
        entry.timer?.invalidate()
        entry.timer = nil
        entries.remove(at: index)
        let panel = entry.panel
        let right = Prefs.shared.qaPosition == .bottomRight
        let out = panel.frame.offsetBy(dx: (right ? 1 : -1) * panel.frame.width * 0.4, dy: 0)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
            panel.animator().setFrame(out, display: true)
        }, completionHandler: {
            MainActor.assumeIsolated { panel.orderOut(nil) }
        })
        layout()
    }

    // MARK: Actions

    private func copy(_ entry: Entry) {
        switch entry.kind {
        case .image(let image, let scale, _):
            Clipboard.copy(image: image, scale: scale)
        case .video(let url, _, _):
            Clipboard.copy(fileURL: url)
        }
        confirm(entry, QuickFeedback(symbol: "checkmark", text: S.copiedShort))
    }

    /// Affiche la coche animée, puis ferme la vignette (sauf si elle est épinglée).
    private func confirm(_ entry: Entry, _ feedback: QuickFeedback) {
        Sound.success()
        entry.model.feedback = feedback
        entry.timer?.invalidate()
        Task { @MainActor [weak self, weak entry] in
            try? await Task.sleep(nanoseconds: 850_000_000)
            guard let self, let entry, entry.model.feedback == feedback else { return }
            if entry.model.pinned {
                entry.model.feedback = nil
            } else {
                self.dismiss(entry)
            }
        }
    }

    private func save(_ entry: Entry) {
        do {
            switch entry.kind {
            case .image(let image, _, _):
                try FileUtil.savePNG(image)
            case .video(let url, let isGIF, _):
                try FileUtil.saveVideo(url, isGIF: isGIF)
            }
            confirm(entry, QuickFeedback(symbol: "checkmark", text: S.savedShort))
        } catch {
            showError(S.saveFailed, error)
        }
    }

    private func edit(_ entry: Entry) {
        guard case .image(let image, let scale, _) = entry.kind else { return }
        EditorWindowController.open(image: image, scale: scale)
        dismiss(entry)
    }


    /// Clic sur la vignette : ouvre directement l'éditeur d'annotations (aperçu pour les vidéos).
    private func preview(_ entry: Entry) {
        switch entry.kind {
        case .image(let image, let scale, _):
            // La vignette reste affichée.
            EditorWindowController.open(image: image, scale: scale)
        case .video(let url, let isGIF, _):
            PreviewWindowController.show(.video(url, isGIF: isGIF))
        }
    }

    private func open(_ entry: Entry) {
        guard case .video(let url, _, _) = entry.kind else { return }
        NSWorkspace.shared.open(url)
    }
}
