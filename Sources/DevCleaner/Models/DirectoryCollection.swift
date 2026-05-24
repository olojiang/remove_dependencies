import Foundation

public struct DirectoryCollectionItem: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let path: String
    public let relativePath: String
    public let typeName: String
    public let sizeInBytes: Int64
    public var isSelected: Bool

    public init(
        path: String,
        relativePath: String,
        typeName: String,
        sizeInBytes: Int64,
        isSelected: Bool = true
    ) {
        self.id = path
        self.path = path
        self.relativePath = relativePath
        self.typeName = typeName
        self.sizeInBytes = sizeInBytes
        self.isSelected = isSelected
    }

    public init(dependency: DependencyItem) {
        self.init(
            path: dependency.path.path,
            relativePath: dependency.relativePath,
            typeName: dependency.type.displayName,
            sizeInBytes: dependency.sizeInBytes,
            isSelected: true
        )
    }

    public var displayName: String {
        URL(fileURLWithPath: path).lastPathComponent
    }

    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: sizeInBytes, countStyle: .file)
    }
}

public struct DirectoryCollection: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var createdAt: Date
    public var updatedAt: Date
    public var items: [DirectoryCollectionItem]

    public init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        items: [DirectoryCollectionItem]
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.items = items
    }

    public var selectedItems: [DirectoryCollectionItem] {
        items.filter(\.isSelected)
    }

    public var selectedSize: Int64 {
        selectedItems.reduce(0) { $0 + $1.sizeInBytes }
    }

    public var formattedSelectedSize: String {
        ByteCountFormatter.string(fromByteCount: selectedSize, countStyle: .file)
    }
}
