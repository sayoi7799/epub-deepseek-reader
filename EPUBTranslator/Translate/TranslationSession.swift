import Foundation
import Observation

@MainActor
@Observable
final class TranslationSession: Identifiable {
    enum Phase: Equatable {
        case idle
        case translating
        case refining
        case done
        case failed(String)
        case cancelled
    }

    let id = UUID()
    let source: String
    let anchorID: String?
    let context: TranslationContext
    var style: TranslationStyle
    var phase: Phase = .idle
    var text: String = ""
    var usedCache = false
    var insertedInReader = false
    var modelName: String = ""

    init(source: String, anchorID: String?, context: TranslationContext, style: TranslationStyle) {
        self.source = source
        self.anchorID = anchorID
        self.context = context
        self.style = style
    }

    var isBusy: Bool {
        phase == .translating || phase == .refining
    }

    var hasContent: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var errorMessage: String? {
        if case .failed(let message) = phase { return message }
        return nil
    }

    /// 短按一个词和整段翻译，提示词策略不同。
    var taskKind: TranslationTaskKind {
        let words = source.split(whereSeparator: { $0.isWhitespace })
        if words.count <= 2 && source.count <= 24 {
            return .word
        }
        if source.count > 260 || source.contains("\n\n") {
            return .paragraph
        }
        return .selection
    }
}
