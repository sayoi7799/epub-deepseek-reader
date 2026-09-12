import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class ReaderViewModel {
    private(set) var book: Book
    private let library: LibraryStore
    private let settings: SettingsStore
    private let engine: TranslationEngine
    let webController = ReaderWebController()

    var chapterIndex: Int
    var html: String = ""
    var reloadToken = UUID()
    var isLoading = false
    var loadError: String?

    var selection: ReaderSelection?
    var session: TranslationSession?
    var showChapterList = false
    var showReaderSettings = false
    var toast: String?

    private var chapterProgress: Double
    private var progressTask: Task<Void, Never>?
    private var insertedAnchors: Set<String> = []
    private var toastTask: Task<Void, Never>?

    init(book: Book, library: LibraryStore, settings: SettingsStore, engine: TranslationEngine) {
        self.book = book
        self.library = library
        self.settings = settings
        self.engine = engine
        self.chapterIndex = min(max(book.currentChapterIndex, 0), max(book.chapters.count - 1, 0))
        self.chapterProgress = book.chapterProgress
    }

    var appearance: ReaderAppearance { settings.appearance }

    var chapter: Chapter? { book.chapter(at: chapterIndex) }

    var chapterTitle: String { chapter?.title ?? book.title }

    var hasPreviousChapter: Bool { chapterIndex > 0 }

    var hasNextChapter: Bool { chapterIndex + 1 < book.chapters.count }

    var progressText: String {
        guard !book.chapters.isEmpty else { return "" }
        return "第 \(chapterIndex + 1)/\(book.chapters.count) 章 · \(Int(book.totalProgress * 100))%"
    }

    // MARK: - 章节加载

    func loadInitialChapter() async {
        guard html.isEmpty else { return }
        await loadChapter()
        library.markOpened(book)
    }

    func loadChapter() async {
        guard let chapter = self.chapter else {
            loadError = "这本书没有可阅读的章节"
            return
        }
        isLoading = true
        loadError = nil
        selection = nil
        session = nil
        insertedAnchors.removeAll()

        let progress = chapterProgress
        let loaded = await library.chapterHTML(
            book: book,
            chapter: chapter,
            appearance: settings.appearance,
            progress: progress
        )
        isLoading = false

        if let loaded {
            html = loaded
            reloadToken = UUID()
        } else {
            loadError = "这一章的内容读不出来，可能文件格式比较特殊"
        }
    }

    func goToChapter(_ index: Int) {
        guard index >= 0, index < book.chapters.count, index != chapterIndex else { return }
        chapterIndex = index
        chapterProgress = 0
        book.currentChapterIndex = index
        book.chapterProgress = 0
        library.scheduleSave()
        Task { await loadChapter() }
    }

    func goNext() {
        guard hasNextChapter else { return }
        goToChapter(chapterIndex + 1)
    }

    func goPrevious() {
        guard hasPreviousChapter else { return }
        goToChapter(chapterIndex - 1)
    }

    // MARK: - WebView 消息

    func handle(_ message: ReaderMessage) {
        switch message {
        case .ready:
            break

        case .progress(let value):
            chapterProgress = min(max(value, 0), 1)
            book.chapterProgress = chapterProgress
            scheduleProgressSave()

        case .selection(let text, let anchorID, let rect, let context):
            guard settings.selectToTranslate else { return }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            if session != nil {
                closeSession()
            }
            selection = ReaderSelection(text: trimmed, anchorID: anchorID, rect: rect, context: context)

        case .selectionCleared:
            if session == nil {
                selection = nil
            }

        case .paragraphTap(let text, let anchorID, let rect, let context):
            guard settings.tapToTranslate else { return }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            if let session, session.anchorID == anchorID {
                closeSession()
                return
            }
            startTranslation(
                for: ReaderSelection(text: trimmed, anchorID: anchorID, rect: rect, context: context)
            )

        case .link(let href):
            handleLink(href)
        }
    }

    private func handleLink(_ href: String) {
        if href.hasPrefix("http://") || href.hasPrefix("https://") {
            if let url = URL(string: href) {
                UIApplication.shared.open(url)
            }
            return
        }
        let base = EPUBParser.directory(of: chapter?.href ?? "")
        let resolved = EPUBParser.resolve(base: base, href: href)
        guard let index = book.chapters.firstIndex(where: { $0.href == resolved }) else { return }
        goToChapter(index)
    }

    // MARK: - 翻译

    func startTranslation(for selection: ReaderSelection) {
        self.selection = nil
        let session = TranslationSession(
            source: selection.text,
            anchorID: selection.anchorID.isEmpty ? nil : selection.anchorID,
            context: context(for: selection),
            style: settings.defaultStyle
        )
        self.session = session
        engine.start(session)

        if settings.autoInsertTranslation {
            let targetID = session.id
            Task { [weak self] in
                while let self, let current = self.session, current.id == targetID, current.isBusy {
                    try? await Task.sleep(nanoseconds: 250_000_000)
                }
                guard let self, let current = self.session, current.id == targetID, current.hasContent else { return }
                self.insert(current)
            }
        }
    }

    func retryCurrent() {
        guard let session = self.session else { return }
        engine.start(session)
    }

    func refineCurrent() {
        guard let session = self.session else { return }
        engine.refine(session)
    }

    func stopCurrent() {
        guard let session = self.session else { return }
        engine.cancel(session)
    }

    func closeSession() {
        guard let session = self.session else { return }
        engine.cancel(session)
        if session.insertedInReader, let anchorID = session.anchorID {
            webController.removeTranslation(anchorID: anchorID)
            insertedAnchors.remove(anchorID)
        }
        self.session = nil
    }

    func changeStyle(_ style: TranslationStyle) {
        guard let session = self.session else { return }
        session.style = style
        engine.start(session)
    }

    func copyCurrentTranslation() {
        guard let session = self.session, session.hasContent else { return }
        UIPasteboard.general.string = session.text
        showToast("已复制译文")
    }

    func insertCurrentTranslation() {
        guard let session = self.session, session.hasContent else { return }
        insert(session)
    }

    private func insert(_ session: TranslationSession) {
        guard let anchorID = session.anchorID, !anchorID.isEmpty else {
            showToast("这一处无法插入正文")
            return
        }
        webController.insertTranslation(anchorID: anchorID, text: session.text)
        session.insertedInReader = true
        insertedAnchors.insert(anchorID)
        showToast("已插入到正文下面")
    }

    private func context(for selection: ReaderSelection) -> TranslationContext {
        var glossary = settings.glossary
        for (key, value) in book.glossary {
            glossary[key] = value
        }
        return TranslationContext(
            bookID: book.id.uuidString,
            bookTitle: book.title,
            bookAuthor: book.author,
            chapterTitle: chapterTitle,
            paragraph: selection.context.paragraph,
            previousParagraph: selection.context.previousParagraph,
            nextParagraph: selection.context.nextParagraph,
            glossary: glossary
        )
    }

    // MARK: - 进度

    private func scheduleProgressSave() {
        progressTask?.cancel()
        progressTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }
            self?.commitProgress()
        }
    }

    func persistProgress() {
        progressTask?.cancel()
        commitProgress()
    }

    private func commitProgress() {
        book.chapterProgress = chapterProgress
        book.currentChapterIndex = chapterIndex
        book.lastOpenedAt = Date()
        library.update(book)
    }

    // MARK: - 提示

    func showToast(_ text: String) {
        toast = text
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }
}
