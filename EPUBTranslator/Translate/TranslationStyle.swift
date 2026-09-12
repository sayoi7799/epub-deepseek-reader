import Foundation

enum TranslationStyle: String, CaseIterable, Identifiable, Codable {
    case literary
    case faithful
    case colloquial
    case academic
    case concise

    var id: String { rawValue }

    var title: String {
        switch self {
        case .literary: return "文学流畅"
        case .faithful: return "忠于原文"
        case .colloquial: return "口语自然"
        case .academic: return "学术严谨"
        case .concise: return "极简速读"
        }
    }

    var subtitle: String {
        switch self {
        case .literary: return "像中文作家直接写出来的文字，适合小说"
        case .faithful: return "信息完整、句序对齐，适合技术书"
        case .colloquial: return "像真人讲话，对白处理更好"
        case .academic: return "术语统一、逻辑清楚，适合论文专著"
        case .concise: return "只留核心意思，扫读最快"
        }
    }

    var systemImage: String {
        switch self {
        case .literary: return "book.closed"
        case .faithful: return "text.alignleft"
        case .colloquial: return "bubble.left.and.bubble.right"
        case .academic: return "graduationcap"
        case .concise: return "bolt"
        }
    }

    var instruction: String {
        switch self {
        case .literary:
            return "以中文文学的语感翻译：句子长短交错，避免逐词对应；比喻、语气、节奏都要在中文里重新成立。宁可改写句式，也不要留下翻译腔。"
        case .faithful:
            return "忠实优先：不增删信息、不合并句子、术语精确，尽量保持原文的句序和修辞结构，只做必要的最小语序调整。"
        case .colloquial:
            return "像中文母语者日常说话那样表达，可以用口语词和短句；对白要能听出人物口气，不要书面腔。"
        case .academic:
            return "严谨的书面语：术语前后统一，逻辑连接词准确，概念不加戏，保持客观中立的语气。"
        case .concise:
            return "只保留核心意思，用最短的中文说清楚，适合快速扫读；不求文采，但求准确、无歧义。"
        }
    }
}
