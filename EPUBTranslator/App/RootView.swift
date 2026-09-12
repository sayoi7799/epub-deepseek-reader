import SwiftUI

struct RootView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(LibraryStore.self) private var library
    @Environment(AppRouter.self) private var router

    @State private var libraryPath: [Book] = []

    var body: some View {
        @Bindable var router = router

        TabView(selection: $router.selectedTab) {
            NavigationStack(path: $libraryPath) {
                LibraryView()
                    .navigationDestination(for: Book.self) { book in
                        ReaderView(book: book)
                    }
            }
            .tabItem { Label(AppRouter.Tab.library.title, systemImage: AppRouter.Tab.library.systemImage) }
            .tag(AppRouter.Tab.library)

            NavigationStack {
                HistoryView()
            }
            .tabItem { Label(AppRouter.Tab.history.title, systemImage: AppRouter.Tab.history.systemImage) }
            .tag(AppRouter.Tab.history)

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label(AppRouter.Tab.settings.title, systemImage: AppRouter.Tab.settings.systemImage) }
            .tag(AppRouter.Tab.settings)
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
}
