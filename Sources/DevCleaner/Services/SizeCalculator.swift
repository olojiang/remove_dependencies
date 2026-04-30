import Foundation

public struct SizeCalculator: @unchecked Sendable {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func directorySize(at url: URL) throws -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey],
            options: []
        ) else { return 0 }

        var totalSize: Int64 = 0
        for case let fileURL as URL in enumerator {
            do {
                let values = try fileURL.resourceValues(forKeys: [
                    .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey
                ])
                guard values.isRegularFile == true else { continue }
                let size = values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0
                totalSize += Int64(size)
            } catch {
                continue
            }
        }
        return totalSize
    }

    public func modificationDate(at url: URL) -> Date? {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        return values?.contentModificationDate
    }
}
