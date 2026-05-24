import Foundation

final class AppLogger {
    static let shared = AppLogger()

    private let queue = DispatchQueue(label: "com.devcleaner.app.filelogger")
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
    private let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()

    private var logDirectory: URL?

    private init() {}

    func configure() {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let directory = baseURL.appendingPathComponent("DevCleaner/logs", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            logDirectory = directory
            pruneLogs(in: directory)
        } catch {
            fputs("DevCleaner logger setup failed: \(error.localizedDescription)\n", stderr)
        }
    }

    func info(_ message: String) {
        write(level: "INFO", message: message)
    }

    func error(_ message: String) {
        write(level: "ERROR", message: message)
    }

    private func write(level: String, message: String) {
        queue.async {
            if self.logDirectory == nil {
                self.configure()
            }
            guard let directory = self.logDirectory else { return }

            let now = Date()
            let line = "[\(self.timestampFormatter.string(from: now))] [\(level)] \(message)\n"
            let logURL = directory.appendingPathComponent("devcleaner-\(self.dateFormatter.string(from: now)).log")

            do {
                if !FileManager.default.fileExists(atPath: logURL.path) {
                    FileManager.default.createFile(atPath: logURL.path, contents: nil)
                    self.pruneLogs(in: directory)
                }
                let handle = try FileHandle(forWritingTo: logURL)
                defer { try? handle.close() }
                try handle.seekToEnd()
                if let data = line.data(using: .utf8) {
                    try handle.write(contentsOf: data)
                }
            } catch {
                fputs("DevCleaner log write failed: \(error.localizedDescription)\n", stderr)
            }
        }
    }

    private func pruneLogs(in directory: URL) {
        do {
            let logs = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
            .filter { $0.lastPathComponent.hasPrefix("devcleaner-") && $0.pathExtension == "log" }
            .sorted {
                let left = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let right = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return left > right
            }

            for staleLog in logs.dropFirst(7) {
                try? FileManager.default.removeItem(at: staleLog)
            }
        } catch {
            fputs("DevCleaner log pruning failed: \(error.localizedDescription)\n", stderr)
        }
    }
}
