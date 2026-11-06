import AppKit
import Carbon
import UniformTypeIdentifiers

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var statusMenu: NSMenu!
    private var hotKeyIDs: [UInt32] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = Prefs.shared
        buildMainMenu()

        statusMenu = NSMenu()
        statusMenu.delegate = self
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.menu = statusMenu
        updateStatusButton()

        RecordingController.shared.onStateChange = { [weak self] in self?.updateStatusButton() }
        registerHotKeys()

        let center = NotificationCenter.default
        center.addObserver(forName: ShortcutStore.didChange, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { (NSApp.delegate as? AppDelegate)?.registerHotKeys() }
        }
        // While a shortcut is being recorded, global shortcuts are suspended.
        center.addObserver(forName: ShortcutStore.recordingDidChange, object: nil, queue: .main) { note in
            let recording = note.object as? Bool ?? false
            MainActor.assumeIsolated {
                guard let delegate = NSApp.delegate as? AppDelegate else { return }
                if recording { delegate.unregisterHotKeys() } else { delegate.registerHotKeys() }
            }
        }

        _ = HistoryStore.shared

        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
        }
        Updater.startAutomaticChecks()
    }

    // MARK: Global shortcuts

    private func unregisterHotKeys() {
        for id in hotKeyIDs { HotKeyCenter.shared.unregister(id) }
        hotKeyIDs.removeAll()
    }

    private func registerHotKeys() {
        unregisterHotKeys()
        for action in ShortcutAction.allCases {
            guard let combo = ShortcutStore.combo(for: action) else { continue }
            if let id = HotKeyCenter.shared.register(keyCode: combo.keyCode, modifiers: combo.modifiers, handler: { [weak self] in
                self?.perform(action)
            }) {
                hotKeyIDs.append(id)
            }
        }
    }

    private func perform(_ action: ShortcutAction) {
        switch action {
        case .captureArea: CaptureCoordinator.shared.captureArea()
        case .captureFullscreen: CaptureCoordinator.shared.captureFullscreen()
        case .captureWindow: CaptureCoordinator.shared.captureWindow()
        case .scrollingCapture: ScrollCaptureController.shared.start()
        case .recordVideo: RecordingController.shared.toggle()
        case .history: HistoryWindowController.show()
        }
    }

    // MARK: Menu bar icon

    private func updateStatusButton() {
        guard let button = statusItem?.button else { return }
        let recording = RecordingController.shared.isRecording
        let image = recording
            ? NSImage(systemSymbolName: "stop.circle.fill", accessibilityDescription: "Déclic")
            : Brand.menuBarIcon()
        image?.isTemplate = !recording
        button.image = image
        button.contentTintColor = recording ? .systemRed : nil
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let recording = RecordingController.shared.isRecording

        if recording {
            let stop = add(to: menu, S.stopRecording, "stop.circle.fill", #selector(stopRecording),
                           shortcut: ShortcutStore.combo(for: .recordVideo))
            stop.image = Self.symbol("stop.circle.fill", color: .systemRed)
            menu.addItem(.separator())
        }

        menu.addItem(NSMenuItem.sectionHeader(title: S.sectionCapture))
        addAction(.captureArea, to: menu)
        addAction(.captureFullscreen, to: menu)
        addAction(.captureWindow, to: menu)
        addAction(.scrollingCapture, to: menu)

        if !recording {
            menu.addItem(.separator())
            menu.addItem(NSMenuItem.sectionHeader(title: S.sectionRecord))
            addAction(.recordVideo, to: menu)
        }

        menu.addItem(.separator())
        addAction(.history, to: menu)
        add(to: menu, S.openImage, "pencil.and.outline", #selector(openImage), shortcut: nil)
        add(to: menu, S.openFolder, "folder", #selector(openFolder), shortcut: nil)

        menu.addItem(.separator())
        if Updater.isConfigured {
            add(to: menu, S.checkForUpdates, "arrow.triangle.2.circlepath", #selector(updateApp), shortcut: nil)
        }
        let settings = add(to: menu, S.settings, "gearshape", #selector(openSettings), shortcut: nil)
        settings.keyEquivalent = ","
        settings.keyEquivalentModifierMask = [.command]
        let quit = add(to: menu, S.quit, "power", #selector(quit), shortcut: nil)
        quit.keyEquivalent = "q"
        quit.keyEquivalentModifierMask = [.command]
    }

    private static func symbol(_ name: String, color: NSColor? = nil) -> NSImage? {
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
        guard let color else { return image }
        return image.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [color]))
    }

    private func addAction(_ action: ShortcutAction, to menu: NSMenu) {
        let item = add(to: menu, action.title, action.symbol, #selector(menuAction(_:)),
                       shortcut: ShortcutStore.combo(for: action))
        item.representedObject = action.rawValue
    }

    @discardableResult
    private func add(to menu: NSMenu, _ title: String, _ symbol: String, _ selector: Selector,
                     shortcut: KeyCombo?) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: shortcut?.menuKey ?? "")
        if let shortcut { item.keyEquivalentModifierMask = shortcut.menuModifiers }
        item.target = self
        item.image = Self.symbol(symbol)
        menu.addItem(item)
        return item
    }

    // MARK: Actions

    @objc private func menuAction(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let action = ShortcutAction(rawValue: raw) else { return }
        if action == .history {
            perform(action)
            return
        }
        // Let the menu close before freezing the screen.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            self.perform(action)
        }
    }

    @objc private func stopRecording() { RecordingController.shared.stop(cancel: false) }
    @objc private func closePins() { PinManager.shared.closeAll() }
    @objc private func openSettings() { SettingsWindowController.show() }
    @objc private func updateApp() { Updater.checkNow() }

    @objc private func openImage() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let image = FileUtil.loadImage(url) else {
            showError(S.openFailed, CocoaError(.fileReadCorruptFile))
            return
        }
        EditorWindowController.open(image: image, scale: NSScreen.underMouse.backingScaleFactor)
    }

    @objc private func openFolder() {
        let folder = Prefs.shared.saveFolder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folder)
    }

    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: Main menu (⌘Z, ⌘C, ⌘S… in the editor, ⌘, for settings)

    private func buildMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "Déclic")
        let settings = appMenu.addItem(withTitle: S.settings, action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: S.quit, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: S.menuFile)
        fileMenu.addItem(withTitle: S.close, action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileMenu.addItem(withTitle: S.save, action: Selector(("saveImage:")), keyEquivalent: "s")
        let saveAs = fileMenu.addItem(withTitle: S.saveAs, action: Selector(("saveImageAs:")), keyEquivalent: "s")
        saveAs.keyEquivalentModifierMask = [.command, .shift]
        fileItem.submenu = fileMenu
        main.addItem(fileItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: S.menuEdit)
        editMenu.addItem(withTitle: S.undo, action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: S.redo, action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: S.cut, action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: S.copy, action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: S.paste, action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: S.selectAll, action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        main.addItem(editItem)

        NSApp.mainMenu = main
    }
}
