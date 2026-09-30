// Purpose: Collapsible cluster showing tool activity for an assistant turn ("Used N tools").

#if canImport(UIKit)
import SwiftUI

struct ChatToolActivityCluster: View {
    let traces: [AIToolTrace]
    let theme: ReaderThemeV2
    @State private var isExpanded: Bool = false

    var body: some View {
        guard !traces.isEmpty else { return AnyView(EmptyView()) }

        return AnyView(
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "wrench.and.screwdriver")
                            .font(.system(size: 11))
                            .foregroundStyle(Color(theme.accentColor))

                        Text("Used \(traces.count) tool\(traces.count == 1 ? "" : "s")")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color(theme.inkColor).opacity(0.8))

                        if traces.contains(where: { $0.state == .running || $0.state == .awaitingConfirmation }) {
                            ProgressView()
                                .controlSize(.mini)
                                .padding(.leading, 2)
                        }

                        Spacer()

                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(theme.sheetCardSurfaceColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("toolActivityHeader")

                if isExpanded {
                    VStack(spacing: 4) {
                        ForEach(traces) { trace in
                            ChatToolCallRow(trace: trace, theme: theme)
                        }
                    }
                    .padding(.leading, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(.vertical, 2)
        )
    }
}
#endif
