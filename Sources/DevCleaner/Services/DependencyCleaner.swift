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
}
