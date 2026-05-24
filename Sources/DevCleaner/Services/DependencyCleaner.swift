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
}
