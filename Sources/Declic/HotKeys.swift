import AppKit
import Carbon

/// Raccourcis clavier globaux via l'API Carbon (fonctionne sans autorisation d'accessibilité).
@MainActor
final class HotKeyCenter {
    typealias Handler = @MainActor () -> Void

    static let shared = HotKeyCenter()

    private var handlers: [UInt32: Handler] = [:]
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var installed = false
    private var nextID: UInt32 = 1

    /// Enregistre un raccourci. Retourne un identifiant utilisable avec `unregister`.
    @discardableResult
    func register(keyCode: Int, modifiers: Int, handler: @escaping Handler) -> UInt32? {
        installIfNeeded()
        let id = nextID
        nextID += 1
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x5348_4B54), id: id) // 'SHKT'
        let status = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hotKeyID,
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else {
            NSLog("Declic: impossible d'enregistrer le raccourci \(keyCode) (\(status))")
            return nil
        }
        handlers[id] = handler
        refs[id] = ref
        return id
    }

    func unregister(_ id: UInt32?) {
        guard let id, let ref = refs[id] else { return }
        UnregisterEventHotKey(ref)
        refs[id] = nil
        handlers[id] = nil
    }

    fileprivate func fire(_ id: UInt32) {
        handlers[id]?()
    }

    private func installIfNeeded() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event,
                                           EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID),
                                           nil,
                                           MemoryLayout<EventHotKeyID>.size,
                                           nil,
                                           &hotKeyID)
            guard status == noErr else { return status }
            let id = hotKeyID.id
            MainActor.assumeIsolated {
                HotKeyCenter.shared.fire(id)
            }
            return noErr
        }, 1, &spec, nil, nil)
    }
}
