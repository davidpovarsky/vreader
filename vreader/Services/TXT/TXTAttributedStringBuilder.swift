// Purpose: Builds NSAttributedString from plain text + TXTViewConfig.
// Extracted from TXTTextViewBridge.applyText so it can run off the main thread.
//
// Key decisions:
// - Static, pure function with no UIKit view dependencies.
// - @Sendable safe — can be called from Task.detached for background construction.
// - UIFontMetrics scaling applied for Dynamic Type support.
//
// @coordinates-with: TXTTextViewBridge.swift, TXTReaderContainerView.swift

#if canImport(UIKit)
import UIKit

/// Sendable wrapper for NSAttributedString, safe because the wrapped value
/// is immutable and never mutated after construction.
struct SendableAttributedString: @unchecked Sendable {
    let value: NSAttributedString
}

enum TXTAttributedStringBuilder {

    /// Builds a Sendable-wrapped NSAttributedString for cross-isolation transfer.
    static func buildSendable(text: String, config: TXTViewConfig) -> SendableAttributedString {
        SendableAttributedString(value: build(text: text, config: config))
    }

    /// Builds an NSAttributedString from plain text and the given config.
    /// Safe to call from any thread.
    static func build(text: String, config: TXTViewConfig) -> NSAttributedString {
        let baseFont: UIFont
        if let name = config.fontName {
            baseFont = UIFont(name: name, size: config.fontSize)
                ?? .systemFont(ofSize: config.fontSize)
        } else {
            baseFont = .systemFont(ofSize: config.fontSize)
        }
        let font = UIFontMetrics.default.scaledFont(for: baseFont)

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = config.lineSpacing

        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraphStyle,
            .foregroundColor: config.textColor,
        ]
        if config.letterSpacing != 0 {
            attributes[.kern] = config.letterSpacing
        }

        return NSAttributedString(string: text, attributes: attributes)
    }
}
#endif
