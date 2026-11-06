import AppKit
import AVFoundation
import SwiftUI

// MARK: - Stockage

struct HistoryItem: Codable, Identifiable, Equatable {
    enum Kind: String, Codable {
        case screenshot, video, gif
    }

    let id: UUID
    let date: Date
    let kind: Kind
    let fileName: String
    let width: Int
    let height: Int
    let scale: Double

    var isImage: Bool { kind == .screenshot }
}

/// Historique des captures, conservé dans ~/Library/Application Support/Déclic/History.
@MainActor
final class HistoryStore: ObservableObject {
    static let shared = HistoryStore()

    @Published private(set) var items: [HistoryItem] = []

    let folder: URL
    private var indexURL: URL { folder.appendingPathComponent("index.json") }
    private let maxItems = 1000

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        folder = support.appendingPathComponent("Declic/History", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        load()
        prune()
    }

    func url(for item: HistoryItem) -> URL { folder.appendingPathComponent(item.fileName) }

    func addImage(_ image: CGImage, scale: CGFloat) {
        guard Prefs.shared.historyEnabled else { return }
        let id = UUID()
        let item = HistoryItem(id: id, date: Date(), kind: .screenshot, fileName: "\(id.uuidString).png",
                               width: image.width, height: image.height, scale: Double(scale))
        let url = self.url(for: item)
        Task.detached(priority: .utility) {
            guard let data = FileUtil.pngData(image) else { return }
            try? data.write(to: url)
            await MainActor.run {
                HistoryStore.shared.insert(item)
            }
        }
    }

    func addVideo(_ source: URL, isGIF: Bool) {
        guard Prefs.shared.historyEnabled else { return }
        let id = UUID()
        let item = HistoryItem(id: id, date: Date(), kind: isGIF ? .gif : .video,
                               fileName: "\(id.uuidString).\(isGIF ? "gif" : "mp4")",
                               width: 0, height: 0, scale: 1)
        do {
            try FileManager.default.copyItem(at: source, to: url(for: item))
            insert(item)
        } catch {
            NSLog("Declic: historique : \(error)")
        }
    }

    private func insert(_ item: HistoryItem) {
        items.insert(item, at: 0)
        prune()
        save()
    }

    func remove(_ item: HistoryItem) {
        try? FileManager.default.removeItem(at: url(for: item))
        items.removeAll { $0.id == item.id }
        ThumbnailCache.shared.forget(item.id)
        save()
    }

    func clear() {
        for item in items { try? FileManager.default.removeItem(at: url(for: item)) }
        items.removeAll()
        save()
    }

    /// Supprime les éléments trop anciens (durée réglable) ou en trop.
    func prune() {
        let days = Prefs.shared.historyDays
        var removed: [HistoryItem] = []
        if days > 0 {
            let limit = Date().addingTimeInterval(-Double(days) * 86_400)
            removed += items.filter { $0.date < limit }
        }
        if items.count > maxItems { removed += items[maxItems...] }
        guard !removed.isEmpty else { return }
        let ids = Set(removed.map(\.id))
        for item in removed { try? FileManager.default.removeItem(at: url(for: item)) }
        items.removeAll { ids.contains($0.id) }
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode([HistoryItem].self, from: data) else { return }
        items = decoded.filter { FileManager.default.fileExists(atPath: url(for: $0).path) }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    // MARK: Actions

    func image(for item: HistoryItem) -> CGImage? {
        guard item.isImage else { return nil }
        return FileUtil.loadImage(url(for: item))
    }

    func copy(_ item: HistoryItem) {
        if let image = image(for: item) {
            Clipboard.copy(image: image, scale: CGFloat(item.scale))
        } else {
            Clipboard.copy(fileURL: url(for: item))
        }
        FeedbackHUD.show(S.copied)
    }

    func saveToFolder(_ item: HistoryItem) {
        do {
            let dest: URL
            if let image = image(for: item) {
                dest = try FileUtil.savePNG(image)
            } else {
                dest = try FileUtil.saveVideo(url(for: item), isGIF: item.kind == .gif)
            }
            NSWorkspace.shared.activateFileViewerSelecting([dest])
        } catch {
            showError(S.saveFailed, error)
        }
    }

    func annotate(_ item: HistoryItem) {
        guard let image = image(for: item) else { return }
        EditorWindowController.open(image: image, scale: CGFloat(item.scale))
    }

    func pin(_ item: HistoryItem) {
        guard let image = image(for: item) else { return }
        PinManager.shared.pin(image: image, scale: CGFloat(item.scale), origin: nil)
    }

    /// Aperçu (double-clic).
    func open(_ item: HistoryItem) {
        if let image = image(for: item) {
            EditorWindowController.open(image: image, scale: CGFloat(item.scale))
        } else if !item.isImage {
            PreviewWindowController.show(.video(url(for: item), isGIF: item.kind == .gif))
        }
    }
}

// MARK: - Vignettes

@MainActor
final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSString, NSImage>()

    func cached(_ id: UUID) -> NSImage? { cache.object(forKey: id.uuidString as NSString) }

    func forget(_ id: UUID) { cache.removeObject(forKey: id.uuidString as NSString) }

    func load(_ item: HistoryItem, url: URL) async -> NSImage? {
        if let hit = cached(item.id) { return hit }
        let image: NSImage?
        switch item.kind {
        case .screenshot, .gif:
            let cg = await Task.detached(priority: .utility) { ImageTools.thumbnail(of: url, maxPixel: 520) }.value
            image = cg.map { NSImage(cgImage: $0, size: .zero) }
        case .video:
            image = await FileUtil.thumbnail(for: url, isGIF: false)
        }
        if let image { cache.setObject(image, forKey: item.id.uuidString as NSString) }
        return image
    }
}

// MARK: - Fenêtre

enum HistoryFilter: String, CaseIterable, Identifiable {
    case all, screenshots, recordings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return S.filterAll
        case .screenshots: return S.filterScreenshots
        case .recordings: return S.filterRecordings
        }
    }
}

@MainActor
struct HistoryView: View {
    @ObservedObject var store: HistoryStore
    @State private var filter: HistoryFilter = .all
    @State private var confirmClear = false

    private var filtered: [HistoryItem] {
        switch filter {
        case .all: return store.items
        case .screenshots: return store.items.filter(\.isImage)
        case .recordings: return store.items.filter { !$0.isImage }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Picker("", selection: $filter) {
                    ForEach(HistoryFilter.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()

                Spacer()

                Text(S.itemsCount(filtered.count))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                Button {
                    NSWorkspace.shared.open(store.folder)
                } label: {
                    Image(systemName: "folder")
                }
                .help(S.showInFinder)

                Button(role: .destructive) {
                    confirmClear = true
                } label: {
                    Image(systemName: "trash")
                }
                .help(S.clearHistory)
                .disabled(store.items.isEmpty)
            }
            .controlSize(.large)
            .padding(.leading, 84)
            .padding(.trailing, 14)
            .frame(height: 60)
            .background(WindowDragArea())

            Divider()

            if filtered.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 34, weight: .light))
                        .foregroundColor(.secondary)
                    Text(S.historyEmpty)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 190, maximum: 260), spacing: 16)], spacing: 18) {
                        ForEach(filtered) { item in
                            HistoryCell(item: item, store: store)
                        }
                    }
                    .padding(18)
                }
            }
        }
        .ignoresSafeArea()
        .frame(minWidth: 640, minHeight: 420)
        .alert(S.clearHistoryConfirm, isPresented: $confirmClear) {
            Button(S.clearHistory, role: .destructive) { store.clear() }
            Button(S.cancel, role: .cancel) {}
        }
    }
}

@MainActor
struct HistoryCell: View {
    let item: HistoryItem
    @ObservedObject var store: HistoryStore
    @State private var thumbnail: NSImage?
    @State private var hover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .padding(6)
                } else {
                    ProgressView().controlSize(.small)
                }
                if !item.isImage && !hover {
                    Image(systemName: item.kind == .gif ? "photo.stack" : "play.circle.fill")
                        .font(.system(size: 26, weight: .light))
                        .foregroundColor(.white.opacity(0.9))
                        .shadow(color: .black.opacity(0.4), radius: 4)
                }
                if hover {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.black.opacity(0.4))
                    HStack(spacing: 6) {
                        CircleIconButton(symbol: "doc.on.doc", help: S.copy, size: 26) { store.copy(item) }
                        CircleIconButton(symbol: "square.and.arrow.down", help: S.save, size: 26) { store.saveToFolder(item) }
                        if item.isImage {
                            CircleIconButton(symbol: "pencil", help: S.annotate, size: 26) { store.annotate(item) }
                        } else {
                            CircleIconButton(symbol: "play.fill", help: S.open, size: 26) { store.open(item) }
                        }
                        CircleIconButton(symbol: "trash", help: S.delete, size: 26) { store.remove(item) }
                    }
                }
            }
            .frame(height: 140)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(hover ? 0.25 : 0.08), lineWidth: 1)
            )
            .onHover { hover = $0 }
            .onTapGesture(count: 2) { store.open(item) }
            .onDrag {
                NSItemProvider(contentsOf: store.url(for: item)) ?? NSItemProvider()
            }
            .contextMenu {
                Button(S.copy) { store.copy(item) }
                Button(S.save) { store.saveToFolder(item) }
                if item.isImage {
                    Button(S.annotate) { store.annotate(item) }
                } else {
                    Button(S.open) { store.open(item) }
                }
                Button(S.showInFinder) { NSWorkspace.shared.activateFileViewerSelecting([store.url(for: item)]) }
                Divider()
                Button(S.delete, role: .destructive) { store.remove(item) }
            }

            HStack(spacing: 6) {
                Image(systemName: kindSymbol)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Text(item.date, style: .relative)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.primary.opacity(0.8))
                    .lineLimit(1)
                Spacer()
                if item.isImage {
                    Text("\(item.width) × \(item.height)")
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 2)
        }
        .task(id: item.id) {
            thumbnail = await ThumbnailCache.shared.load(item, url: store.url(for: item))
        }
        .animation(.easeOut(duration: 0.12), value: hover)
    }

    private var kindSymbol: String {
        switch item.kind {
        case .screenshot: return "photo"
        case .video: return "video"
        case .gif: return "photo.stack"
        }
    }
}

@MainActor
final class HistoryWindowController: NSWindowController {
    private static var shared: HistoryWindowController?

    static func show() {
        if shared == nil {
            HistoryStore.shared.prune()
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 940, height: 620),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
            window.title = S.history
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: HistoryView(store: HistoryStore.shared))
            window.center()
            window.setFrameAutosaveName("DeclicHistory")
            shared = HistoryWindowController(window: window)
        }
        NSApp.activate(ignoringOtherApps: true)
        shared?.showWindow(nil)
        shared?.window?.makeKeyAndOrderFront(nil)
    }
}
