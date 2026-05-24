import Foundation

public struct DirectoryCollectionStore {
    private let defaults: UserDefaults
    private let storageKey: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(
        defaults: UserDefaults = .standard,
        storageKey: String = "directoryCollections"
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    public func load() -> [DirectoryCollection] {
        guard let data = defaults.data(forKey: storageKey) else { return [] }
        do {
            return try decoder.decode([DirectoryCollection].self, from: data)
        } catch {
            return []
        }
    }

    public func save(_ collections: [DirectoryCollection]) {
        guard let data = try? encoder.encode(collections) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
