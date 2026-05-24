import SwiftUI

@main
struct DevCleanerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        AppLogger.shared.configure()
        AppLogger.shared.info("DevCleaner starting")
    }

    var body: some Scene {
        WindowGroup("DevCleaner 纪 - 开发依赖清理") {
            ContentView()
                .frame(minWidth: 750, minHeight: 500)
        }
        .defaultSize(width: 900, height: 650)
    }
}
