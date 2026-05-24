import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var didInstallWindowCloseObserver = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return }

        let currentPID = ProcessInfo.processInfo.processIdentifier
        if let existingApp = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .first(where: { $0.processIdentifier != currentPID }) {
            AppLogger.shared.info("Another instance is already running; activating pid \(existingApp.processIdentifier)")
            existingApp.activate(options: [.activateAllWindows])
            NSApp.terminate(nil)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        installWindowCloseObserver()

        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            for window in NSApp.windows where window.canBecomeMain {
                window.makeKeyAndOrderFront(nil)
                if !window.isZoomed {
                    window.zoom(nil)
                }
            }
            AppLogger.shared.info("Main window activated and maximized")
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        AppLogger.shared.info("Last window closed; terminating application")
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppLogger.shared.info("DevCleaner terminating")
    }

    private func installWindowCloseObserver() {
        guard !didInstallWindowCloseObserver else { return }
        didInstallWindowCloseObserver = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )
    }

    @objc private func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow, closingWindow.canBecomeMain else { return }

        DispatchQueue.main.async {
            let visibleMainWindows = NSApp.windows.filter {
                $0 !== closingWindow && $0.canBecomeMain && $0.isVisible
            }
            if visibleMainWindows.isEmpty {
                AppLogger.shared.info("Main window closed; terminating application")
                NSApp.terminate(nil)
            }
        }
    }
}
