import Foundation

public struct DependencyItem: Identifiable, Hashable, Sendable {
    public let id: String
    public let path: URL
    public let type: DependencyType
    public let relativePath: String
    public let modificationDate: Date?
    public var sizeInBytes: Int64
    public var isSelected: Bool

    public init(
        path: URL,
        type: DependencyType,
        relativePath: String = "",
        modificationDate: Date? = nil,
        sizeInBytes: Int64 = 0,
        isSelected: Bool = false
    ) {
        self.id = path.path
        self.path = path
        self.type = type
        self.relativePath = relativePath.isEmpty ? type.rawValue : relativePath
        self.modificationDate = modificationDate
        self.sizeInBytes = sizeInBytes
        self.isSelected = isSelected
    }

    public var name: String { type.rawValue }

    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: sizeInBytes, countStyle: .file)
    }

    public var formattedDate: String {
        guard let date = modificationDate else { return "—" }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }
}
