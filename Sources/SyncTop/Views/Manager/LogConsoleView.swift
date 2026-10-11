import SwiftUI
import SyncTopCore

public struct LogConsoleView: View {
    @ObservedObject var state: AppState
    let profileId: UUID?
    @Environment(\.dismiss) private var dismiss

    public init(state: AppState, profileId: UUID?) {
        self.state = state
        self.profileId = profileId
    }

    private var logs: [String] {
        if let id = profileId {
            return state.activeLogs[id] ?? ["No active log output for this profile yet."]
        }
        return state.activeLogs.values.flatMap { $0 }
    }

    private var profileName: String {
        guard let id = profileId, let profile = state.profiles.first(where: { $0.id == id }) else {
            return "All Logs"
        }
        return profile.name
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "terminal.fill")
                    .foregroundColor(.accentColor)
                Text("Logs: \(profileName)")
                    .font(.headline)
                Spacer()
                Button("Close") {
                    dismiss()
                }
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Console output
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(logs.enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .id(index)
                        }
                    }
                    .padding(10)
                }
                .background(Color(NSColor.textBackgroundColor))
                .onChange(of: logs.count) { _, newCount in
                    if newCount > 0 {
                        proxy.scrollTo(newCount - 1, anchor: .bottom)
                    }
                }
            }

            Divider()

            // Footer
            HStack {
                Text("\(logs.count) lines")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Copy All") {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(logs.joined(separator: "\n"), forType: .string)
                }
                .controlSize(.small)
            }
            .padding(10)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 580, height: 400)
    }
}
