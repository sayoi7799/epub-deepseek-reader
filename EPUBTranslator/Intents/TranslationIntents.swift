import AppIntents
import Foundation
import UIKit

enum TranslationIntentError: Error, CustomLocalizedStringResourceConvertible {
    case emptyInput
    case noRecentBook

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .emptyInput:
            return "没有可翻译的文字。"
        case .noRecentBook:
            return "书架里还没有书。"
        }
    }
}

enum TranslationStyleAppEnum: String, AppEnum {
    case literary
    case faithful
    case colloquial
    case academic
    case concise

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "翻译风格")

    static var caseDisplayRepresentations: [TranslationStyleAppEnum: DisplayRepresentation] = [
        .literary: "文学流畅",
        .faithful: "忠于原文",
        .colloquial: "口语自然",
        .academic: "学术严谨",
        .concise: "极简速读",
    ]

    var translationStyle: TranslationStyle {
        TranslationStyle(rawValue: rawValue) ?? .literary
    }
}

/// 把一段文字翻译成中文（不打开 App）。
struct TranslateTextIntent: AppIntent {
    static var title: LocalizedStringResource = "翻译文本"
    static var description = IntentDescription("用 DeepSeek 把一段文字翻译成自然的中文。")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "文本", description: "要翻译的内容")
    var text: String

    @Parameter(title: "风格")
    var style: TranslationStyleAppEnum?

    static var parameterSummary: some ParameterSummary {
        Summary("翻译 \(\.$text)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TranslationIntentError.emptyInput }
        let engine = await MainActor.run { AppServices.shared.engine }
        let result = try await engine.translate(text: trimmed, style: style?.translationStyle ?? .literary)
        return .result(value: result)
    }
}

/// 翻译剪贴板内容。
struct TranslateClipboardIntent: AppIntent {
    static var title: LocalizedStringResource = "翻译剪贴板"
    static var description = IntentDescription("翻译剪贴板里复制的那段文字。")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let text = (UIPasteboard.general.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw TranslationIntentError.emptyInput }
        let engine = await MainActor.run { AppServices.shared.engine }
        let result = try await engine.translate(text: text, style: .literary)
        return .result(value: result)
    }
}

/// 直接跳到上次在读的那本书。
struct ContinueReadingIntent: AppIntent {
    static var title: LocalizedStringResource = "继续阅读"
    static var description = IntentDescription("打开译读里最近在读的那本书。")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        let opened = await MainActor.run { () -> Bool in
            let services = AppServices.shared
            services.library.load()
            guard let book = services.library.mostRecentlyOpened else { return false }
            services.router.open(book)
            return true
        }
        if !opened { throw TranslationIntentError.noRecentBook }
        return .result()
    }
}

struct EPUBTranslatorShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: TranslateTextIntent(),
            phrases: [
                "用\(.applicationName)翻译这段话",
                "\(.applicationName)翻译",
            ],
            shortTitle: "翻译文本",
            systemImageName: "character.book.closed"
        )
        AppShortcut(
            intent: TranslateClipboardIntent(),
            phrases: [
                "用\(.applicationName)翻译剪贴板",
            ],
            shortTitle: "翻译剪贴板",
            systemImageName: "doc.on.clipboard"
        )
        AppShortcut(
            intent: ContinueReadingIntent(),
            phrases: [
                "用\(.applicationName)继续读书",
            ],
            shortTitle: "继续阅读",
            systemImageName: "book"
        )
    }
}
