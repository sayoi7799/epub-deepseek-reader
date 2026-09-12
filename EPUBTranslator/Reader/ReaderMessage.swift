import CoreGraphics
import Foundation

struct SelectionContext: Equatable {
    var paragraph: String
    var previousParagraph: String
    var nextParagraph: String

    static let empty = SelectionContext(paragraph: "", previousParagraph: "", nextParagraph: "")
}

struct ReaderSelection: Equatable {
    var text: String
    var anchorID: String
    var rect: CGRect
    var context: SelectionContext
}

enum ReaderMessage {
    case ready
    case progress(Double)
    case selection(text: String, anchorID: String, rect: CGRect, context: SelectionContext)
    case selectionCleared
    case paragraphTap(text: String, anchorID: String, rect: CGRect, context: SelectionContext)
    case link(href: String)

    init?(payload: [String: Any]) {
        guard let type = payload["type"] as? String else { return nil }

        let rect = ReaderMessage.rect(from: payload["rect"] as? [String: Any])
        let context = ReaderMessage.context(from: payload["context"] as? [String: Any])
        let text = (payload["text"] as? String) ?? ""
        let anchorID = (payload["anchorId"] as? String) ?? ""

        switch type {
        case "ready":
            self = .ready
        case "progress":
            let value = (payload["value"] as? NSNumber)?.doubleValue ?? 0
            self = .progress(value)
        case "selection":
            guard !text.isEmpty else { return nil }
            self = .selection(text: text, anchorID: anchorID, rect: rect, context: context)
        case "selectionCleared":
            self = .selectionCleared
        case "paragraphTap":
            guard !text.isEmpty else { return nil }
            self = .paragraphTap(text: text, anchorID: anchorID, rect: rect, context: context)
        case "link":
            let href = (payload["href"] as? String) ?? ""
            guard !href.isEmpty else { return nil }
            self = .link(href: href)
        default:
            return nil
        }
    }

    private static func rect(from payload: [String: Any]?) -> CGRect {
        guard let payload else { return .zero }
        let x = (payload["x"] as? NSNumber)?.doubleValue ?? 0
        let y = (payload["y"] as? NSNumber)?.doubleValue ?? 0
        let width = (payload["width"] as? NSNumber)?.doubleValue ?? 0
        let height = (payload["height"] as? NSNumber)?.doubleValue ?? 0
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private static func context(from payload: [String: Any]?) -> SelectionContext {
        guard let payload else { return .empty }
        return SelectionContext(
            paragraph: (payload["paragraph"] as? String) ?? "",
            previousParagraph: (payload["before"] as? String) ?? "",
            nextParagraph: (payload["after"] as? String) ?? ""
        )
    }
}
