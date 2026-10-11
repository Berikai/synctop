import SwiftUI
import AppKit
import SyncTopCore

@main
struct SyncTopApp: App {
    @StateObject private var appState = AppState()
    @Environment(\.openWindow) private var openWindow

    init() {
        // Run as menu bar extra by default; windows activate smoothly on demand
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarPopoverView(state: appState) {
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "manager")
            }
        } label: {
            Image(systemName: menuBarIcon)
        }
        .menuBarExtraStyle(.window)

        Window("SyncTop Manager", id: "manager") {
            ManagerWindowView(state: appState)
                .task {
                    await appState.initialize()
                }
        }
        .defaultSize(width: 700, height: 520)
    }

    private var menuBarIcon: String {
        if appState.isAnySyncing {
            return "arrow.triangle.2.circlepath"
        }
        return "arrow.triangle.2.circlepath.circle"
    }
}
