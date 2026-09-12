import Foundation

enum EPUBError: Error, LocalizedError {
    case missingContainer
    case missingPackage
    case emptySpine
    case notFound(String)

    var errorDescription: String? {
        switch self {
        case .missingContainer:
            return "EPUB 缺少 META-INF/container.xml"
        case .missingPackage:
            return "EPUB 缺少 OPF 包文件"
        case .emptySpine:
            return "EPUB 里没有可阅读的章节"
        case .notFound(let path):
            return "EPUB 里找不到文件：\(path)"
        }
    }
}

struct EPUBParser {
    /// 解压 EPUB 到 `bookFolder/content`，复制原始文件，并解析出书籍信息。
    static func importEPUB(from sourceURL: URL, to bookFolder: URL, sourceFileName: String) throws -> ParsedBook {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: bookFolder, withIntermediateDirectories: true)

        let contentURL = bookFolder.appendingPathComponent("content", isDirectory: true)
        if fileManager.fileExists(atPath: contentURL.path) {
            try fileManager.removeItem(at: contentURL)
        }
        let archive = try ZipArchive(url: sourceURL)
        try archive.extract(to: contentURL)

        let originalURL = bookFolder.appendingPathComponent("original.epub")
        if fileManager.fileExists(atPath: originalURL.path) {
            try fileManager.removeItem(at: originalURL)
        }
        try? fileManager.copyItem(at: sourceURL, to: originalURL)

        return try parse(contentRoot: contentURL, defaultTitle: (sourceFileName as NSString).deletingPathExtension)
    }

    /// - Parameter defaultTitle: 书里没有 dc:title 时使用的书名（注意不要叫 fallbackTitle，
    ///   否则会遮住下面的 `fallbackTitle(for:index:)` 方法）。
    static func parse(contentRoot: URL, defaultTitle: String = "未命名书籍") throws -> ParsedBook {
        let containerURL = contentRoot.appendingPathComponent("META-INF/container.xml")
        guard let containerData = try? Data(contentsOf: containerURL) else {
            throw EPUBError.missingContainer
        }
        let containerRoot = try XMLTreeParser.parse(data: containerData)
        guard
            let rootfile = containerRoot.descendants(named: "rootfile").first,
            let packagePath = rootfile.attribute(named: "full-path")
        else {
            throw EPUBError.missingPackage
        }

        let packageRelativePath = normalize(packagePath)
        let packageURL = fileURL(root: contentRoot, relativePath: packageRelativePath)
        guard let packageData = try? Data(contentsOf: packageURL) else {
            throw EPUBError.notFound(packageRelativePath)
        }
        let packageRoot = try XMLTreeParser.parse(data: packageData)
        let packageDirectory = directory(of: packageRelativePath)

        let metadata = packageRoot.child(named: "metadata")
        let title = metadata?.descendants(named: "title").first?.trimmedText ?? ""
        let creator = metadata?.descendants(named: "creator").first?.trimmedText ?? ""
        let language = metadata?.descendants(named: "language").first?.trimmedText ?? ""

        var manifest: [String: ManifestItem] = [:]
        for item in packageRoot.descendants(named: "item") {
            guard
                let id = item.attribute(named: "id"),
                let href = item.attribute(named: "href")
            else { continue }
            manifest[id] = ManifestItem(
                id: id,
                href: href,
                mediaType: item.attribute(named: "media-type") ?? "",
                properties: item.attribute(named: "properties") ?? ""
            )
        }

        let spine = packageRoot.child(named: "spine")
        let itemrefs = spine?.children(named: "itemref") ?? []

        var chapterPaths: [String] = []
        for itemref in itemrefs {
            guard
                let idref = itemref.attribute(named: "idref"),
                let item = manifest[idref]
            else { continue }
            guard item.mediaType.contains("html") else { continue }
            let path = resolve(base: packageDirectory, href: item.href)
            guard !chapterPaths.contains(path) else { continue }
            chapterPaths.append(path)
        }

        if chapterPaths.isEmpty {
            // 少数 EPUB 的 spine 不完整，退化成按清单里的 HTML 排序。
            let fallback = manifest.values
                .filter { $0.mediaType.contains("html") }
                .map { resolve(base: packageDirectory, href: $0.href) }
                .sorted()
            chapterPaths = Array(Set(fallback)).sorted()
        }

        guard !chapterPaths.isEmpty else { throw EPUBError.emptySpine }

        let toc = tableOfContents(packageRoot: packageRoot, manifest: manifest, packageDirectory: packageDirectory)

        var chapters: [Chapter] = []
        for (index, path) in chapterPaths.enumerated() {
            let title = toc[path] ?? fallbackTitle(for: path, index: index)
            chapters.append(Chapter(href: path, title: title, order: index))
        }

        let coverPath = cover(
            packageRoot: packageRoot,
            metadata: metadata,
            manifest: manifest,
            packageDirectory: packageDirectory
        )

        return ParsedBook(
            title: title.isEmpty ? defaultTitle : title,
            author: creator,
            language: language,
            coverPath: coverPath,
            chapters: chapters
        )
    }

    private struct ManifestItem {
        var id: String
        var href: String
        var mediaType: String
        var properties: String
    }

    // MARK: - 目录

    private static func tableOfContents(
        packageRoot: XMLNode,
        manifest: [String: ManifestItem],
        packageDirectory: String
    ) -> [String: String] {
        var result: [String: String] = [:]

        // EPUB 3：nav 文档里的 epub:type="toc"。
        if let navItem = manifest.values.first(where: { $0.properties.contains("nav") }) {
            let navPath = resolve(base: packageDirectory, href: navItem.href)
            let navDirectory = directory(of: navPath)
            if let data = try? Data(contentsOf: URL(fileURLWithPath: navPath)) {
                if let root = try? XMLTreeParser.parse(data: data) {
                    let navs = root.descendants(named: "nav")
                    let tocNav = navs.first { ($0.attribute(named: "type") ?? "").contains("toc") } ?? navs.first
                    for anchor in tocNav?.descendants(named: "a") ?? [] {
                        guard let href = anchor.attribute(named: "href") else { continue }
                        let label = anchor.trimmedText.isEmpty ? (anchor.children(named: "span").first?.trimmedText ?? "") : anchor.trimmedText
                        record(into: &result, base: navDirectory, href: href, title: label)
                    }
                }
            }
        }

        // EPUB 2：toc.ncx。
        let spineTOCID = packageRoot.child(named: "spine")?.attribute(named: "toc")
        let ncxItem = spineTOCID.flatMap { manifest[$0] }
            ?? manifest.values.first { $0.mediaType.contains("dtbncx") }
        if let ncxItem {
            let ncxPath = resolve(base: packageDirectory, href: ncxItem.href)
            let ncxDirectory = directory(of: ncxPath)
            if let data = try? Data(contentsOf: URL(fileURLWithPath: ncxPath)),
               let root = try? XMLTreeParser.parse(data: data) {
                for navPoint in root.descendants(named: "navPoint") {
                    guard
                        let label = navPoint.child(named: "navLabel")?.child(named: "text")?.trimmedText,
                        let src = navPoint.child(named: "content")?.attribute(named: "src")
                    else { continue }
                    record(into: &result, base: ncxDirectory, href: src, title: label)
                }
            }
        }

        return result
    }

    private static func record(into result: inout [String: String], base: String, href: String, title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let path = resolve(base: base, href: href)
        if result[path] == nil {
            result[path] = trimmed
        }
    }

    // MARK: - 封面

    private static func cover(
        packageRoot: XMLNode,
        metadata: XMLNode?,
        manifest: [String: ManifestItem],
        packageDirectory: String
    ) -> String? {
        if let item = manifest.values.first(where: { $0.properties.contains("cover-image") }) {
            return resolve(base: packageDirectory, href: item.href)
        }
        let coverID = metadata?
            .descendants(named: "meta")
            .first { ($0.attribute(named: "name") ?? "") == "cover" }?
            .attribute(named: "content")
        if let coverID, let item = manifest[coverID] {
            return resolve(base: packageDirectory, href: item.href)
        }
        return nil
    }

    // MARK: - 路径工具

    /// 把相对路径规范化成不带 `.` / `..` 的相对路径。
    static func normalize(_ path: String) -> String {
        let decoded = path.removingPercentEncoding ?? path
        var components: [String] = []
        for component in decoded.split(separator: "/", omittingEmptySubsequences: true) {
            switch component {
            case ".":
                continue
            case "..":
                if !components.isEmpty { components.removeLast() }
            default:
                components.append(String(component))
            }
        }
        return components.joined(separator: "/")
    }

    /// 以 `base` 目录为基准解析 `href`（会去掉 `#fragment` 和 `?query`）。
    static func resolve(base: String, href: String) -> String {
        let decoded = href.removingPercentEncoding ?? href
        var path = decoded
        if let hashIndex = path.firstIndex(of: "#") {
            path = String(path[path.startIndex..<hashIndex])
        }
        if let queryIndex = path.firstIndex(of: "?") {
            path = String(path[path.startIndex..<queryIndex])
        }
        if path.hasPrefix("/") {
            return normalize(path)
        }
        let combined = base.isEmpty ? path : base + "/" + path
        return normalize(combined)
    }

    static func directory(of path: String) -> String {
        guard let index = path.lastIndex(of: "/") else { return "" }
        return String(path[path.startIndex..<index])
    }

    static func fileURL(root: URL, relativePath: String) -> URL {
        let normalized = normalize(relativePath)
        return URL(fileURLWithPath: root.path + "/" + normalized)
    }

    private static func fallbackTitle(for path: String, index: Int) -> String {
        let name = path.split(separator: "/").last.map(String.init) ?? path
        if name.hasPrefix("chapter") {
            let digits = name.drop(while: { !$0.isNumber }).prefix(while: { $0.isNumber })
            if !digits.isEmpty {
                return "第 \(Int(digits) ?? (index + 1)) 章"
            }
        }
        return "第 \(index + 1) 章"
    }

}
