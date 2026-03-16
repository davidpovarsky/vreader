// Purpose: SwiftUI sheet wrapping UIReferenceLibraryViewController for system dictionary.
// Presents the built-in iOS dictionary definition for a given word.
//
// Key decisions:
// - Uses UIViewControllerRepresentable to wrap UIReferenceLibraryViewController.
// - Self-contained — no external state besides the word to define.
// - Presented as a sheet from ReaderContainerView.
//
// @coordinates-with DictionaryLookup.swift, ReaderContainerView.swift

#if canImport(UIKit)
import SwiftUI
import UIKit

/// Sheet that displays the system dictionary definition for a word.
struct DictionarySheet: UIViewControllerRepresentable {
    let word: String

    func makeUIViewController(context: Context) -> UIReferenceLibraryViewController {
        DictionaryLookup.viewController(for: word)
    }

    func updateUIViewController(
        _ uiViewController: UIReferenceLibraryViewController,
        context: Context
    ) {
        // No updates needed — word is immutable for the sheet's lifetime.
    }
}
#endif
