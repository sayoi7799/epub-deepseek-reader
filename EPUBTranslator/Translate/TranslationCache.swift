import Foundation
import CryptoKit
import Observation

/// 翻译结果缓存：同一段文字、同一风格只花钱翻译一次。
@MainActor
@Observable
final class TranslationCache {
    private(set) var entries: [String: String] = [:]
    private let fileURL: URL
    private var pendingSave: Task<Void, Never>?
    private let limit = 4000

    var count: Int { entries.count }

    init(fileURL: URL) {
        self.fileURL = fileURL
        load()
    }

    static func key(
        text: String,
        style: TranslationStyle,
        targetLanguage: TargetLanguage,
        model: String,
        instruction: String,
        context: TranslationContext,
        kind: TranslationTaskKind
    ) -> String {
        let contextPart = [
            context.bookTitle ?? "",
            context.chapterTitle ?? "",
            context.paragraph ?? "",
            context.previousParagraph ?? "",
            context.nextParagraph ?? "",
        ].joined(separator: "\u{1}")
        let raw = [
            "v1",
            model,
            style.rawValue,
            targetLanguage.rawValue,
            kind.rawValue,
            instruction,
            contextPart,
            text,
        ].joined(separator: "\u{2}")
        return SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func value(for key: String) -> String? {
        entries[key]
    }

    func store(_ value: String, for key: String) {
        entries[key] = value
        if entries.count > limit {
            let overflow = entries.count - limit
            for keyToRemove in entries.keys.prefix(overflow) {
                entries.removeValue(forKey: keyToRemove)
            }
        }
        scheduleSave()
    }

    func clear() {
        entries.removeAll()
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func load() {
        guard
            let data = try? Data(contentsOf: fileURL),
            let decoded = try? JSONDecoder().decode([String: String].self, from: data)
        else { return }
        entries = decoded
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        pendingSave?.cancel()
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: fileURL, options: [.atomic])
    }
}
