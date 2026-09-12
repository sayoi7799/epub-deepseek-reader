import ActivityKit
import Foundation

/// 灵动岛 / 锁屏 Live Activity 的共享数据结构。
///
/// 这个文件同时被 `EPUBTranslator`（App）和 `EPUBTranslatorWidgets`（扩展）编译，
/// 两边必须使用同名的 `TranslationActivityAttributes`，
/// 系统才能把 App 启动的活动交给扩展渲染。
struct TranslationActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        enum Phase: String, Codable, Hashable {
            case preparing
            case translating
            case refining
            case finished
            case failed
        }

        var sourceText: String
        var translatedText: String
        var phase: Phase
        var styleTitle: String
        var message: String?
        var updatedAt: Date

        var displayText: String {
            let trimmed = translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "…" : trimmed
        }

        var phaseTitle: String {
            switch phase {
            case .preparing: return "准备中"
            case .translating: return "翻译中"
            case .refining: return "润色中"
            case .finished: return "已完成"
            case .failed: return "出错了"
            }
        }

        var isBusy: Bool {
            switch phase {
            case .preparing, .translating, .refining: return true
            case .finished, .failed: return false
            }
        }
    }

    /// 书籍标题（用于锁屏卡片顶部）。
    var bookTitle: String
    var chapterTitle: String
    /// 书籍 UUID 字符串，用于点按灵动岛跳回 App 继续读。
    var bookID: String
}
