import Foundation
import ServiceManagement

/// Manages the automatic launch of SyncTop at macOS login using the modern SMAppService API.
public final class LaunchAtLoginManager: Sendable {
    public static let shared = LaunchAtLoginManager()

    public var isEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    public func setEnabled(_ enable: Bool) throws {
        if #available(macOS 13.0, *) {
            if enable {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        }
    }
}

