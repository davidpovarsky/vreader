// Purpose: Compact badge visually distinguishing remote external MCP server sources.

#if canImport(UIKit)
import SwiftUI

struct ChatMCPServerBadge: View {
    let serverName: String

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "network")
                .font(.system(size: 9))
            Text(serverName)
                .font(.system(size: 10, weight: .medium))
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(Color.blue.opacity(0.12))
        .foregroundStyle(.blue)
        .clipShape(Capsule())
    }
}

struct ChatOCRSourceBadge: View {
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "doc.viewfinder")
                .font(.system(size: 9))
            Text("OCR")
                .font(.system(size: 10, weight: .semibold))
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(Color.purple.opacity(0.12))
        .foregroundStyle(.purple)
        .clipShape(Capsule())
    }
}

struct ChatToolErrorRow: View {
    let errorMessage: String
    let theme: ReaderThemeV2

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
            Text(errorMessage)
                .font(.caption2)
                .foregroundStyle(Color(theme.inkColor).opacity(0.8))
            Spacer()
        }
        .padding(8)
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
#endif
