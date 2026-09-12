import Foundation
import Observation

@MainActor
@Observable
final class AppRouter {
    enum Tab: String, CaseIterable, Identifiable {
        case library
        case history
        case settings

        var id: String { rawValue }

        var title: String {
            switch self {
            case .library: return "书架"
            case .history: return "译文"
            case .settings: return "设置"
            }
        }

        var systemImage: String {
            switch self {
            case .library: return "books.vertical"
            case .history: return "text.book.closed"
            case .settings: return "gearshape"
            }
        }
    }

    var selectedTab: Tab = .library
    /// 由快捷指令 / App Intent 触发的「继续阅读」。
    var bookToOpen: Book?
    /// 从 Files 或其它 App 打开进来的 EPUB 文件地址。
    var incomingFileURL: URL?
    /// 灵动岛 / 锁屏卡片点按后想打开的书。
    var pendingBookID: UUID?

    func open(_ book: Book) {
        selectedTab = .library
        bookToOpen = book
    }

    func handleIncoming(url: URL) {
        if url.isFileURL {
            incomingFileURL = url
            return
        }
        guard url.scheme?.lowercased() == "epubtranslator" else { return }
        if let uuid = UUID(uuidString: url.lastPathComponent) {
            pendingBookID = uuid
        } else {
            selectedTab = .library
        }
    }
}
