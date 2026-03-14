// Purpose: Side-by-side or stacked bilingual display for AI translation.
// Shows original text on left/top and translation on right/bottom.
//
// Key decisions:
// - Adapts layout based on horizontal size class: side-by-side in regular,
//   stacked in compact.
// - Both panels are independently scrollable.
// - Language label headers distinguish original from translation.
// - Minimal styling; follows system fonts and design tokens.
//
// @coordinates-with: AITranslationViewModel.swift, TranslationPanel.swift

#if canImport(UIKit)
import SwiftUI

/// Displays original and translated text in a bilingual layout.
struct BilingualView: View {

    /// The original source text.
    let originalText: String

    /// The translated text.
    let translatedText: String

    /// The target language label (e.g., "Chinese").
    let targetLanguage: String

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        if horizontalSizeClass == .regular {
            sideBySideLayout
        } else {
            stackedLayout
        }
    }

    // MARK: - Layouts

    @ViewBuilder
    private var sideBySideLayout: some View {
        HStack(spacing: 0) {
            textPanel(
                label: "Original",
                text: originalText,
                accessibilityId: "bilingualOriginal"
            )

            Divider()

            textPanel(
                label: targetLanguage,
                text: translatedText,
                accessibilityId: "bilingualTranslation"
            )
        }
    }

    @ViewBuilder
    private var stackedLayout: some View {
        VStack(spacing: 0) {
            textPanel(
                label: "Original",
                text: originalText,
                accessibilityId: "bilingualOriginal"
            )

            Divider()

            textPanel(
                label: targetLanguage,
                text: translatedText,
                accessibilityId: "bilingualTranslation"
            )
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private func textPanel(
        label: String,
        text: String,
        accessibilityId: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemGroupedBackground))
                .accessibilityAddTraits(.isHeader)
                .accessibilityLabel("\(label) section")

            ScrollView {
                Text(text)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
        }
        .accessibilityIdentifier(accessibilityId)
    }
}
#endif
