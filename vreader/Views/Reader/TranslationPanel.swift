// Purpose: Panel for AI translation with language picker and bilingual display.
// Contains the language selector, translate button, and BilingualView.
//
// Key decisions:
// - Uses AITranslationViewModel for state management.
// - Language picker uses a Picker with menu style (compact dropdown).
// - Shows loading state (ProgressView) while translating.
// - Shows error with retry button on failure.
// - When translation completes, shows BilingualView.
//
// @coordinates-with: AITranslationViewModel.swift, BilingualView.swift, AIReaderPanel.swift

#if canImport(UIKit)
import SwiftUI

/// Translation panel with language picker and bilingual result display.
struct TranslationPanel: View {

    /// The translation view model.
    @Bindable var viewModel: AITranslationViewModel

    /// The current locator for context extraction.
    let locator: Locator

    /// The text content to translate.
    let textContent: String

    /// The book format.
    let format: BookFormat

    var body: some View {
        VStack(spacing: 0) {
            languageBar

            Divider()

            if viewModel.isLoading {
                loadingView
            } else if let error = viewModel.errorMessage {
                errorView(message: error)
            } else if let translated = viewModel.translatedText {
                BilingualView(
                    originalText: viewModel.originalText,
                    translatedText: translated,
                    targetLanguage: viewModel.targetLanguage
                )
            } else {
                idleView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("translationPanel")
    }

    // MARK: - Subviews

    @ViewBuilder
    private var languageBar: some View {
        HStack {
            Text("Translate to:")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Picker("Language", selection: $viewModel.targetLanguage) {
                ForEach(viewModel.supportedLanguages, id: \.self) { language in
                    Text(language).tag(language)
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("languagePicker")

            Spacer()

            Button {
                Task {
                    await viewModel.translate(
                        originalText: textContent,
                        locator: locator,
                        format: format
                    )
                }
            } label: {
                Label("Translate", systemImage: "character.book.closed")
                    .font(.subheadline)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .accessibilityIdentifier("translateButton")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var idleView: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "character.book.closed")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text("Select a language and tap Translate")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()
        }
    }

    @ViewBuilder
    private var loadingView: some View {
        VStack(spacing: 16) {
            Spacer()

            ProgressView()
                .controlSize(.large)

            Text("Translating\u{2026}")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .accessibilityIdentifier("translationLoading")
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(.orange)
                .accessibilityHidden(true)

            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button("Try Again") {
                Task {
                    await viewModel.translate(
                        originalText: textContent,
                        locator: locator,
                        format: format
                    )
                }
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("translationRetryButton")

            Spacer()
        }
        .accessibilityIdentifier("translationError")
    }
}
#endif
