import SwiftUI
import DevCleanerLib

@main
struct DevCleanerApp: App {
    var body: some Scene {
        WindowGroup("DevCleaner - 开发依赖清理") {
            ContentView()
                .frame(minWidth: 750, minHeight: 500)
        }
        .defaultSize(width: 900, height: 650)
    }
}
