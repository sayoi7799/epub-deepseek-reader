import Foundation

struct Chapter: Codable, Identifiable, Hashable {
    /// 相对解压目录的路径，例如 `OEBPS/text/chapter1.xhtml`。
    var href: String
    var title: String
    var order: Int

    var id: String { href }
}

struct Book: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var title: String
    var author: String
    var language: String
    /// 封面在解压目录中的相对路径。
    var coverPath: String?
    var sourceFileName: String
    var byteSize: Int
    var addedAt: Date = Date()
    var lastOpenedAt: Date?
    var chapters: [Chapter]
    var currentChapterIndex: Int = 0
    /// 当前章节内的阅读进度（0 ~ 1）。
    var chapterProgress: Double = 0
    /// 本书专属术语表：原文 -> 译文。
    var glossary: [String: String] = [:]

    var authorDisplay: String {
        let trimmed = author.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "未知作者" : trimmed
    }

    var totalProgress: Double {
        guard !chapters.isEmpty else { return 0 }
        let completed = Double(min(currentChapterIndex, chapters.count - 1))
        let within = min(max(chapterProgress, 0), 1)
        return min(1, (completed + within) / Double(chapters.count))
    }

    func chapter(at index: Int) -> Chapter? {
        guard index >= 0 && index < chapters.count else { return nil }
        return chapters[index]
    }

    var currentChapter: Chapter? {
        chapter(at: currentChapterIndex)
    }
}

struct ParsedBook {
    var title: String
    var author: String
    var language: String
    var coverPath: String?
    var chapters: [Chapter]
}
