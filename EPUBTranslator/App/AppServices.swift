import Foundation
import Observation

/// App 级别的依赖容器：在 App 启动时创建一次，通过 environment 注入。
@MainActor
@Observable
final class AppServices {
    /// 共享实例：App 界面和 App Intents 都从同一个实例读写数据。
    static let shared = AppServices()

    let settings: SettingsStore
    let library: LibraryStore
    let cache: TranslationCache
    let history: HistoryStore
    let engine: TranslationEngine
    let router: AppRouter
    let liveActivity: LiveActivityController

    init() {
        let settings = SettingsStore()
        let library = LibraryStore()
        let cache = TranslationCache(fileURL: AppPaths.translationCacheURL)
        let history = HistoryStore(fileURL: AppPaths.historyURL)
        let liveActivity = LiveActivityController()
        self.settings = settings
        self.library = library
        self.cache = cache
        self.history = history
        self.liveActivity = liveActivity
        self.engine = TranslationEngine(
            settings: settings,
            cache: cache,
            history: history,
            liveActivity: liveActivity
        )
        self.router = AppRouter()
    }

    func start() async {
        library.load()
        liveActivity.endAllStale()
        await library.importInboxIfNeeded()
        cache.saveNow()
        history.saveNow()
    }
}
