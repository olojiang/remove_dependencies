import Foundation

public struct DependencyCleaner: @unchecked Sendable {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func remove(items: [DependencyItem]) throws -> [URL] {
        var removed: [URL] = []
        for item in items where item.isSelected {
            guard fileManager.fileExists(atPath: item.path.path) else { continue }
            try fileManager.removeItem(at: item.path)
            removed.append(item.path)
        }
        return removed
    }

    public func remove(paths: [String]) throws -> [URL] {
        var removed: [URL] = []
        for path in paths {
            guard fileManager.fileExists(atPath: path) else { continue }
            let url = URL(fileURLWithPath: path)
            try fileManager.removeItem(at: url)
            removed.append(url)
        }
        return removed
    }

    public func removeWithElevatedFallback(items: [DependencyItem], password: String?) -> RemovalResult {
        removeWithElevatedFallback(paths: items.filter(\.isSelected).map(\.path.path), password: password)
    }

    public func removeWithElevatedFallback(paths: [String], password: String?) -> RemovalResult {
        var removed: [URL] = []
        var failed: [RemovalFailure] = []

        for path in paths {
            guard fileManager.fileExists(atPath: path) else { continue }
            let url = URL(fileURLWithPath: path)

            do {
                try fileManager.removeItem(at: url)
                removed.append(url)
                continue
            } catch {
                guard let password, !password.isEmpty else {
                    failed.append(RemovalFailure(path: url, message: error.localizedDescription))
                    continue
                }

                do {
                    try Self.removeUsingSudo(path: path, password: password)
                    if !fileManager.fileExists(atPath: path) {
                        removed.append(url)
                    } else {
                        failed.append(RemovalFailure(path: url, message: "sudo 删除后路径仍然存在"))
                    }
                } catch {
                    failed.append(RemovalFailure(path: url, message: error.localizedDescription))
                }
            }
        }

        return RemovalResult(removed: removed, failed: failed)
    }

    private static func removeUsingSudo(path: String, password: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        process.arguments = ["-k", "-S", "-p", "", "/bin/rm", "-rf", "--", path]

        let inputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardInput = inputPipe
        process.standardError = errorPipe

        try process.run()
        inputPipe.fileHandleForWriting.write(Data((password + "\n").utf8))
        try? inputPipe.fileHandleForWriting.close()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw RemovalError.elevatedRemovalFailed(message?.isEmpty == false ? message! : "sudo 删除失败")
        }
    }
}

public struct RemovalResult: Sendable {
    public let removed: [URL]
    public let failed: [RemovalFailure]

    public init(removed: [URL], failed: [RemovalFailure]) {
        self.removed = removed
        self.failed = failed
    }
}

public struct RemovalFailure: Sendable, Equatable {
    public let path: URL
    public let message: String

    public init(path: URL, message: String) {
        self.path = path
        self.message = message
    }
}

public enum RemovalError: LocalizedError {
    case elevatedRemovalFailed(String)

    public var errorDescription: String? {
        switch self {
        case .elevatedRemovalFailed(let message):
            return message
        }
    }
}
