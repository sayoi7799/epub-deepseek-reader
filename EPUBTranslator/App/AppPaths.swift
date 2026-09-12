import Foundation

enum AppPaths {
    static var root: URL {
        let supportRoot = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return supportRoot.appendingPathComponent("EPUBTranslator", isDirectory: true)
    }

    static var translationCacheURL: URL {
        root.appendingPathComponent("translation-cache.json")
    }

    static var historyURL: URL {
        root.appendingPathComponent("history.json")
    }
}
