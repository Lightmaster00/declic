import AppKit
import AVFoundation
import Carbon
import ImageIO
import ScreenCaptureKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Video stream writer

/// Receives SCStream frames and writes them as MP4 (H.264) with AVAssetWriter.
final class StreamWriter: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let url: URL
    var onUnexpectedStop: (@Sendable () -> Void)?

    private let queue = DispatchQueue(label: "com.lightmaster.declic.recorder")
    private let assetWriter: AVAssetWriter
    private let input: AVAssetWriterInput
    private var stream: SCStream?
    private var sessionStarted = false
    private var lastPTS: CMTime = .invalid
    private var lastArrival: TimeInterval = 0

    init(url: URL, width: Int, height: Int, fps: Int, bitsPerPixel: Double) throws {
        self.url = url
        try? FileManager.default.removeItem(at: url)
        assetWriter = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let bitrate = max(1_500_000, Int(Double(width * height) * bitsPerPixel))
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitrate,
                AVVideoExpectedSourceFrameRateKey: fps,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            ] as [String: Any],
        ]
        input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = true
        super.init()
        guard assetWriter.canAdd(input) else { throw CaptureError.writerSetup }
        assetWriter.add(input)
    }

    func start(filter: SCContentFilter, configuration: SCStreamConfiguration) async throws {
        let s = SCStream(filter: filter, configuration: configuration, delegate: self)
        try s.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        guard assetWriter.startWriting() else { throw assetWriter.error ?? CaptureError.writerSetup }
        stream = s
        try await s.startCapture()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid else { return }
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let rawStatus = attachments.first?[.status] as? Int,
              let status = SCFrameStatus(rawValue: rawStatus),
              status == .complete else { return }

        let pts = sampleBuffer.presentationTimeStamp
        if !sessionStarted {
            assetWriter.startSession(atSourceTime: pts)
            sessionStarted = true
        }
        if input.isReadyForMoreMediaData {
            _ = input.append(sampleBuffer)
            lastPTS = pts
            lastArrival = ProcessInfo.processInfo.systemUptime
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        NSLog("Declic: stream stopped: \(error)")
        onUnexpectedStop?()
    }

    func stop() async throws -> URL {
        if let s = stream {
            stream = nil
            try? await s.stopCapture()
        }
        let finished: Bool = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            queue.async {
                guard self.sessionStarted, self.lastPTS.isValid else {
                    self.assetWriter.cancelWriting()
                    cont.resume(returning: false)
                    return
                }
                // Extends the last frame until stop (a still screen produces no new frames).
                let tail = max(0, ProcessInfo.processInfo.systemUptime - self.lastArrival)
                let end = CMTimeAdd(self.lastPTS, CMTime(seconds: tail, preferredTimescale: 600))
                self.input.markAsFinished()
                self.assetWriter.endSession(atSourceTime: end)
                self.assetWriter.finishWriting { cont.resume(returning: true) }
            }
        }
        guard finished, assetWriter.status == .completed else {
            throw assetWriter.error ?? CaptureError.emptyRecording
        }
        return url
    }
}

// MARK: - GIF

enum GIFExporter {
    static func export(videoURL: URL, to gifURL: URL, fps: Int, maxWidth: Int) async throws {
        let asset = AVURLAsset(url: videoURL)
        let duration = try await asset.load(.duration).seconds
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 60)
        generator.maximumSize = CGSize(width: CGFloat(maxWidth), height: CGFloat(maxWidth) * 4)

        let rate = Double(max(1, fps))
        let count = max(1, Int((duration * rate).rounded(.down)))
        guard let dest = CGImageDestinationCreateWithURL(gifURL as CFURL, UTType.gif.identifier as CFString, count, nil) else {
            throw CaptureError.gifExport
        }
        let fileProps = [kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFLoopCount as String: 0]]
        CGImageDestinationSetProperties(dest, fileProps as CFDictionary)
        let frameProps = [kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFDelayTime as String: 1.0 / rate]]

        for i in 0..<count {
            let time = CMTime(seconds: Double(i) / rate, preferredTimescale: 600)
            let frame = try await generator.image(at: time)
            CGImageDestinationAddImage(dest, frame.image, frameProps as CFDictionary)
        }
        guard CGImageDestinationFinalize(dest) else { throw CaptureError.gifExport }
    }
}

// MARK: - Mode bar (area / full screen / app)

final class RecordingHUDModel: ObservableObject {
    @Published var format: RecordingFormat = .mp4
    @Published var mode: RecordModeChoice = .area
    @Published var ready = false
}

@MainActor
struct RecordingHUDView: View {
    @ObservedObject var model: RecordingHUDModel
    let onMode: (RecordModeChoice) -> Void
    let onRecord: () -> Void
    let onClose: () -> Void

    @AppStorage(PrefKey.recCountdown) private var countdown = 0
    @AppStorage(PrefKey.recCursor) private var cursor = true
    @AppStorage(PrefKey.showClicks) private var clicks = true

    var body: some View {
        HStack(spacing: 12) {
            HUDIconButton(symbol: "xmark", help: "\(S.cancel) (Esc)", action: onClose)

            GlassSegmented<RecordModeChoice>(
                items: [
                    .init(value: .area, title: S.modeArea, symbol: "rectangle.dashed"),
                    .init(value: .fullscreen, title: S.modeFullscreen, symbol: "display"),
                    .init(value: .window, title: S.modeApp, symbol: "macwindow"),
                ],
                selection: model.mode,
                onSelect: onMode
            )

            GlassSegmented<RecordingFormat>(
                items: [
                    .init(value: .mp4, title: S.video),
                    .init(value: .gif, title: "GIF"),
                ],
                selection: model.format,
                onSelect: { model.format = $0 }
            )

            Menu {
                Picker(S.countdown, selection: $countdown) {
                    Text(S.none).tag(0)
                    Text(S.seconds(3)).tag(3)
                    Text(S.seconds(5)).tag(5)
                }
                Toggle(S.showCursor, isOn: $cursor)
                Toggle(S.showClicks, isOn: $clicks)
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 14, weight: .semibold))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .frame(width: 32, height: 32)
            .background(GlassFill(shape: Circle()))
            .help(S.options)

            HUDTextButton(title: S.record, symbol: "record.circle", color: .red, enabled: model.ready, action: onRecord)
                .help("\(S.record) (↩)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .hudBackground(cornerRadius: 20)
        .padding(18)
    }
}

// MARK: - Countdown

final class CountdownModel: ObservableObject {
    @Published var value = 3
}

struct CountdownView: View {
    @ObservedObject var model: CountdownModel

    var body: some View {
        Text("\(model.value)")
            .font(.system(size: 54, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundColor(.white)
            .frame(width: 110, height: 110)
            .hudBackground(cornerRadius: 55)
            .id(model.value)
            .transition(.scale(scale: 1.25).combined(with: .opacity))
            .animation(.easeOut(duration: 0.25), value: model.value)
            .padding(14)
    }
}

// MARK: - Badge while recording

final class RecordingTimerModel: ObservableObject {
    @Published var elapsed: TimeInterval = 0
    @Published var processing = false
}

struct RecordingControlView: View {
    @ObservedObject var model: RecordingTimerModel
    let isGIF: Bool
    let onStop: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            if model.processing {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
                Text(S.converting)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.trailing, 4)
            } else {
                PulsingDot()
                Text(timeString)
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundColor(.white)
                    .frame(minWidth: 38, alignment: .leading)
                if isGIF {
                    Text("GIF")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1.5)
                        .background(RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.9)))
                }
                HUDTextButton(title: S.stop, symbol: "stop.fill", color: .red, action: onStop)
                HUDIconButton(symbol: "xmark", help: S.cancel, action: onCancel)
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .hudBackground(cornerRadius: 19)
        .padding(14)
    }

    private var timeString: String {
        let s = Int(model.elapsed)
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
}

final class RecordingBorderView: NSView {
    var color: NSColor = .systemRed

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 1.5, dy: 1.5)
        let shadowPath = NSBezierPath(rect: r)
        shadowPath.lineWidth = 3
        NSColor.black.withAlphaComponent(0.25).setStroke()
        shadowPath.stroke()
        let path = NSBezierPath(rect: r)
        path.lineWidth = 1.5
        path.setLineDash([6, 4], count: 2, phase: 0)
        color.setStroke()
        path.stroke()
    }
}

/// Transparent window drawing a dashed frame around an area.
@MainActor
func makeBorderWindow(around rect: CGRect, color: NSColor) -> NSWindow {
    let frame = rect.insetBy(dx: -3, dy: -3)
    let border = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
    border.isOpaque = false
    border.backgroundColor = .clear
    border.hasShadow = false
    border.ignoresMouseEvents = true
    border.level = .statusBar
    border.isReleasedWhenClosed = false
    border.collectionBehavior = [.canJoinAllSpaces, .stationary]
    let view = RecordingBorderView(frame: CGRect(origin: .zero, size: frame.size))
    view.color = color
    border.contentView = view
    border.orderFrontRegardless()
    return border
}

// MARK: - Controller

@MainActor
final class RecordingController {
    static let shared = RecordingController()

    enum Target {
        case area(AreaResult)
        case screen(NSScreen)
        case window(WindowCandidate)

        var screenRect: CGRect {
            switch self {
            case .area(let a): return a.screenRect
            case .screen(let s): return s.frame
            case .window(let w): return w.frame
            }
        }
    }

    var onStateChange: (() -> Void)?
    private(set) var isRecording = false
    private var starting = false

    // Target selection
    private let hudModel = RecordingHUDModel()
    private var hudPanel: FloatingPanel?
    private var hudScreen: NSScreen?
    private var hudKeys: [UInt32?] = []
    private var areaPicker: RecordAreaPicker?
    private var windowHighlight: NSWindow?
    private var pickingWindow = false
    private var lastArea: AreaResult?
    private var target: Target?

    // Recording
    private var writer: StreamWriter?
    private var format: RecordingFormat = .mp4
    private var controlPanel: FloatingPanel?
    private var borderWindow: NSWindow?
    private var timer: Timer?
    private var startDate = Date()
    private let timerModel = RecordingTimerModel()

    var isChoosing: Bool { hudPanel != nil }

    /// Recording shortcut: opens the mode bar, closes it, or stops the recording.
    func toggle() {
        if isRecording {
            stop(cancel: false)
        } else if pickingWindow {
            // The shortcut closes everything, even while a window is being picked.
            pickingWindow = false
            MissionControlPicker.shared.cancel()
            closeChooser()
        } else if hudPanel != nil {
            closeChooser()
        } else if !starting {
            openChooser()
        }
    }

    // MARK: Mode bar

    private func openChooser() {
        hudModel.format = Prefs.shared.recLastFormat
        let screen = NSScreen.underMouse
        hudScreen = screen

        let view = RecordingHUDView(
            model: hudModel,
            onMode: { [weak self] mode in self?.activate(mode) },
            onRecord: { [weak self] in self?.startRecording() },
            onClose: { [weak self] in self?.closeChooser() }
        )
        let host = FirstMouseHostingView(rootView: view)
        let size = host.fittingSize
        host.frame = CGRect(origin: .zero, size: size)
        let panel = FloatingPanel(size: size)
        panel.level = .aboveOverlay
        panel.contentView = host
        let vf = screen.visibleFrame
        let frame = CGRect(x: vf.midX - size.width / 2, y: vf.minY + 36, width: size.width, height: size.height)
        panel.setFrame(frame.offsetBy(dx: 0, dy: -16), display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
            panel.animator().setFrame(frame, display: true)
            panel.animator().alphaValue = 1
        }
        hudPanel = panel

        registerHUDKeys()
        // App mode is never reopened automatically (the window is picked every time).
        let last = Prefs.shared.recLastMode
        activate(last == .window ? .area : last)
    }

    private func registerHUDKeys() {
        unregisterHUDKeys()
        hudKeys = [
            HotKeyCenter.shared.register(keyCode: kVK_Escape, modifiers: 0) { [weak self] in self?.back() },
            HotKeyCenter.shared.register(keyCode: kVK_Return, modifiers: 0) { [weak self] in self?.startRecording() },
        ]
    }

    private func unregisterHUDKeys() {
        for key in hudKeys { HotKeyCenter.shared.unregister(key) }
        hudKeys = []
    }

    /// Switches mode at any time (going back is always possible).
    private func activate(_ mode: RecordModeChoice) {
        closePickers()
        target = nil
        hudModel.mode = mode
        hudModel.ready = false
        Prefs.shared.recLastMode = mode
        // The bar stays above the overlays.
        defer { if !pickingWindow { hudPanel?.orderFrontRegardless() } }

        switch mode {
        case .area:
            let picker = RecordAreaPicker(initial: lastArea)
            picker.onChange = { [weak self] area in
                guard let self else { return }
                if let area { self.lastArea = area }
                self.target = area.map { .area($0) }
                self.hudModel.ready = self.target != nil
            }
            picker.onConfirm = { [weak self] in self?.startRecording() }
            areaPicker = picker
            if let current = picker.current {
                target = .area(current)
                hudModel.ready = true
            }

        case .fullscreen:
            target = .screen(hudScreen ?? NSScreen.underMouse)
            hudModel.ready = true

        case .window:
            chooseWindowInMissionControl()
        }
    }

    /// App mode: the window is picked in the window gallery.
    private func chooseWindowInMissionControl() {
        windowHighlight?.orderOut(nil)
        windowHighlight = nil
        pickingWindow = true
        unregisterHUDKeys()
        hudPanel?.orderOut(nil)
        MissionControlPicker.shared.pick { [weak self] candidate in
            guard let self else { return }
            self.pickingWindow = false
            guard let panel = self.hudPanel, self.hudModel.mode == .window else { return }
            if let candidate {
                // Window picked: it comes to the front, then recording starts
                // right away (after the countdown).
                self.target = .window(candidate)
                self.hudModel.ready = true
                WindowRaiser.raise(candidate)
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    self.startRecording()
                }
            } else {
                // Picking cancelled: back to the bar, in Area mode.
                panel.orderFrontRegardless()
                self.registerHUDKeys()
                self.activate(.area)
            }
        }
    }

    /// Escape: cancels the current selection, otherwise closes the bar.
    private func back() {
        if let picker = areaPicker, picker.clearSelection() {
            target = nil
            hudModel.ready = false
            return
        }
        if windowHighlight != nil {
            closePickers()
            target = nil
            hudModel.ready = false
            return
        }
        closeChooser()
    }

    private func closePickers() {
        areaPicker?.close()
        areaPicker = nil
        windowHighlight?.orderOut(nil)
        windowHighlight = nil
    }

    private func closeChooser() {
        closePickers()
        unregisterHUDKeys()
        hudPanel?.orderOut(nil)
        hudPanel = nil
        target = nil
    }

    private func startRecording() {
        guard let target, hudPanel != nil else { return }
        format = hudModel.format
        Prefs.shared.recLastFormat = format
        closeChooser()
        starting = true
        Task {
            await self.countdown(over: target.screenRect)
            await self.begin(target)
            self.starting = false
        }
    }

    private func countdown(over rect: CGRect) async {
        let seconds = Prefs.shared.recCountdown
        guard seconds > 0 else { return }
        let model = CountdownModel()
        model.value = seconds
        let host = FirstMouseHostingView(rootView: CountdownView(model: model))
        let size = host.fittingSize
        host.frame = CGRect(origin: .zero, size: size)
        let panel = FloatingPanel(size: size)
        panel.level = .aboveOverlay
        panel.ignoresMouseEvents = true
        panel.contentView = host
        panel.setFrameOrigin(CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2))
        panel.orderFrontRegardless()
        for value in stride(from: seconds, to: 0, by: -1) {
            model.value = value
            Sound.tick()
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        panel.orderOut(nil)
    }

    // MARK: Start / stop

    private func begin(_ target: Target) async {
        do {
            let prefs = Prefs.shared
            let content = try await Capturer.content()
            let filter: SCContentFilter
            var source: CGRect?
            var border: CGRect?
            let screen: NSScreen

            switch target {
            case .area(let area):
                guard let display = Capturer.display(for: area.shot.screen, in: content) else { throw CaptureError.noDisplay }
                filter = Capturer.displayFilter(display, content: content)
                if !area.isFullScreen {
                    source = area.displayRect
                    border = area.screenRect
                }
                screen = area.shot.screen
            case .screen(let s):
                guard let display = Capturer.display(for: s, in: content) else { throw CaptureError.noDisplay }
                filter = Capturer.displayFilter(display, content: content)
                screen = s
            case .window(let candidate):
                // The window is followed even when moved or covered by another one.
                filter = SCContentFilter(desktopIndependentWindow: candidate.window)
                screen = NSScreen.best(for: candidate.frame)
            }

            let scale = CGFloat(filter.pointPixelScale)
            let pointSize = source?.size ?? filter.contentRect.size
            var pixelWidth = pointSize.width * scale
            var pixelHeight = pointSize.height * scale
            let maxDimension: CGFloat = 3840 // comfortable limit for H.264
            if max(pixelWidth, pixelHeight) > maxDimension {
                let f = maxDimension / max(pixelWidth, pixelHeight)
                pixelWidth *= f
                pixelHeight *= f
            }

            let fps = prefs.recFPS
            let config = SCStreamConfiguration()
            if let source { config.sourceRect = source }
            config.width = Self.even(pixelWidth)
            config.height = Self.even(pixelHeight)
            config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
            config.showsCursor = prefs.recCursor
            config.pixelFormat = kCVPixelFormatType_32BGRA
            config.queueDepth = 6
            if case .window = target { config.ignoreShadowsSingleWindow = true }
            if #available(macOS 15.0, *) {
                config.showMouseClicks = prefs.showClicks
            }

            let url = FileUtil.newTempFolder().appendingPathComponent("\(S.recordingPrefix) \(FileUtil.timestamp()).mp4")
            let writer = try StreamWriter(url: url, width: config.width, height: config.height, fps: fps,
                                          bitsPerPixel: prefs.recQuality == .high ? 5 : 2.5)
            writer.onUnexpectedStop = {
                Task { @MainActor in RecordingController.shared.stop(cancel: false) }
            }
            try await writer.start(filter: filter, configuration: config)

            self.writer = writer
            isRecording = true
            startDate = Date()
            showRecordingUI(screen: screen, border: border)
            onStateChange?()
        } catch {
            Capturer.presentError(error)
        }
    }

    func stop(cancel: Bool) {
        guard isRecording, let writer else { return }
        isRecording = false
        self.writer = nil
        timer?.invalidate()
        timer = nil
        borderWindow?.orderOut(nil)
        borderWindow = nil
        onStateChange?()
        let format = self.format
        let prefs = Prefs.shared

        if format == .gif && !cancel {
            timerModel.processing = true
        } else {
            hideControlPanel()
        }

        Task {
            do {
                let mp4 = try await writer.stop()
                if cancel {
                    try? FileManager.default.removeItem(at: mp4)
                    return
                }
                var output = mp4
                let isGIF = format == .gif
                if isGIF {
                    let gif = mp4.deletingPathExtension().appendingPathExtension("gif")
                    try await GIFExporter.export(videoURL: mp4, to: gif, fps: prefs.gifFPS, maxWidth: prefs.gifWidth)
                    try? FileManager.default.removeItem(at: mp4)
                    output = gif
                }
                self.hideControlPanel()
                Sound.shutter()
                HistoryStore.shared.addVideo(output, isGIF: isGIF)
                if prefs.recAfterCopy { Clipboard.copy(fileURL: output) }
                if prefs.recAfterSave {
                    do { try FileUtil.saveVideo(output, isGIF: isGIF) } catch { showError(S.saveFailed, error) }
                }
                if prefs.recAfterQuickAccess {
                    let thumbnail = await FileUtil.thumbnail(for: output, isGIF: isGIF)
                    QuickAccessManager.shared.show(.video(output, isGIF: isGIF, thumbnail: thumbnail))
                }
            } catch {
                self.hideControlPanel()
                if !cancel { showError(S.recordingFailed, error) }
            }
        }
    }

    private static func even(_ value: CGFloat) -> Int {
        max(2, Int(value) & ~1)
    }

    // MARK: Interface

    private func showRecordingUI(screen: NSScreen, border: CGRect?) {
        if let border {
            borderWindow = makeBorderWindow(around: border, color: .systemRed)
        }

        timerModel.elapsed = 0
        timerModel.processing = false
        let view = RecordingControlView(
            model: timerModel,
            isGIF: format == .gif,
            onStop: { [weak self] in self?.stop(cancel: false) },
            onCancel: { [weak self] in self?.stop(cancel: true) }
        )
        let host = FirstMouseHostingView(rootView: view)
        let size = host.fittingSize
        let panel = FloatingPanel(size: CGSize(width: size.width + 120, height: size.height))
        panel.level = .statusBar
        host.frame = CGRect(origin: .zero, size: panel.frame.size)
        panel.contentView = host
        let vf = screen.visibleFrame
        panel.setFrameOrigin(CGPoint(x: vf.midX - panel.frame.width / 2, y: vf.minY + 12))
        panel.orderFrontRegardless()
        controlPanel = panel

        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            MainActor.assumeIsolated {
                let controller = RecordingController.shared
                controller.timerModel.elapsed = Date().timeIntervalSince(controller.startDate)
            }
        }
    }

    private func hideControlPanel() {
        controlPanel?.orderOut(nil)
        controlPanel = nil
        timerModel.processing = false
    }
}
