import AppKit
import Carbon
import Combine
import SwiftUI

/// Actions accessibles par raccourci global.
enum ShortcutAction: String, CaseIterable, Identifiable {
    case captureArea, captureFullscreen, captureWindow, scrollingCapture, recordVideo, history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .captureArea: return S.captureArea
        case .captureFullscreen: return S.captureFullscreen
        case .captureWindow: return S.captureWindow
        case .scrollingCapture: return S.scrollingCapture
        case .recordVideo: return S.recordScreen
        case .history: return S.history
        }
    }

    var symbol: String {
        switch self {
        case .captureArea: return "rectangle.dashed"
        case .captureFullscreen: return "display"
        case .captureWindow: return "macwindow"
        case .scrollingCapture: return "arrow.up.and.down.text.horizontal"
        case .recordVideo: return "record.circle"
        case .history: return "clock.arrow.circlepath"
        }
    }

    var defaultCombo: KeyCombo? {
        let mods = optionKey | shiftKey
        switch self {
        case .captureFullscreen: return KeyCombo(keyCode: kVK_ANSI_3, modifiers: mods)
        case .captureArea: return KeyCombo(keyCode: kVK_ANSI_4, modifiers: mods)
        case .captureWindow: return KeyCombo(keyCode: kVK_ANSI_5, modifiers: mods)
        case .recordVideo: return KeyCombo(keyCode: kVK_ANSI_6, modifiers: mods)
        case .scrollingCapture: return KeyCombo(keyCode: kVK_ANSI_8, modifiers: mods)
        case .history: return KeyCombo(keyCode: kVK_ANSI_H, modifiers: mods)
        }
    }
}

/// Combinaison de touches (code de touche + modificateurs Carbon).
struct KeyCombo: Equatable {
    var keyCode: Int
    var modifiers: Int

    var display: String {
        var s = ""
        if modifiers & controlKey != 0 { s += "⌃" }
        if modifiers & optionKey != 0 { s += "⌥" }
        if modifiers & shiftKey != 0 { s += "⇧" }
        if modifiers & cmdKey != 0 { s += "⌘" }
        return s + KeyNames.name(for: keyCode)
    }

    /// Caractère utilisable comme équivalent clavier de menu (nil pour les touches spéciales).
    var menuKey: String? {
        let n = KeyNames.name(for: keyCode)
        guard n.count == 1 else { return nil }
        return n.lowercased()
    }

    var menuModifiers: NSEvent.ModifierFlags {
        var f: NSEvent.ModifierFlags = []
        if modifiers & controlKey != 0 { f.insert(.control) }
        if modifiers & optionKey != 0 { f.insert(.option) }
        if modifiers & shiftKey != 0 { f.insert(.shift) }
        if modifiers & cmdKey != 0 { f.insert(.command) }
        return f
    }

    var stored: String { "\(keyCode):\(modifiers)" }

    init(keyCode: Int, modifiers: Int) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    init?(stored: String) {
        let parts = stored.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        self.init(keyCode: parts[0], modifiers: parts[1])
    }

    static func from(event: NSEvent) -> KeyCombo? {
        let flags = event.modifierFlags
        var mods = 0
        if flags.contains(.control) { mods |= controlKey }
        if flags.contains(.option) { mods |= optionKey }
        if flags.contains(.shift) { mods |= shiftKey }
        if flags.contains(.command) { mods |= cmdKey }
        let code = Int(event.keyCode)
        // Une touche de fonction peut se passer de modificateur ; les autres non.
        if mods == 0 && !KeyNames.isFunctionKey(code) { return nil }
        return KeyCombo(keyCode: code, modifiers: mods)
    }
}

enum KeyNames {
    private static let table: [Int: String] = [
        kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D", kVK_ANSI_E: "E",
        kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H", kVK_ANSI_I: "I", kVK_ANSI_J: "J",
        kVK_ANSI_K: "K", kVK_ANSI_L: "L", kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O",
        kVK_ANSI_P: "P", kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
        kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X", kVK_ANSI_Y: "Y",
        kVK_ANSI_Z: "Z",
        kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3", kVK_ANSI_4: "4",
        kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7", kVK_ANSI_8: "8", kVK_ANSI_9: "9",
        kVK_ANSI_Minus: "-", kVK_ANSI_Equal: "=", kVK_ANSI_LeftBracket: "[", kVK_ANSI_RightBracket: "]",
        kVK_ANSI_Semicolon: ";", kVK_ANSI_Quote: "'", kVK_ANSI_Backslash: "\\", kVK_ANSI_Comma: ",",
        kVK_ANSI_Period: ".", kVK_ANSI_Slash: "/", kVK_ANSI_Grave: "`",
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16",
    ]

    private static let functionKeys: Set<Int> = [
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
        kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16,
    ]

    static func name(for keyCode: Int) -> String { table[keyCode] ?? "#\(keyCode)" }
    static func isFunctionKey(_ keyCode: Int) -> Bool { functionKeys.contains(keyCode) }
}

/// Stockage des raccourcis : absent = valeur par défaut, chaîne vide = aucun raccourci.
@MainActor
enum ShortcutStore {
    static let didChange = Notification.Name("DeclicShortcutsDidChange")
    static let recordingDidChange = Notification.Name("DeclicShortcutRecording")

    private static func key(_ action: ShortcutAction) -> String { "shortcut.\(action.rawValue)" }

    static func combo(for action: ShortcutAction) -> KeyCombo? {
        guard let stored = UserDefaults.standard.string(forKey: key(action)) else { return action.defaultCombo }
        return KeyCombo(stored: stored)
    }

    static func set(_ combo: KeyCombo?, for action: ShortcutAction) {
        UserDefaults.standard.set(combo?.stored ?? "", forKey: key(action))
        NotificationCenter.default.post(name: didChange, object: nil)
    }

    static func resetAll() {
        for action in ShortcutAction.allCases {
            UserDefaults.standard.removeObject(forKey: key(action))
        }
        NotificationCenter.default.post(name: didChange, object: nil)
    }
}

/// Champ d'enregistrement d'un raccourci (cliquer puis taper la combinaison).
@MainActor
struct ShortcutRecorder: View {
    let action: ShortcutAction
    @State private var combo: KeyCombo?
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 6) {
            Button {
                recording ? stop() : start()
            } label: {
                Text(recording ? S.typeShortcut : (combo?.display ?? S.none))
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundColor(recording ? Color.accentColor : (combo == nil ? Color.secondary : Color.primary))
                    .frame(minWidth: 120)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(recording ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)

            Button {
                stop()
                update(nil)
            } label: {
                Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(combo == nil ? 0 : 1)
            .disabled(combo == nil)
            .help(S.clearShortcut)
        }
        .onAppear { combo = ShortcutStore.combo(for: action) }
        .onReceive(NotificationCenter.default.publisher(for: ShortcutStore.didChange)) { _ in
            combo = ShortcutStore.combo(for: action)
        }
        .onDisappear { stop() }
    }

    private func update(_ new: KeyCombo?) {
        combo = new
        ShortcutStore.set(new, for: action)
    }

    private func start() {
        recording = true
        NotificationCenter.default.post(name: ShortcutStore.recordingDidChange, object: true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated {
                if Int(event.keyCode) == kVK_Escape {
                    stop()
                } else if Int(event.keyCode) == kVK_Delete || Int(event.keyCode) == kVK_ForwardDelete {
                    update(nil)
                    stop()
                } else if let c = KeyCombo.from(event: event) {
                    update(c)
                    stop()
                } else {
                    NSSound.beep()
                }
            }
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if recording {
            recording = false
            NotificationCenter.default.post(name: ShortcutStore.recordingDidChange, object: false)
        }
    }
}
