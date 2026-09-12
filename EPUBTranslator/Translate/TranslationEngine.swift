import Foundation
import Observation

/// 翻译编排：读取设置 → 查缓存 → 调用 DeepSeek → 流式刷新 → 落库。
@MainActor
@Observable
final class TranslationEngine {
    private let settings: SettingsStore
    private let cache: TranslationCache
    private let history: HistoryStore
    private let liveActivity: LiveActivityController
    private var runningTask: Task<Void, Never>?

    init(
        settings: SettingsStore,
        cache: TranslationCache,
        history: HistoryStore,
        liveActivity: LiveActivityController
    ) {
        self.settings = settings
        self.cache = cache
        self.history = history
        self.liveActivity = liveActivity
    }

    var isRunning: Bool { runningTask != nil }

    // MARK: - 翻译

    func start(_ session: TranslationSession) {
        runningTask?.cancel()
        session.usedCache = false
        session.modelName = settings.model.rawValue

        let builder = promptBuilder(for: session.style)
        let kind = session.taskKind
        let messages = builder.messages(text: session.source, context: session.context, kind: kind)
        let cacheKey = TranslationCache.key(
            text: session.source,
            style: session.style,
            targetLanguage: settings.targetLanguage,
            model: settings.model.rawValue,
            instruction: settings.customInstruction,
            context: session.context,
            kind: kind
        )

        if let cached = cache.value(for: cacheKey) {
            session.text = cached
            session.phase = .done
            session.usedCache = true
            liveActivity.stop()
            return
        }

        guard let client = try? DeepSeekClient(settings: settings) else {
            let message = DeepSeekError.missingAPIKey.localizedDescription
            session.phase = .failed(message)
            liveActivity.fail(message: message)
            return
        }

        let request = ChatRequest(
            model: settings.model.rawValue,
            messages: messages,
            stream: settings.streaming,
            temperature: settings.temperature,
            maxTokens: settings.maxTokens > 0 ? settings.maxTokens : nil
        )

        requestLiveActivity(for: session)
        session.text = ""
        session.phase = .translating

        runningTask = Task { [weak self] in
            await self?.run(session: session, client: client, request: request, cacheKey: cacheKey, builder: builder)
        }
    }

    private func requestLiveActivity(for session: TranslationSession) {
        guard settings.liveActivityEnabled else {
            liveActivity.stop()
            return
        }
        liveActivity.begin(
            sourceText: session.source,
            bookTitle: session.context.bookTitle ?? "",
            chapterTitle: session.context.chapterTitle ?? "",
            bookID: session.context.bookID ?? "",
            styleTitle: session.style.title
        )
    }

    private func run(
        session: TranslationSession,
        client: DeepSeekClient,
        request: ChatRequest,
        cacheKey: String,
        builder: PromptBuilder
    ) async {
        defer { runningTask = nil }
        do {
            var draft = ""
            if settings.streaming {
                for try await delta in client.stream(request) {
                    if Task.isCancelled { return }
                    draft += delta
                    session.text = draft
                    liveActivity.update(translated: draft)
                }
            } else {
                draft = try await client.complete(request)
                session.text = draft
                liveActivity.update(translated: draft, force: true)
            }

            let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                let message = DeepSeekError.emptyResponse.localizedDescription
                session.phase = .failed(message)
                liveActivity.fail(message: message)
                return
            }

            if settings.highQuality {
                session.phase = .refining
                liveActivity.update(phase: .refining, force: true)
                let refineRequest = ChatRequest(
                    model: settings.model.rawValue,
                    messages: builder.refineMessages(draft: trimmed, source: session.source, context: session.context),
                    stream: settings.streaming,
                    temperature: max(0.2, settings.temperature - 0.6),
                    maxTokens: settings.maxTokens > 0 ? settings.maxTokens : nil
                )
                if settings.streaming {
                    session.text = ""
                    var refined = ""
                    for try await delta in client.stream(refineRequest) {
                        if Task.isCancelled { return }
                        refined += delta
                        session.text = refined
                        liveActivity.update(translated: refined)
                    }
                    let finalText = refined.trimmingCharacters(in: .whitespacesAndNewlines)
                    finish(session: session, text: finalText.isEmpty ? trimmed : finalText, cacheKey: cacheKey)
                } else if let refined = try? await client.complete(refineRequest) {
                    liveActivity.update(translated: refined, force: true)
                    finish(session: session, text: refined, cacheKey: cacheKey)
                } else {
                    finish(session: session, text: trimmed, cacheKey: cacheKey)
                }
            } else {
                finish(session: session, text: trimmed, cacheKey: cacheKey)
            }
        } catch {
            if Task.isCancelled { return }
            if let deepSeekError = error as? DeepSeekError, case .cancelled = deepSeekError {
                session.phase = .cancelled
                liveActivity.stop()
                return
            }
            session.phase = .failed(error.localizedDescription)
            liveActivity.fail(message: error.localizedDescription)
        }
    }

    private func finish(session: TranslationSession, text: String, cacheKey: String) {
        session.text = text
        session.phase = .done
        session.usedCache = false
        liveActivity.finish(translated: text)
        cache.store(text, for: cacheKey)
        history.add(
            TranslationRecord(
                sourceText: session.source,
                translatedText: text,
                bookTitle: session.context.bookTitle,
                chapterTitle: session.context.chapterTitle,
                styleRaw: session.style.rawValue,
                model: settings.model.rawValue
            )
        )
    }

    // MARK: - 润色

    func refine(_ session: TranslationSession) {
        let draft = session.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !draft.isEmpty else { return }
        runningTask?.cancel()

        guard let client = try? DeepSeekClient(settings: settings) else {
            session.phase = .failed(DeepSeekError.missingAPIKey.localizedDescription)
            return
        }

        let builder = promptBuilder(for: session.style)
        let request = ChatRequest(
            model: settings.model.rawValue,
            messages: builder.refineMessages(draft: draft, source: session.source, context: session.context),
            stream: settings.streaming,
            temperature: max(0.2, settings.temperature - 0.6),
            maxTokens: settings.maxTokens > 0 ? settings.maxTokens : nil
        )

        session.phase = .refining
        requestLiveActivity(for: session)
        runningTask = Task { [weak self] in
            defer { self?.runningTask = nil }
            do {
                var result = ""
                if self?.settings.streaming == true {
                    result = ""
                    for try await delta in client.stream(request) {
                        if Task.isCancelled { return }
                        result += delta
                        session.text = result
                        self?.liveActivity.update(translated: result)
                    }
                } else {
                    result = try await client.complete(request)
                    session.text = result
                    self?.liveActivity.update(translated: result, force: true)
                }
                let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    let message = DeepSeekError.emptyResponse.localizedDescription
                    session.phase = .failed(message)
                    self?.liveActivity.fail(message: message)
                } else {
                    session.text = trimmed
                    session.phase = .done
                    self?.liveActivity.finish(translated: trimmed)
                    self?.history.add(
                        TranslationRecord(
                            sourceText: session.source,
                            translatedText: trimmed,
                            bookTitle: session.context.bookTitle,
                            chapterTitle: session.context.chapterTitle,
                            styleRaw: session.style.rawValue,
                            model: self?.settings.model.rawValue ?? ""
                        )
                    )
                }
            } catch {
                if Task.isCancelled { return }
                session.phase = .failed(error.localizedDescription)
                self?.liveActivity.fail(message: error.localizedDescription)
            }
        }
    }

    func cancel(_ session: TranslationSession) {
        runningTask?.cancel()
        runningTask = nil
        liveActivity.stop()
        if session.isBusy {
            session.phase = session.hasContent ? .done : .cancelled
        }
    }

    // MARK: - 其他

    var promptBuilder: PromptBuilder {
        PromptBuilder(
            style: settings.defaultStyle,
            targetLanguage: settings.targetLanguage,
            customInstruction: settings.customInstruction,
            includeContext: settings.useBookContext
        )
    }

    func promptBuilder(for style: TranslationStyle) -> PromptBuilder {
        PromptBuilder(
            style: style,
            targetLanguage: settings.targetLanguage,
            customInstruction: settings.customInstruction,
            includeContext: settings.useBookContext
        )
    }

    /// 设置页的「测试连接」。
    func testConnection() async throws -> String {
        let client = try DeepSeekClient(settings: settings)
        let request = ChatRequest(
            model: settings.model.rawValue,
            messages: [
                ChatMessage.system("你是一个测试助手，只输出一行简短的中文。"),
                ChatMessage.user("请回答「连接正常」四个字。"),
            ],
            stream: false,
            temperature: 0.3,
            maxTokens: 64
        )
        return try await client.complete(request)
    }

    /// 给 App Intents / 快捷指令用的同步翻译。
    func translate(
        text: String,
        style: TranslationStyle,
        context: TranslationContext = .empty
    ) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let client = try DeepSeekClient(settings: settings)
        let builder = promptBuilder(for: style)
        let kind: TranslationTaskKind = trimmed.split(whereSeparator: { $0.isWhitespace }).count <= 2 ? .word : .selection
        let request = ChatRequest(
            model: settings.model.rawValue,
            messages: builder.messages(text: trimmed, context: context, kind: kind),
            stream: false,
            temperature: settings.temperature,
            maxTokens: settings.maxTokens > 0 ? settings.maxTokens : nil
        )
        let result = try await client.complete(request)
        history.add(
            TranslationRecord(
                sourceText: trimmed,
                translatedText: result,
                bookTitle: context.bookTitle,
                chapterTitle: context.chapterTitle,
                styleRaw: style.rawValue,
                model: settings.model.rawValue
            )
        )
        return result
    }
}
