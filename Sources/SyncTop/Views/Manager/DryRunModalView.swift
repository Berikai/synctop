import SwiftUI
import SyncTopCore

public struct DryRunModalView: View {
    @ObservedObject var state: AppState
    let onConfirmSync: () -> Void
    @Environment(\.dismiss) private var dismiss

    public init(state: AppState, onConfirmSync: @escaping () -> Void) {
        self.state = state
        self.onConfirmSync = onConfirmSync
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "magnifyingglass.circle.fill")
                    .foregroundColor(.accentColor)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Dry-Run Simulation Preview")
                        .font(.headline)
                    if let profile = state.dryRunProfile {
                        Text("\(profile.name) (\(profile.direction.displayName))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                if state.isDryRunExecuting {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Console output
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        if state.dryRunLogs.isEmpty && state.isDryRunExecuting {
                            Text("Simulating sync... querying Google Drive API...")
                                .foregroundColor(.secondary)
                                .font(.system(.body, design: .monospaced))
                                .padding()
                        } else if state.dryRunLogs.isEmpty && !state.isDryRunExecuting {
                            Text("No changes detected between local folder and Google Drive.")
                                .foregroundColor(.secondary)
                                .font(.system(.body, design: .monospaced))
                                .padding()
                        } else {
                            ForEach(Array(state.dryRunLogs.enumerated()), id: \.offset) { index, log in
                                logRow(log)
                                    .id(index)
                            }
                        }
                    }
                    .padding(12)
                }
                .background(Color(NSColor.textBackgroundColor))
                .onChange(of: state.dryRunLogs.count) { _, newCount in
                    if newCount > 0 {
                        proxy.scrollTo(newCount - 1, anchor: .bottom)
                    }
                }
            }

            Divider()

            // Footer
            HStack {
                Button("Close") {
                    dismiss()
                }
                Spacer()
                Button {
                    dismiss()
                    onConfirmSync()
                } label: {
                    Label("Run Real Sync Now", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(state.isDryRunExecuting)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 600, height: 440)
    }

    private func logRow(_ log: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            if log.contains("NOTICE:") || log.contains("Copied") || log.contains("Would copy") {
                Image(systemName: "arrow.up.circle.fill")
                    .foregroundColor(.green)
                    .font(.caption)
            } else if log.contains("Deleted") || log.contains("Would delete") {
                Image(systemName: "trash.fill")
                    .foregroundColor(.red)
                    .font(.caption)
            } else if log.contains("CONFLICT") {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.caption)
            } else {
                Image(systemName: "circle.fill")
                    .foregroundColor(.secondary.opacity(0.3))
                    .font(.system(size: 6))
                    .padding(.top, 5)
            }

            Text(log)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
        }
    }
}
