import Foundation
import Observation

struct TranslationRecord: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var sourceText: String
    var translatedText: String
    var bookTitle: String?
    var chapterTitle: String?
    var styleRaw: String
    var model: String
    var createdAt: Date = Date()
    var isFavorite: Bool = false

    var style: TranslationStyle {
        TranslationStyle(rawValue: styleRaw) ?? .literary
    }

    var contextLine: String {
        var parts: [String] = []
        if let bookTitle, !bookTitle.isEmpty { parts.append("《\(bookTitle)》") }
        if let chapterTitle, !chapterTitle.isEmpty { parts.append(chapterTitle) }
        return parts.joined(separator: " · ")
    }
}

@MainActor
@Observable
final class HistoryStore {
    private(set) var records: [TranslationRecord] = []
    private let fileURL: URL
    private var pendingSave: Task<Void, Never>?
    private let limit = 3000

    init(fileURL: URL) {
        self.fileURL = fileURL
        load()
    }

    func add(_ record: TranslationRecord) {
        guard !record.translatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        records.insert(record, at: 0)
        if records.count > limit {
            records.removeLast(records.count - limit)
        }
        scheduleSave()
    }

    func update(_ record: TranslationRecord) {
        guard let index = records.firstIndex(where: { $0.id == record.id }) else { return }
        records[index] = record
        scheduleSave()
    }

    func delete(_ record: TranslationRecord) {
        records.removeAll { $0.id == record.id }
        scheduleSave()
    }

    func deleteAll() {
        records.removeAll()
        saveNow()
    }

    func toggleFavorite(_ record: TranslationRecord) {
        var updated = record
        updated.isFavorite.toggle()
        update(updated)
    }

    func exportMarkdown() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        var lines: [String] = ["# 译读 · 译文导出", ""]
        for record in records {
            let header = record.contextLine.isEmpty ? "" : " — \(record.contextLine)"
            lines.append("## \(formatter.string(from: record.createdAt))\(header)")
            lines.append("")
            lines.append("**原文**")
            lines.append("")
            lines.append(record.sourceText)
            lines.append("")
            lines.append("**译文**（\(record.style.title)）")
            lines.append("")
            lines.append(record.translatedText)
            lines.append("")
            lines.append("---")
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private func load() {
        guard
            let data = try? Data(contentsOf: fileURL),
            let decoded = try? JSONDecoder().decode([TranslationRecord].self, from: data)
        else { return }
        records = decoded
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        pendingSave?.cancel()
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: fileURL, options: [.atomic])
    }
}
