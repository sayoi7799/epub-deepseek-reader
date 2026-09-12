import SwiftUI

@main
struct EPUBTranslatorApp: App {
    @State private var services = AppServices.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(services.settings)
                .environment(services.library)
                .environment(services.cache)
                .environment(services.history)
                .environment(services.engine)
                .environment(services.router)
                .task {
                    await services.start()
                }
                .onOpenURL { url in
                    services.router.handleIncoming(url: url)
                }
        }
    }
}
