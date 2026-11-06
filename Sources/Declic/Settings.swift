import AppKit
import ServiceManagement
import SwiftUI

// MARK: - Settings window (tabs in the toolbar)

@MainActor
final class SettingsWindowController: NSWindowController {
    private static var shared: SettingsWindowController?

    static func show() {
        if shared == nil {
            let tabs = NSTabViewController()
            tabs.tabStyle = .toolbar
            tabs.canPropagateSelectedChildViewControllerTitle = true
            func add<V: View>(_ title: String, _ symbol: String, _ view: V) {
                let controller = NSHostingController(rootView: view.frame(width: 560))
                controller.sizingOptions = .preferredContentSize
                controller.title = title
                let item = NSTabViewItem(viewController: controller)
                item.label = title
                item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
                tabs.addTabViewItem(item)
            }
            add(S.tabGeneral, "gearshape", GeneralSettings())
            add(S.tabCaptures, "camera.viewfinder", CaptureSettings())
            add(S.tabQuickAccess, "rectangle.stack", QuickAccessSettings())
            add(S.tabRecording, "record.circle", RecordingSettings())
            add(S.tabShortcuts, "command", ShortcutSettings())
            add(S.tabHistory, "clock.arrow.circlepath", HistorySettings())
            add(S.tabAbout, "info.circle", AboutSettings())

            let window = NSWindow(contentViewController: tabs)
            window.styleMask = [.titled, .closable]
            window.toolbarStyle = .preference
            window.isReleasedWhenClosed = false
            window.center()
            shared = SettingsWindowController(window: window)
        }
        NSApp.activate(ignoringOtherApps: true)
        shared?.showWindow(nil)
        shared?.window?.makeKeyAndOrderFront(nil)
    }
}

// MARK: - General

@MainActor
struct GeneralSettings: View {
    @AppStorage(PrefKey.playSound) private var playSound = true
    @AppStorage(PrefKey.filePrefix) private var filePrefix = ""
    @AppStorage(PrefKey.afterQuickAccess) private var afterQuickAccess = true
    @AppStorage(PrefKey.afterCopy) private var afterCopy = false
    @AppStorage(PrefKey.afterSave) private var afterSave = false
    @AppStorage(PrefKey.afterAnnotate) private var afterAnnotate = false
    @AppStorage(PrefKey.recAfterQuickAccess) private var recAfterQuickAccess = true
    @AppStorage(PrefKey.recAfterCopy) private var recAfterCopy = false
    @AppStorage(PrefKey.recAfterSave) private var recAfterSave = false
    @AppStorage(PrefKey.autoCheckUpdates) private var autoCheckUpdates = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var folder = URL(fileURLWithPath: NSHomeDirectory())

    var body: some View {
        Form {
            Section {
                Toggle(S.launchAtLogin, isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, value in
                        do {
                            if value { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                            showError(S.launchAtLogin, error)
                        }
                    }
                Toggle(S.playSound, isOn: $playSound)
                if Updater.isConfigured {
                    LabeledContent(S.autoCheckUpdates) {
                        HStack(spacing: 10) {
                            Button(S.checkNow) { Updater.checkNow() }
                            Toggle("", isOn: $autoCheckUpdates).labelsHidden()
                        }
                    }
                }
            }

            Section(S.exportSection) {
                LabeledContent(S.exportLocation) {
                    HStack(spacing: 8) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: folder.path))
                            .resizable()
                            .frame(width: 16, height: 16)
                        Text(folder.lastPathComponent)
                            .lineLimit(1)
                        Button(S.change) { chooseFolder() }
                    }
                }
                TextField(S.filePrefixLabel, text: $filePrefix, prompt: Text(S.screenshotPrefix))
            }

            Section(S.afterScreenshot) {
                Toggle(S.showQuickAccess, isOn: $afterQuickAccess)
                Toggle(S.copyToClipboard, isOn: $afterCopy)
                Toggle(S.saveToFolder, isOn: $afterSave)
                Toggle(S.openAnnotate, isOn: $afterAnnotate)
            }

            Section(S.afterRecording) {
                Toggle(S.showQuickAccess, isOn: $recAfterQuickAccess)
                Toggle(S.copyFileToClipboard, isOn: $recAfterCopy)
                Toggle(S.saveToFolder, isOn: $recAfterSave)
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { folder = Prefs.shared.saveFolder }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = S.choose
        panel.directoryURL = folder
        if panel.runModal() == .OK, let url = panel.url {
            Prefs.shared.saveFolder = url
            folder = url
        }
    }
}

// MARK: - Captures

@MainActor
struct CaptureSettings: View {
    @AppStorage(PrefKey.imageFormat) private var format = ImageFormat.png.rawValue
    @AppStorage(PrefKey.jpegQuality) private var quality = 0.9
    @AppStorage(PrefKey.scaleTo1x) private var scaleTo1x = false
    @AppStorage(PrefKey.freezeScreen) private var freeze = false
    @AppStorage(PrefKey.showMagnifier) private var magnifier = true
    @AppStorage(PrefKey.showCrosshair) private var crosshair = false
    @AppStorage(PrefKey.hideDesktopIcons) private var hideIcons = false
    @AppStorage(PrefKey.windowShadow) private var shadow = true
    @AppStorage(PrefKey.windowBackground) private var background = WindowBackground.transparent.rawValue
    @AppStorage(PrefKey.windowPadding) private var padding = 40.0
    @AppStorage(PrefKey.windowColor) private var colorHex = "#5B5BD6"

    var body: some View {
        Form {
            Section(S.fileSection) {
                Picker(S.fileFormat, selection: $format) {
                    ForEach(ImageFormat.allCases) { Text($0.title).tag($0.rawValue) }
                }
                if format != ImageFormat.png.rawValue {
                    LabeledContent(S.quality) {
                        HStack {
                            Slider(value: $quality, in: 0.3...1)
                            Text("\(Int(quality * 100)) %")
                                .monospacedDigit()
                                .frame(width: 44, alignment: .trailing)
                        }
                    }
                }
                Toggle(isOn: $scaleTo1x) {
                    Text(S.scaleTo1x)
                    Text(S.scaleTo1xHelp)
                }
            }

            Section(S.areaSection) {
                Toggle(S.freezeScreen, isOn: $freeze)
                Toggle(S.showMagnifier, isOn: $magnifier)
                Toggle(S.showCrosshair, isOn: $crosshair)
                Toggle(isOn: $hideIcons) {
                    Text(S.hideDesktopIcons)
                    Text(S.hideDesktopIconsHelp)
                }
            }

            Section(S.windowSection) {
                Toggle(S.windowShadow, isOn: $shadow)
                Picker(S.windowBackgroundLabel, selection: $background) {
                    Text(S.bgTransparent).tag(WindowBackground.transparent.rawValue)
                    Text(S.bgWhite).tag(WindowBackground.white.rawValue)
                    Text(S.bgLight).tag(WindowBackground.light.rawValue)
                    Text(S.bgDark).tag(WindowBackground.dark.rawValue)
                    Text(S.bgCustom).tag(WindowBackground.custom.rawValue)
                }
                if background == WindowBackground.custom.rawValue {
                    ColorPicker(S.bgColor, selection: Binding(
                        get: { Color(nsColor: NSColor(hex: colorHex) ?? .systemIndigo) },
                        set: { colorHex = NSColor($0).hexString }
                    ), supportsOpacity: false)
                }
                if background != WindowBackground.transparent.rawValue {
                    LabeledContent(S.padding) {
                        HStack {
                            Slider(value: $padding, in: 0...150, step: 5)
                            Text("\(Int(padding)) pt")
                                .monospacedDigit()
                                .frame(width: 48, alignment: .trailing)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Quick Access

@MainActor
struct QuickAccessSettings: View {
    @AppStorage(PrefKey.qaPosition) private var position = QuickAccessPosition.bottomLeft.rawValue
    @AppStorage(PrefKey.qaSize) private var size = QuickAccessSize.medium.rawValue
    @AppStorage(PrefKey.qaAutoClose) private var autoClose = 0

    var body: some View {
        Form {
            Section {
                Picker(S.position, selection: $position) {
                    Text(S.bottomLeft).tag(QuickAccessPosition.bottomLeft.rawValue)
                    Text(S.bottomRight).tag(QuickAccessPosition.bottomRight.rawValue)
                }
                .pickerStyle(.segmented)
                Picker(S.overlaySize, selection: $size) {
                    Text(S.sizeSmall).tag(QuickAccessSize.small.rawValue)
                    Text(S.sizeMedium).tag(QuickAccessSize.medium.rawValue)
                    Text(S.sizeLarge).tag(QuickAccessSize.large.rawValue)
                }
                .pickerStyle(.segmented)
            }
            Section {
                Picker(S.autoClose, selection: $autoClose) {
                    Text(S.never).tag(0)
                    Text(S.seconds(5)).tag(5)
                    Text(S.seconds(10)).tag(10)
                    Text(S.seconds(30)).tag(30)
                    Text(S.seconds(60)).tag(60)
                }
            } footer: {
                Text(S.autoCloseHelp)
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Recording

@MainActor
struct RecordingSettings: View {
    @AppStorage(PrefKey.recFPS) private var fps = 60
    @AppStorage(PrefKey.recQuality) private var quality = VideoQuality.high.rawValue
    @AppStorage(PrefKey.recCursor) private var cursor = true
    @AppStorage(PrefKey.showClicks) private var clicks = true
    @AppStorage(PrefKey.recCountdown) private var countdown = 0
    @AppStorage(PrefKey.gifFPS) private var gifFPS = 15
    @AppStorage(PrefKey.gifWidth) private var gifWidth = 960

    var body: some View {
        Form {
            Section(S.videoSection) {
                Picker(S.frameRate, selection: $fps) {
                    Text("30 fps").tag(30)
                    Text("60 fps").tag(60)
                }
                .pickerStyle(.segmented)
                Picker(S.quality, selection: $quality) {
                    Text(S.qualityStandard).tag(VideoQuality.standard.rawValue)
                    Text(S.qualityHigh).tag(VideoQuality.high.rawValue)
                }
                .pickerStyle(.segmented)
                Toggle(S.showCursor, isOn: $cursor)
                Toggle(isOn: $clicks) {
                    Text(S.showClicks)
                    if #available(macOS 15.0, *) {
                        EmptyView()
                    } else {
                        Text(S.requiresMacOS15)
                    }
                }
                Picker(S.countdown, selection: $countdown) {
                    Text(S.none).tag(0)
                    Text(S.seconds(3)).tag(3)
                    Text(S.seconds(5)).tag(5)
                }
            }
            Section("GIF") {
                Picker(S.frameRate, selection: $gifFPS) {
                    Text("10 fps").tag(10)
                    Text("15 fps").tag(15)
                    Text("20 fps").tag(20)
                    Text("25 fps").tag(25)
                }
                Picker(S.maxWidth, selection: $gifWidth) {
                    Text("640 px").tag(640)
                    Text("960 px").tag(960)
                    Text("1280 px").tag(1280)
                    Text("1600 px").tag(1600)
                }
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Shortcuts

@MainActor
struct ShortcutSettings: View {
    var body: some View {
        Form {
            Section {
                ForEach(ShortcutAction.allCases) { action in
                    LabeledContent {
                        ShortcutRecorder(action: action)
                    } label: {
                        Label(action.title, systemImage: action.symbol)
                    }
                }
            } footer: {
                HStack {
                    Text(S.shortcutsHelp)
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button(S.restoreDefaults) { ShortcutStore.resetAll() }
                }
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - History

@MainActor
struct HistorySettings: View {
    @AppStorage(PrefKey.historyEnabled) private var enabled = true
    @AppStorage(PrefKey.historyDays) private var days = 30
    @State private var confirmClear = false

    var body: some View {
        Form {
            Section {
                Toggle(S.keepHistory, isOn: $enabled)
                Picker(S.keepFor, selection: $days) {
                    Text(S.days(1)).tag(1)
                    Text(S.days(7)).tag(7)
                    Text(S.days(30)).tag(30)
                    Text(S.forever).tag(0)
                }
                .disabled(!enabled)
                .onChange(of: days) { HistoryStore.shared.prune() }
            }
            Section {
                HStack {
                    Button(S.openHistory) { HistoryWindowController.show() }
                    Spacer()
                    Button(S.clearHistory, role: .destructive) { confirmClear = true }
                }
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
        .alert(S.clearHistoryConfirm, isPresented: $confirmClear) {
            Button(S.clearHistory, role: .destructive) { HistoryStore.shared.clear() }
            Button(S.cancel, role: .cancel) {}
        }
    }
}

// MARK: - About

@MainActor
struct AboutSettings: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 84, height: 84)
            Text("Déclic")
                .font(.system(size: 22, weight: .bold, design: .rounded))
            Text(S.tagline)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Brand.coral)
            Text("\(S.version) \(version)")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Text(S.aboutText)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
        .padding(.vertical, 36)
        .frame(maxWidth: .infinity)
    }
}
