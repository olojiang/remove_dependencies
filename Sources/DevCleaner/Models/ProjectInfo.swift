import Foundation

public struct ProjectInfo: Identifiable, Hashable, Sendable {
    public let id: String
    public let path: URL
    public let name: String
    public var dependencies: [DependencyItem]
    public var isExpanded: Bool

    public init(path: URL, dependencies: [DependencyItem] = [], isExpanded: Bool = true) {
        self.id = path.path
        self.path = path
        self.name = path.lastPathComponent
        self.dependencies = dependencies
        self.isExpanded = isExpanded
    }

    public var totalSize: Int64 {
        dependencies.reduce(0) { $0 + $1.sizeInBytes }
    }

    public var selectedSize: Int64 {
        dependencies.filter(\.isSelected).reduce(0) { $0 + $1.sizeInBytes }
    }

    public var hasSelectedItems: Bool {
        dependencies.contains { $0.isSelected }
    }

    public var formattedTotalSize: String {
        ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }
}
