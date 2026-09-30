// Purpose: Row displaying MCP server connection status and tool count.

#if canImport(UIKit)
import SwiftUI

struct MCPServerConnectionStatusRow: View {
    let status: MCPCompatibilityStatus

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(status.displayLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var statusColor: Color {
        switch status {
        case .connected: return .green
        case .connecting: return .orange
        case .disconnected: return .secondary
        case .authRequired: return .blue
        case .error, .incompatible: return .red
        }
    }
}
#endif
