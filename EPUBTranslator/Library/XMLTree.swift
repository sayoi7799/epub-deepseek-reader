import Foundation

/// 一棵极简的 XML 树。EPUB 里的 container.xml / OPF / NCX / nav 都是 XML，
/// 用树结构比用 XMLParser 的代理状态机更好读。
final class XMLNode {
    let name: String
    let localName: String
    private(set) var attributes: [String: String]
    private(set) var children: [XMLNode] = []
    private(set) var text: String = ""
    weak var parent: XMLNode?

    init(name: String, attributes: [String: String]) {
        self.name = name
        self.attributes = attributes
        if let colonIndex = name.firstIndex(of: ":") {
            self.localName = String(name[name.index(after: colonIndex)...])
        } else {
            self.localName = name
        }
    }

    func append(child: XMLNode) {
        child.parent = self
        children.append(child)
    }

    func append(text fragment: String) {
        text += fragment
    }

    var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func child(named target: String) -> XMLNode? {
        children.first { $0.localName == target }
    }

    func children(named target: String) -> [XMLNode] {
        children.filter { $0.localName == target }
    }

    var allDescendants: [XMLNode] {
        children + children.flatMap { $0.allDescendants }
    }

    func descendants(named target: String) -> [XMLNode] {
        allDescendants.filter { $0.localName == target }
    }

    /// 先按完整属性名匹配，再按去掉命名空间前缀的属性名匹配。
    func attribute(named target: String) -> String? {
        if let value = attributes[target] { return value }
        for (key, value) in attributes where XMLNode.localName(of: key) == target {
            return value
        }
        return nil
    }

    static func localName(of qualifiedName: String) -> String {
        guard let colonIndex = qualifiedName.firstIndex(of: ":") else { return qualifiedName }
        return String(qualifiedName[qualifiedName.index(after: colonIndex)...])
    }
}

enum XMLTreeError: Error, LocalizedError {
    case emptyDocument
    case parseFailed(String)

    var errorDescription: String? {
        switch self {
        case .emptyDocument:
            return "XML 文档为空"
        case .parseFailed(let message):
            return "XML 解析失败：\(message)"
        }
    }
}

enum XMLTreeParser {
    static func parse(data: Data) throws -> XMLNode {
        let parser = XMLParser(data: data)
        let builder = Builder()
        parser.delegate = builder
        parser.shouldProcessNamespaces = false
        parser.shouldResolveExternalEntities = false
        guard parser.parse() else {
            if let root = builder.root { return root }
            let message = parser.parserError?.localizedDescription ?? "未知错误"
            throw XMLTreeError.parseFailed(message)
        }
        guard let root = builder.root else { throw XMLTreeError.emptyDocument }
        return root
    }

    static func parse(string: String) throws -> XMLNode {
        try parse(data: Data(string.utf8))
    }

    private final class Builder: NSObject, XMLParserDelegate {
        var root: XMLNode?
        private var stack: [XMLNode] = []

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?,
            attributes attributeDict: [String: String] = [:]
        ) {
            let node = XMLNode(name: elementName, attributes: attributeDict)
            if let parent = stack.last {
                parent.append(child: node)
            } else if root == nil {
                root = node
            }
            stack.append(node)
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            stack.last?.append(text: string)
        }

        func parser(
            _ parser: XMLParser,
            didEndElement elementName: String,
            namespaceURI: String?,
            qualifiedName qName: String?
        ) {
            if !stack.isEmpty {
                stack.removeLast()
            }
        }
    }
}
