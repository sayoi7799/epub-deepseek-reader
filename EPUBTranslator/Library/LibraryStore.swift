import Foundation
import Observation

@MainActor
@Observable
final class LibraryStore {
    enum ImportState: Equatable {
        case idle
        case importing(name: String)
        case failed(message: String)
    }

    private(set) var books: [Book] = []
    private(set) var importState: ImportState = .idle
    var lastErrorMessage: String?

    private let fileManager = FileManager.default
    private let rootURL: URL
    private let booksURL: URL
    private let indexURL: URL
    /// Files 应用里「我的 iPhone / 译读」对应的目录，可以直接丢 EPUB 进来。
    let inboxURL: URL

    private var pendingSave: Task<Void, Never>?

    init() {
        let supportRoot = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        rootURL = supportRoot.appendingPathComponent("EPUBTranslator", isDirectory: true)
        booksURL = rootURL.appendingPathComponent("Books", isDirectory: true)
        indexURL = rootURL.appendingPathComponent("library.json")
        inboxURL = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first ?? rootURL
    }

    // MARK: - 读写

    func load() {
        try? fileManager.createDirectory(at: booksURL, withIntermediateDirectories: true)
        guard let data = try? Data(contentsOf: indexURL) else { return }
        guard let decoded = try? JSONDecoder().decode([Book].self, from: data) else { return }
        books = decoded.sorted { $0.addedAt > $1.addedAt }
    }

    func scheduleSave() {
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        pendingSave?.cancel()
        guard let data = try? JSONEncoder().encode(books) else { return }
        try? fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try? data.write(to: indexURL, options: [.atomic])
    }

    // MARK: - 路径

    func folderURL(for book: Book) -> URL {
        booksURL.appendingPathComponent(book.id.uuidString, isDirectory: true)
    }

    func contentURL(for book: Book) -> URL {
        folderURL(for: book).appendingPathComponent("content", isDirectory: true)
    }

    func coverImageURL(for book: Book) -> URL? {
        guard let coverPath = book.coverPath else { return nil }
        let url = EPUBParser.fileURL(root: contentURL(for: book), relativePath: coverPath)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: - 导入

    func importBook(from sourceURL: URL, replacingExisting: Bool = true) async throws -> Book {
        let fileName = sourceURL.lastPathComponent
        importState = .importing(name: fileName)
        defer { importState = .idle }

        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer { if accessed { sourceURL.stopAccessingSecurityScopedResource() } }

        let attributes = try? fileManager.attributesOfItem(atPath: sourceURL.path)
        let byteSize = (attributes?[.size] as? NSNumber)?.intValue ?? 0

        if replacingExisting, let existing = books.first(where: { $0.sourceFileName == fileName }) {
            delete(existing)
        }

        let newID = UUID()
        let folder = booksURL.appendingPathComponent(newID.uuidString, isDirectory: true)
        let parsed = try await Task.detached(priority: .userInitiated) {
            try EPUBParser.importEPUB(from: sourceURL, to: folder, sourceFileName: fileName)
        }.value

        let book = Book(
            id: newID,
            title: parsed.title,
            author: parsed.author,
            language: parsed.language,
            coverPath: parsed.coverPath,
            sourceFileName: fileName,
            byteSize: byteSize,
            chapters: parsed.chapters
        )
        books.insert(book, at: 0)
        saveNow()
        return book
    }

    /// 扫描 Files 目录，把用户丢进来的 EPUB 自动导入。
    func importInboxIfNeeded() async {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: inboxURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for url in urls where url.pathExtension.lowercased() == "epub" {
            if url.lastPathComponent.hasPrefix(".") { continue }
            if books.contains(where: { $0.sourceFileName == url.lastPathComponent }) { continue }
            do {
                _ = try await importBook(from: url, replacingExisting: false)
            } catch {
                lastErrorMessage = "导入 \(url.lastPathComponent) 失败：\(error.localizedDescription)"
            }
        }
    }

    // MARK: - 修改

    func update(_ book: Book) {
        guard let index = books.firstIndex(where: { $0.id == book.id }) else { return }
        books[index] = book
        scheduleSave()
    }

    func markOpened(_ book: Book) {
        guard let index = books.firstIndex(where: { $0.id == book.id }) else { return }
        books[index].lastOpenedAt = Date()
        scheduleSave()
    }

    func delete(_ book: Book) {
        books.removeAll { $0.id == book.id }
        try? fileManager.removeItem(at: folderURL(for: book))
        saveNow()
    }

    func deleteAll() {
        books.removeAll()
        try? fileManager.removeItem(at: booksURL)
        try? fileManager.createDirectory(at: booksURL, withIntermediateDirectories: true)
        saveNow()
    }

    func book(with id: UUID) -> Book? {
        books.first { $0.id == id }
    }

    var mostRecentlyOpened: Book? {
        books
            .filter { $0.lastOpenedAt != nil }
            .sorted { ($0.lastOpenedAt ?? .distantPast) > ($1.lastOpenedAt ?? .distantPast) }
            .first ?? books.first
    }

    // MARK: - 章节内容

    func chapterHTML(
        book: Book,
        chapter: Chapter,
        appearance: ReaderAppearance,
        progress: Double
    ) async -> String? {
        let contentRoot = contentURL(for: book)
        let chapterPath = chapter.href
        return await Task.detached(priority: .userInitiated) { () -> String? in
            let url = EPUBParser.fileURL(root: contentRoot, relativePath: chapterPath)
            guard
                let data = try? Data(contentsOf: url),
                let text = String.decodingText(from: data)
            else { return nil }
            return HTMLDocumentBuilder.build(
                sourceHTML: text,
                chapterPath: chapterPath,
                contentRoot: contentRoot,
                appearance: appearance,
                initialProgress: progress
            )
        }.value
    }
}
