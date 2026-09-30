// Purpose: Navigable source card for local retrieval, semantic search, and OCR hits.

#if canImport(UIKit)
import SwiftUI

struct ChatSourceResultCard: View {
    let provenance: AISourceProvenance
    let theme: ReaderThemeV2
    let onNavigate: (Locator) -> Void

    var body: some View {
        Button {
            onNavigate(provenance.locator)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(headerTitle)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(theme.inkColor))

                    Spacer()

                    badgeView
                }

                if !provenance.snippet.isEmpty {
                    Text(provenance.snippet)
                        .font(.system(size: 12))
                        .foregroundStyle(Color(theme.inkColor).opacity(0.8))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(10)
            .background(Color(theme.sheetCardSurfaceColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(theme.inkColor).opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("chatSourceResultCard")
    }

    private var headerTitle: String {
        if let explicit = provenance.sourceLabel, !explicit.isEmpty { return explicit }
        if let chapter = provenance.chapterTitle, !chapter.isEmpty { return chapter }
        if let page = provenance.pageIndex { return "Page \(page + 1)" }
        return provenance.bookTitle.isEmpty ? "Source" : provenance.bookTitle
    }

    @ViewBuilder
    private var badgeView: some View {
        if provenance.isOCRDerived {
            ChatOCRSourceBadge()
        } else if let server = provenance.mcpServerName {
            ChatMCPServerBadge(serverName: server)
        } else {
            Text(provenance.retrievalMethod.defaultBadgeLabel)
                .font(.system(size: 9.5, weight: .medium))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.12))
                .foregroundStyle(Color.secondary)
                .clipShape(Capsule())
        }
    }
}

struct ChatToolResultCard: View {
    let title: String
    let detail: String?
    let iconName: String
    let theme: ReaderThemeV2

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color(theme.accentColor))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(theme.inkColor))
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(Color(theme.inkColor).opacity(0.75))
                }
            }
            Spacer()
        }
        .padding(10)
        .background(Color(theme.sheetCardSurfaceColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct ChatSemanticSearchStatus: View {
    let state: SemanticIndexingState
    let theme: ReaderThemeV2

    var body: some View {
        switch state {
        case .indexing(_, let progress):
            HStack(spacing: 6) {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .frame(width: 80)
                Text("Indexing: \(Int(progress * 100))%")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        case .failed(_, let err):
            Text("Indexing error: \(err)")
                .font(.caption2)
                .foregroundStyle(.red)
        default:
            EmptyView()
        }
    }
}
#endif
