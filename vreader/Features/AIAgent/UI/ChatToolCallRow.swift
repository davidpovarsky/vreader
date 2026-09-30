// Purpose: Single row rendering a tool call's icon, title, argument summary, and status badge.

#if canImport(UIKit)
import SwiftUI

struct ChatToolCallRow: View {
    let trace: AIToolTrace
    let theme: ReaderThemeV2

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: trace.iconName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color(theme.accentColor))
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(trace.displayName)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Color(theme.inkColor))
                    if let server = trace.mcpServerName {
                        ChatMCPServerBadge(serverName: server)
                    }
                }
                if !trace.argumentSummary.isEmpty {
                    Text(trace.argumentSummary)
                        .font(.caption2)
                        .foregroundStyle(Color(theme.inkColor).opacity(0.65))
                        .lineLimit(1)
                }
            }

            Spacer()

            statusIndicator
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(Color(theme.sheetCardSurfaceColor).opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch trace.state {
        case .queued:
            Image(systemName: "clock")
                .font(.caption2)
                .foregroundStyle(.secondary)
        case .running:
            ProgressView()
                .controlSize(.mini)
        case .awaitingConfirmation:
            Text("Pending")
                .font(.caption2.bold())
                .foregroundStyle(.orange)
        case .succeeded:
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.red)
        case .cancelled:
            Image(systemName: "slash.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
#endif
