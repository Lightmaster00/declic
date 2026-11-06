import AppKit
import AVKit
import SwiftUI

/// Content shown in the preview window.
enum PreviewContent {
    case image(CGImage, scale: CGFloat, origin: CGRect?)
    case video(URL, isGIF: Bool)
}

/// Animated GIF (NSImageView animates GIFs natively).
struct AnimatedImageView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.image = NSImage(contentsOf: url)
        view.animates = true
        view.imageScaling = .scaleProportionallyUpOrDown
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return view
    }

    func updateNSView(_ nsView: NSImageView, context: Context) {}
}

@MainActor
final class PreviewModel: ObservableObject {
    let content: PreviewContent
    @Published var toast: String?
    let player: AVPlayer?

    init(content: PreviewContent) {
        self.content = content
        if case .video(let url, let isGIF) = content, !isGIF {
            player = AVPlayer(url: url)
        } else {
            player = nil
        }
    }

    var isImage: Bool {
        if case .image = content { return true }
        return false
    }

    var subtitle: String {
        switch content {
        case .image(let image, _, _): return "\(image.width) × \(image.height) px"
        case .video(_, let isGIF): return isGIF ? "GIF" : "MP4"
        }
    }

    func copy() {
        switch content {
        case .image(let image, let scale, _): Clipboard.copy(image: image, scale: scale)
        case .video(let url, _): Clipboard.copy(fileURL: url)
        }
        flash(S.copied)
    }

    func save() {
        do {
            let url: URL
            switch content {
            case .image(let image, _, _): url = try FileUtil.savePNG(image)
            case .video(let source, let isGIF): url = try FileUtil.saveVideo(source, isGIF: isGIF)
            }
            flash(S.saved(url.lastPathComponent))
        } catch {
            flash(S.error(error.localizedDescription))
        }
    }

    func annotate(closing window: NSWindow?) {
        guard case .image(let image, let scale, _) = content else { return }
        EditorWindowController.open(image: image, scale: scale)
        window?.close()
    }

    func openInDefaultApp() {
        guard case .video(let url, _) = content else { return }
        NSWorkspace.shared.open(url)
    }

    private func flash(_ message: String) {
        toast = message
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            if self?.toast == message { self?.toast = nil }
        }
    }
}

@MainActor
struct PreviewView: View {
    @ObservedObject var model: PreviewModel
    let window: () -> NSWindow?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ZStack {
                Color(nsColor: NSColor(calibratedWhite: 0.1, alpha: 1))
                content
                    .padding(20)
            }
            .overlay(alignment: .bottom) {
                if let toast = model.toast {
                    Label(toast, systemImage: "checkmark.circle.fill")
                        .font(.system(size: 12.5, weight: .medium))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .hudBackground(cornerRadius: 16)
                        .padding(.bottom, 16)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.2), value: model.toast)
        }
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
        .background(
            // Shortcuts: Escape / Space to close, ⌘C to copy.
            ZStack {
                Button("") { window()?.close() }.keyboardShortcut(.escape, modifiers: [])
                Button("") { window()?.close() }.keyboardShortcut(.space, modifiers: [])
                Button("") { model.copy() }.keyboardShortcut("c", modifiers: .command)
            }
            .opacity(0)
        )
    }

    @ViewBuilder
    private var content: some View {
        switch model.content {
        case .image(let image, let scale, _):
            Image(decorative: image, scale: max(scale, 1))
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .shadow(color: .black.opacity(0.5), radius: 16, x: 0, y: 6)
                .onDrag { dragProvider(image) }
        case .video(let url, let isGIF):
            if isGIF {
                AnimatedImageView(url: url)
            } else if let player = model.player {
                VideoPlayer(player: player)
                    .onAppear { player.play() }
                    .onDisappear { player.pause() }
            }
        }
    }

    private func dragProvider(_ image: CGImage) -> NSItemProvider {
        guard let url = try? FileUtil.writeTempImage(image) else { return NSItemProvider() }
        return NSItemProvider(contentsOf: url) ?? NSItemProvider()
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                Text(model.isImage ? S.screenshotPrefix : S.recordingPrefix)
                    .font(.system(size: 13, weight: .semibold))
                Text(model.subtitle)
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 12)

            if model.isImage {
                Button { model.annotate(closing: window()) } label: {
                    Label(S.annotate, systemImage: "pencil.tip.crop.circle")
                }
            } else {
                Button { model.openInDefaultApp() } label: {
                    Label(S.open, systemImage: "arrow.up.forward.app")
                }
            }
            Button { model.copy() } label: {
                Label(S.copy, systemImage: "doc.on.doc")
            }
            Button { model.save() } label: {
                Label(S.save, systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .padding(.leading, 84)
        .padding(.trailing, 14)
        .frame(height: 60)
        .background(WindowDragArea())
        .background(VisualEffectBackground(material: .titlebar))
    }
}

@MainActor
final class PreviewWindowController: NSWindowController, NSWindowDelegate {
    private static var instances: [PreviewWindowController] = []

    static func show(_ content: PreviewContent) {
        let controller = PreviewWindowController(content: content)
        instances.append(controller)
        NSApp.activate(ignoringOtherApps: true)
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    init(content: PreviewContent) {
        let model = PreviewModel(content: content)
        let visible = NSScreen.underMouse.visibleFrame
        var size = CGSize(width: 900, height: 620)
        if case .image(let image, let scale, _) = content {
            let s = max(scale, 1)
            size = CGSize(width: CGFloat(image.width) / s + 40, height: CGFloat(image.height) / s + 40 + 52)
        }
        size.width = min(max(size.width, 640), visible.width * 0.85)
        size.height = min(max(size.height, 420), visible.height * 0.85)

        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self
        window.contentView = NSHostingView(rootView: PreviewView(model: model, window: { [weak window] in window }))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }

    func windowWillClose(_ notification: Notification) {
        PreviewWindowController.instances.removeAll { $0 === self }
    }
}
