import Foundation

/// Exclude preset rules to filter out build artifacts and system cache files from synchronization.
public struct ExcludePreset: Sendable {
    /// Developer build artifacts, virtual environments, and caches.
    public static let developerRules: [String] = [
        "node_modules/**",
        ".git/**",
        ".venv/**",
        "venv/**",
        "__pycache__/**",
        "*.pyc",
        ".pytest_cache/**",
        "target/**",
        "build/**",
        ".build/**",
        ".gradle/**",
        "DerivedData/**",
        "Pods/**",
        ".terraform/**",
        ".next/**",
        ".nuxt/**",
        "dist/**",
        "*.o",
        "*.a",
        "*.dylib"
    ]

    /// macOS operating system temporary and index files.
    public static let systemRules: [String] = [
        ".DS_Store",
        ".DS_Store/**",
        ".AppleDouble/**",
        ".LSOverride",
        ".Trash/**",
        ".Trash-*/**",
        ".Spotlight-V100/**",
        ".Trashes",
        "Thumbs.db",
        "ehthumbs.db",
        "$RECYCLE.BIN/**"
    ]

    /// Combines active presets and custom globs into a list of rclone filter arguments.
    public static func resolveExcludePatterns(
        includeDeveloper: Bool,
        includeSystem: Bool,
        customRules: [String]
    ) -> [String] {
        var rules: [String] = []
        if includeDeveloper {
            rules.append(contentsOf: developerRules)
        }
        if includeSystem {
            rules.append(contentsOf: systemRules)
        }
        for custom in customRules {
            let trimmed = custom.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty && !rules.contains(trimmed) {
                rules.append(trimmed)
            }
        }
        return rules
    }
}
