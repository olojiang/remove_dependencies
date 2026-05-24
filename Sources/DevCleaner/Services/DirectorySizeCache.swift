import Foundation

public struct DirectorySizeCache: @unchecked Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        public let sizeInBytes: Int64
        public let modificationTime: TimeInterval

        public init(sizeInBytes: Int64, modificationDate: Date) {
            self.sizeInBytes = sizeInBytes
            self.modificationTime = modificationDate.timeIntervalSince1970
        }

        public func matches(modificationDate: Date) -> Bool {
            modificationTime == modificationDate.timeIntervalSince1970
        }
    }

    private let defaults: UserDefaults
    private let storageKey: String

    public init(
        defaults: UserDefaults = .standard,
        storageKey: String = "directorySizeCache.v1"
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
    }

    public func cachedSize(for url: URL, modificationDate: Date?) -> Int64? {
        guard let modificationDate,
              let entry = entries()[url.path],
              entry.matches(modificationDate: modificationDate)
        else { return nil }

        return entry.sizeInBytes
    }

    public func store(sizeInBytes: Int64, for url: URL, modificationDate: Date?) {
        guard sizeInBytes >= 0, let modificationDate else { return }

        var currentEntries = entries()
        currentEntries[url.path] = Entry(sizeInBytes: sizeInBytes, modificationDate: modificationDate)
        save(currentEntries)
    }

    public func remove<S: Sequence>(paths: S) where S.Element == String {
        var currentEntries = entries()
        var didRemove = false

        for path in paths where currentEntries.removeValue(forKey: path) != nil {
            didRemove = true
        }

        if didRemove {
            save(currentEntries)
        }
    }

    public func clear() {
        defaults.removeObject(forKey: storageKey)
    }

    private func entries() -> [String: Entry] {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([String: Entry].self, from: data)
        else { return [:] }

        return decoded
    }

    private func save(_ entries: [String: Entry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
