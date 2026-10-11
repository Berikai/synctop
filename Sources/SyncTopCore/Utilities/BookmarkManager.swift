import Foundation

/// Manages macOS security-scoped bookmarks to maintain file access permissions across application launches.
public final class BookmarkManager: Sendable {
    public init() {}

    /// Creates bookmark data for a directory URL.
    public func createBookmark(for url: URL) -> Data? {
        do {
            return try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            return nil
        }
    }

    /// Resolves bookmark data back to an active URL.
    public func resolveBookmark(data: Data) -> (url: URL?, isStale: Bool) {
        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            return (url, isStale)
        } catch {
            return (nil, false)
        }
    }

    /// Accesses a security-scoped URL safely within a block.
    public func accessResource<T>(at url: URL, block: () throws -> T) rethrows -> T {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return try block()
    }
}
