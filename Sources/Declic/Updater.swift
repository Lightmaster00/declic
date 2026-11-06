import AppKit
import Security
import SwiftUI

/// Mises à jour automatiques depuis les « Releases » GitHub du projet.
///
/// - Au lancement puis toutes les 24 h (si l'option est active), Déclic interroge
///   `api.github.com/repos/<dépôt>/releases/latest`.
/// - Si la version publiée est plus récente, une fenêtre propose de l'installer.
/// - L'archive `.zip` de la release est téléchargée, l'app qu'elle contient doit porter
///   la même signature que l'app installée (sinon elle est refusée), puis elle remplace
///   l'app en place et Déclic redémarre. Rien ne s'ouvre dans le Terminal.
///
/// Le dépôt vient de la clé `DeclicGitHubRepo` de l'Info.plist (« propriétaire/dépôt »).
@MainActor
enum Updater {
    struct Release {
        let version: String
        let notes: String
        let assetURL: URL
        let pageURL: URL
    }

    enum UpdateError: LocalizedError {
        case noAsset
        case badArchive
        case badSignature
        case cannotReplace(String)

        var errorDescription: String? {
            switch self {
            case .noAsset: return S.updateNoAsset
            case .badArchive: return S.updateBadArchive
            case .badSignature: return S.updateBadSignature
            case .cannotReplace(let reason): return reason
            }
        }
    }

    static var repository: String? {
        guard let repo = Bundle.main.object(forInfoDictionaryKey: "DeclicGitHubRepo") as? String,
              repo.contains("/"), !repo.hasPrefix("$") else { return nil }
        return repo
    }

    static var isConfigured: Bool { repository != nil }

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    private static var timer: Timer?
    private static var checking = false
    private static var installing = false

    // MARK: Vérification

    /// À appeler au lancement : première vérification après quelques secondes, puis toutes les 24 h.
    static func startAutomaticChecks() {
        guard isConfigured else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            if Prefs.shared.autoCheckUpdates { await check(userInitiated: false) }
        }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 24 * 3600, repeats: true) { _ in
            Task { @MainActor in
                if Prefs.shared.autoCheckUpdates { await Updater.check(userInitiated: false) }
            }
        }
    }

    /// Menu « Rechercher des mises à jour… ».
    static func checkNow() {
        Task { await check(userInitiated: true) }
    }

    static func check(userInitiated: Bool) async {
        guard let repo = repository, !checking, !installing else { return }
        checking = true
        defer { checking = false }
        do {
            guard let release = try await latestRelease(repo: repo) else {
                if userInitiated { showUpToDate() }
                return
            }
            if !userInitiated, UserDefaults.standard.string(forKey: PrefKey.skippedVersion) == release.version {
                return
            }
            offer(release)
        } catch {
            NSLog("Declic update check failed: \(error)")
            if userInitiated { showError(S.updateCheckFailed, error) }
        }
    }

    private static func latestRelease(repo: String) async throws -> Release? {
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else { return nil }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Declic-Updater/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode == 404 { return nil } // aucune release
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String else { return nil }
        if json["draft"] as? Bool == true || json["prerelease"] as? Bool == true { return nil }
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        guard isNewer(version, than: currentVersion) else { return nil }
        let assets = json["assets"] as? [[String: Any]] ?? []
        guard let asset = assets.first(where: { ($0["name"] as? String)?.lowercased().hasSuffix(".zip") == true }),
              let download = (asset["browser_download_url"] as? String).flatMap(URL.init(string:)) else {
            throw UpdateError.noAsset
        }
        let page = (json["html_url"] as? String).flatMap(URL.init(string:)) ?? url
        return Release(version: version, notes: json["body"] as? String ?? "", assetURL: download, pageURL: page)
    }

    /// Compare deux versions « 1.2.10 » composante par composante.
    static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0.filter(\.isNumber)) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0.filter(\.isNumber)) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    // MARK: Fenêtres

    private static func showUpToDate() {
        let alert = NSAlert()
        alert.messageText = S.upToDate
        alert.informativeText = S.upToDateDetail(currentVersion)
        alert.addButton(withTitle: S.ok)
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private static func offer(_ release: Release) {
        let alert = NSAlert()
        alert.messageText = S.updateAvailable(release.version)
        var info = S.updateAvailableDetail(current: currentVersion)
        let notes = release.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !notes.isEmpty {
            info += "\n\n" + String(notes.prefix(600))
        }
        alert.informativeText = info
        alert.addButton(withTitle: S.installAndRestart)
        alert.addButton(withTitle: S.later)
        alert.addButton(withTitle: S.skipVersion)
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            Task { await install(release) }
        case .alertThirdButtonReturn:
            UserDefaults.standard.set(release.version, forKey: PrefKey.skippedVersion)
        default:
            break
        }
    }

    // MARK: Installation

    private static func install(_ release: Release) async {
        guard !installing else { return }
        installing = true
        let progress = UpdateProgressPanel()
        progress.show(S.downloadingUpdate)
        do {
            let work = FileManager.default.temporaryDirectory
                .appendingPathComponent("Declic-update-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

            // 1. Téléchargement.
            let (downloaded, _) = try await URLSession.shared.download(from: release.assetURL)
            let zip = work.appendingPathComponent("update.zip")
            try FileManager.default.moveItem(at: downloaded, to: zip)

            // 2. Décompression.
            progress.update(S.installingUpdate)
            let extracted = work.appendingPathComponent("extracted", isDirectory: true)
            try await run("/usr/bin/ditto", ["-x", "-k", zip.path, extracted.path])
            guard let newApp = try FileManager.default.contentsOfDirectory(at: extracted, includingPropertiesForKeys: nil)
                .first(where: { $0.pathExtension == "app" }) else { throw UpdateError.badArchive }

            // 3. Même signature que l'app actuelle, sinon on refuse.
            guard signatureMatches(newApp) else { throw UpdateError.badSignature }

            // 4. Remplacement de l'app en place, puis redémarrage.
            let current = Bundle.main.bundleURL
            do {
                _ = try FileManager.default.replaceItemAt(current, withItemAt: newApp,
                                                          backupItemName: nil, options: [])
            } catch {
                throw UpdateError.cannotReplace(S.updateCannotReplace(current.deletingLastPathComponent().path))
            }
            try? FileManager.default.removeItem(at: work)
            progress.update(S.restarting)
            relaunch(current)
        } catch {
            progress.close()
            installing = false
            let alert = NSAlert()
            alert.messageText = S.updateFailed
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: S.downloadManually)
            alert.addButton(withTitle: S.ok)
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(release.pageURL)
            }
        }
    }

    /// La nouvelle app doit satisfaire l'exigence de signature de l'app en cours
    /// (même certificat, même identifiant) : une archive modifiée est refusée.
    private static func signatureMatches(_ app: URL) -> Bool {
        var selfCode: SecCode?
        guard SecCodeCopySelf([], &selfCode) == errSecSuccess, let selfCode else { return false }
        var staticSelf: SecStaticCode?
        guard SecCodeCopyStaticCode(selfCode, [], &staticSelf) == errSecSuccess, let staticSelf else { return false }
        var requirement: SecRequirement?
        guard SecCodeCopyDesignatedRequirement(staticSelf, [], &requirement) == errSecSuccess,
              let requirement else { return false }
        var newCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &newCode) == errSecSuccess, let newCode else { return false }
        // kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate
        let flags = SecCSFlags(rawValue: (1 << 0) | (1 << 3) | (1 << 4))
        return SecStaticCodeCheckValidity(newCode, flags, requirement) == errSecSuccess
    }

    /// Relance l'app une fois celle-ci quittée.
    private static func relaunch(_ app: URL) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", app.path]
        try? task.run()
        NSApp.terminate(nil)
    }

    private static func run(_ tool: String, _ arguments: [String]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: tool)
            task.arguments = arguments
            task.terminationHandler = { finished in
                if finished.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: UpdateError.badArchive)
                }
            }
            do { try task.run() } catch { continuation.resume(throwing: error) }
        }
    }
}

// MARK: - Progression

private final class UpdateProgressModel: ObservableObject {
    @Published var text = ""
}

@MainActor
private final class UpdateProgressPanel {
    private let model = UpdateProgressModel()
    private var panel: FloatingPanel?

    func show(_ text: String) {
        model.text = text
        let host = NSHostingView(rootView: UpdateProgressView(model: model))
        let size = CGSize(width: 320, height: 64)
        host.frame = CGRect(origin: .zero, size: size)
        let p = FloatingPanel(size: size)
        p.level = .statusBar
        p.ignoresMouseEvents = true
        p.contentView = host
        let vf = NSScreen.underMouse.visibleFrame
        p.setFrameOrigin(CGPoint(x: vf.midX - size.width / 2, y: vf.maxY - size.height - 20))
        p.orderFrontRegardless()
        panel = p
    }

    func update(_ text: String) { model.text = text }

    func close() {
        panel?.orderOut(nil)
        panel = nil
    }
}

private struct UpdateProgressView: View {
    @ObservedObject var model: UpdateProgressModel

    var body: some View {
        HStack(spacing: 12) {
            ProgressView().controlSize(.small)
            Text(model.text)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .frame(width: 300, height: 48)
        .hudBackground(cornerRadius: 14)
        .environment(\.colorScheme, .dark)
        .padding(8)
    }
}
