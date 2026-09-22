import SwiftUI

/// Native iOS/iPadOS reader toolbar. It deliberately contains no custom
/// chrome, sizing, background or popover implementation: SwiftUI owns the
/// navigation bar, material, menu presentation, hover states and accessibility.
struct NativeReaderToolbar: ToolbarContent {
    let bookTitle: String
    let bilingualActive: Bool
    let bilingualLanguage: String?
    let moreRows: [ReaderMoreMenuRow]
    let autoTurnOn: Bool
    let ttsPlaying: Bool

    let onSearch: () -> Void
    let onBookmark: () -> Void
    let onBilingualSettings: () -> Void
    let onMoreAction: (ReaderMoreMenuRow) -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            HStack(spacing: 6) {
                Text(bookTitle)
                    .font(.headline)
                    .lineLimit(1)

                if bilingualActive, let bilingualLanguage {
                    Button {
                        onBilingualSettings()
                    } label: {
                        Text(bilingualLanguage)
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .accessibilityLabel("Translation settings")
                }
            }
        }

        ToolbarItemGroup(placement: .topBarTrailing) {
            Button(action: onSearch) {
                Image(systemName: "magnifyingglass")
            }
            .accessibilityLabel("Search in book")

            Button(action: onBookmark) {
                Image(systemName: "bookmark")
            }
            .accessibilityLabel("Add bookmark")

            Menu {
                ForEach(moreRows, id: \.self) { row in
                    Button {
                        onMoreAction(row)
                    } label: {
                        Label {
                            Text(row.label)
                        } icon: {
                            Image(systemName: statefulSymbol(for: row))
                        }
                    }
                    .accessibilityIdentifier(row.accessibilityIdentifier)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("More")
        }
    }

    private func statefulSymbol(for row: ReaderMoreMenuRow) -> String {
        switch row {
        case .readAloud where ttsPlaying:
            return "speaker.wave.2.fill"
        case .autoTurnPages where autoTurnOn:
            return "timer.circle.fill"
        case .bilingual where bilingualActive:
            return "character.book.closed.fill"
        default:
            return row.systemImage
        }
    }
}
