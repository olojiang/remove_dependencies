import Foundation

public enum SortField: String, CaseIterable, Identifiable, Sendable {
    case name = "名称"
    case size = "大小"
    case modDate = "修改时间"

    public var id: String { rawValue }
}

public enum SortDirection: String, CaseIterable, Identifiable, Sendable {
    case ascending = "正序"
    case descending = "逆序"

    public var id: String { rawValue }

    public var isAscending: Bool { self == .ascending }
}
