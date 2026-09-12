import Foundation
import Observation

enum DeepSeekModel: String, CaseIterable, Identifiable, Codable {
    case chat = "deepseek-chat"
    case reasoner = "deepseek-reasoner"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chat: return "deepseek-chat"
        case .reasoner: return "deepseek-reasoner"
        }
    }

    var detail: String {
        switch self {
        case .chat: return "通用模型，速度快、便宜，适合日常阅读翻译"
        case .reasoner: return "带思维链的推理模型，长难句和文学性更强，速度较慢"
        }
    }
}

enum TargetLanguage: String, CaseIterable, Identifiable, Codable {
    case simplifiedChinese
    case traditionalChinese
    case english

    var id: String { rawValue }

    var title: String {
        switch self {
        case .simplifiedChinese: return "简体中文"
        case .traditionalChinese: return "繁體中文"
        case .english: return "English"
        }
    }
}

@MainActor
@Observable
final class SettingsStore {
    private enum Key {
        static let apiKeyAccount = "deepseek.apiKey"
        static let baseURL = "settings.baseURL"
        static let model = "settings.model"
        static let temperature = "settings.temperature"
        static let maxTokens = "settings.maxTokens"
        static let style = "settings.style"
        static let targetLanguage = "settings.targetLanguage"
        static let customInstruction = "settings.customInstruction"
        static let highQuality = "settings.highQuality"
        static let streaming = "settings.streaming"
        static let tapToTranslate = "settings.tapToTranslate"
        static let selectToTranslate = "settings.selectToTranslate"
        static let autoInsert = "settings.autoInsert"
        static let appearance = "settings.appearance"
        static let glossary = "settings.glossary"
        static let useBookContext = "settings.useBookContext"
        static let liveActivity = "settings.liveActivity"
    }

    private let defaults = UserDefaults.standard

    // MARK: - DeepSeek

    var apiKey: String = "" {
        didSet {
            guard apiKey != oldValue else { return }
            if apiKey.isEmpty {
                KeychainStore.delete(account: Key.apiKeyAccount)
            } else {
                KeychainStore.save(apiKey, account: Key.apiKeyAccount)
            }
        }
    }

    var baseURLString: String = "https://api.deepseek.com" {
        didSet { defaults.set(baseURLString, forKey: Key.baseURL) }
    }

    var model: DeepSeekModel = .chat {
        didSet { defaults.set(model.rawValue, forKey: Key.model) }
    }

    /// DeepSeek 官方建议：翻译任务用 1.3 的温度会明显更自然。
    var temperature: Double = 1.3 {
        didSet { defaults.set(temperature, forKey: Key.temperature) }
    }

    /// 0 表示不限制输出长度。
    var maxTokens: Int = 0 {
        didSet { defaults.set(maxTokens, forKey: Key.maxTokens) }
    }

    // MARK: - 翻译行为

    var defaultStyle: TranslationStyle = .literary {
        didSet { defaults.set(defaultStyle.rawValue, forKey: Key.style) }
    }

    var targetLanguage: TargetLanguage = .simplifiedChinese {
        didSet { defaults.set(targetLanguage.rawValue, forKey: Key.targetLanguage) }
    }

    var customInstruction: String = "" {
        didSet { defaults.set(customInstruction, forKey: Key.customInstruction) }
    }

    var glossaryText: String = "" {
        didSet { defaults.set(glossaryText, forKey: Key.glossary) }
    }

    /// 开启后每次翻译会做一次「初稿 + 润色」两遍处理，质量更好但更慢更贵。
    var highQuality: Bool = false {
        didSet { defaults.set(highQuality, forKey: Key.highQuality) }
    }

    var streaming: Bool = true {
        didSet { defaults.set(streaming, forKey: Key.streaming) }
    }

    /// 翻译时把前后文一起发给模型，代词和语气判断会准确很多。
    var useBookContext: Bool = true {
        didSet { defaults.set(useBookContext, forKey: Key.useBookContext) }
    }

    // MARK: - 阅读交互

    var tapToTranslate: Bool = true {
        didSet { defaults.set(tapToTranslate, forKey: Key.tapToTranslate) }
    }

    var selectToTranslate: Bool = true {
        didSet { defaults.set(selectToTranslate, forKey: Key.selectToTranslate) }
    }

    var autoInsertTranslation: Bool = false {
        didSet { defaults.set(autoInsertTranslation, forKey: Key.autoInsert) }
    }

    /// 翻译时把进度和译文推到灵动岛 / 锁屏。
    var liveActivityEnabled: Bool = true {
        didSet { defaults.set(liveActivityEnabled, forKey: Key.liveActivity) }
    }

    var appearance: ReaderAppearance = ReaderAppearance() {
        didSet {
            guard appearance != oldValue else { return }
            if let data = try? JSONEncoder().encode(appearance) {
                defaults.set(data, forKey: Key.appearance)
            }
        }
    }

    init() {
        apiKey = KeychainStore.read(account: Key.apiKeyAccount) ?? ""
        if let value = defaults.string(forKey: Key.baseURL), !value.isEmpty {
            baseURLString = value
        }
        if let raw = defaults.string(forKey: Key.model), let value = DeepSeekModel(rawValue: raw) {
            model = value
        }
        if defaults.object(forKey: Key.temperature) != nil {
            temperature = defaults.double(forKey: Key.temperature)
        }
        if defaults.object(forKey: Key.maxTokens) != nil {
            maxTokens = defaults.integer(forKey: Key.maxTokens)
        }
        if let raw = defaults.string(forKey: Key.style), let value = TranslationStyle(rawValue: raw) {
            defaultStyle = value
        }
        if let raw = defaults.string(forKey: Key.targetLanguage), let value = TargetLanguage(rawValue: raw) {
            targetLanguage = value
        }
        customInstruction = defaults.string(forKey: Key.customInstruction) ?? ""
        glossaryText = defaults.string(forKey: Key.glossary) ?? ""
        highQuality = defaults.bool(forKey: Key.highQuality)
        streaming = defaults.object(forKey: Key.streaming) as? Bool ?? true
        useBookContext = defaults.object(forKey: Key.useBookContext) as? Bool ?? true
        tapToTranslate = defaults.object(forKey: Key.tapToTranslate) as? Bool ?? true
        selectToTranslate = defaults.object(forKey: Key.selectToTranslate) as? Bool ?? true
        autoInsertTranslation = defaults.bool(forKey: Key.autoInsert)
        liveActivityEnabled = defaults.object(forKey: Key.liveActivity) as? Bool ?? true
        if let data = defaults.data(forKey: Key.appearance),
           let decoded = try? JSONDecoder().decode(ReaderAppearance.self, from: data) {
            appearance = decoded
        }
    }

    // MARK: - 派生

    var isConfigured: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var completionsURL: URL? {
        var text = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasSuffix("/") { text.removeLast() }
        if text.isEmpty { text = "https://api.deepseek.com" }
        if text.hasSuffix("/chat/completions") { return URL(string: text) }
        return URL(string: text + "/chat/completions")
    }

    /// 全局术语表，每行「原文=译文」或「原文 译文」。
    var glossary: [String: String] {
        var result: [String: String] = [:]
        for rawLine in glossaryText.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") { continue }
            let separator: Character? = line.contains("=") ? "=" : (line.contains("\t") ? "\t" : nil)
            guard let separator else { continue }
            let parts = line.split(separator: separator, maxSplits: 1, omittingEmptySubsequences: true)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces)
            let value = parts[1].trimmingCharacters(in: .whitespaces)
            if !key.isEmpty && !value.isEmpty {
                result[key] = value
            }
        }
        return result
    }
}
