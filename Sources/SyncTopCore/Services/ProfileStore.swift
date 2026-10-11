import Foundation

/// Manages loading and saving sync profiles and run history to disk in Application Support.
public actor ProfileStore {
    private let fileManager = FileManager.default
    private let storageDirectory: URL
    private let profilesFileURL: URL
    private let historyFileURL: URL

    public init(customStorageDirectory: URL? = nil) {
        if let custom = customStorageDirectory {
            self.storageDirectory = custom
        } else {
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.storageDirectory = appSupport.appendingPathComponent("SyncTop", isDirectory: true)
        }
        self.profilesFileURL = self.storageDirectory.appendingPathComponent("profiles.json")
        self.historyFileURL = self.storageDirectory.appendingPathComponent("history.json")
    }

    private func ensureDirectoryExists() throws {
        if !fileManager.fileExists(atPath: storageDirectory.path) {
            try fileManager.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        }
    }

    // MARK: - Profiles

    public func loadProfiles() throws -> [SyncProfile] {
        guard fileManager.fileExists(atPath: profilesFileURL.path) else {
            return []
        }
        let data = try Data(contentsOf: profilesFileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([SyncProfile].self, from: data)
    }

    public func saveProfiles(_ profiles: [SyncProfile]) throws {
        try ensureDirectoryExists()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(profiles)
        try data.write(to: profilesFileURL, options: .atomic)
    }

    // MARK: - History & Reports

    public func loadHistory() throws -> [SyncReport] {
        guard fileManager.fileExists(atPath: historyFileURL.path) else {
            return []
        }
        let data = try Data(contentsOf: historyFileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([SyncReport].self, from: data)
    }

    public func appendReport(_ report: SyncReport, maxEntries: Int = 100) throws {
        try ensureDirectoryExists()
        var current = (try? loadHistory()) ?? []
        current.insert(report, at: 0)
        if current.count > maxEntries {
            current = Array(current.prefix(maxEntries))
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(current)
        try data.write(to: historyFileURL, options: .atomic)
    }
}
