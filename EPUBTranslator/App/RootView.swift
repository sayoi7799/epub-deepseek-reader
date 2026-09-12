import SwiftUI

struct RootView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(LibraryStore.self) private var library
    @Environment(AppRouter.self) private var router
    @Environment(TranslationEngine.self) private var engine

    @State private var libraryPath: [Book] = []

    var body: some View {
        @Bindable var router = router

        TabView(selection: $router.selectedTab) {
            libraryTab
            historyTab
            settingsTab
        }
        .onChange(of: router.bookToOpen) { _, newValue in
            guard let book = newValue else { return }
            router.selectedTab = .library
            libraryPath = [book]
            router.bookToOpen = nil
        }
        .onAppear {
            // 快捷指令可能在界面还没起来时就已经设置好了要打开的书。
            guard let book = router.bookToOpen else { return }
            router.selectedTab = .library
            libraryPath = [book]
            router.bookToOpen = nil
        }
        .onChange(of: router.incomingFileURL) { _, newValue in
            guard let url = newValue else { return }
            router.incomingFileURL = nil
            Task {
                if let book = try? await library.importBook(from: url) {
                    router.selectedTab = .library
                    libraryPath = [book]
                }
            }
        }
        .onChange(of: router.pendingBookID) { _, _ in
            openPendingBook()
        }
        .onChange(of: library.books) { _, _ in
            openPendingBook()
        }
        .onAppear {
            openPendingBook()
        }
        .tint(settings.appearance.theme.isDark ? .white : .accentColor)
    }

    /// 灵动岛 / 锁屏卡片点按后跳回那本书（书可能还没加载完，所以多处都调一次）。
    private func openPendingBook() {
        guard
            let id = router.pendingBookID,
            let book = library.book(with: id)
        else { return }
        router.pendingBookID = nil
        router.selectedTab = .library
        libraryPath = [book]
    }

    // 每个 tab 拆成独立属性：整个 body 写成一坨大表达式时，
    // 编译器会因为类型推断太复杂而报 "unable to type-check this expression in reasonable time"。
    private var libraryTab: some View {
        NavigationStack(path: $libraryPath) {
            LibraryView()
                .navigationDestination(for: Book.self) { book in
                    ReaderView(book: book, library: library, settings: settings, engine: engine)
                }
        }
        .tabItem { tabLabel(.library) }
        .tag(AppRouter.Tab.library)
    }

    private var historyTab: some View {
        NavigationStack {
            HistoryView()
        }
        .tabItem { tabLabel(.history) }
        .tag(AppRouter.Tab.history)
    }

    private var settingsTab: some View {
        NavigationStack {
            SettingsView()
        }
        .tabItem { tabLabel(.settings) }
        .tag(AppRouter.Tab.settings)
    }

    private func tabLabel(_ tab: AppRouter.Tab) -> some View {
        Label(tab.title, systemImage: tab.systemImage)
    }
}
