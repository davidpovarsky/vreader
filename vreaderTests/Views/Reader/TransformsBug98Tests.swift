// Purpose: RED tests for Bug #98 — Text Transforms fail (replacement rules + simp/trad).
// Proves the root cause: ReaderUnifiedCoordinator does not re-apply transforms when
// activeTransforms changes after text is already loaded. Also: race condition between
// loadReplacementRules() and text loading — transforms may not be set when text loads.
//
// These tests assert CORRECT behavior that the current code does NOT implement.
// They should FAIL until the bug is fixed.
//
// @coordinates-with: ReaderUnifiedCoordinator.swift, TextMapper.swift,
//   ReplacementTransform.swift, SimpTradTransform.swift,
//   ReaderContainerView.swift, ReaderContainerView+Sheets.swift

#if canImport(UIKit)
import Testing
import Foundation
@testable import vreader

// MARK: - Test Helpers

/// A simple test transform that uppercases text.
private struct UppercaseTransform: TextTransform {
    func transform(input: String) -> TransformResult {
        let output = input.uppercased()
        return TransformResult(
            text: output,
            offsetMap: .identity(lengthUTF16: output.utf16.count)
        )
    }
}

/// A transform that replaces "foo" with "bar".
private struct FooBarTransform: TextTransform {
    func transform(input: String) -> TransformResult {
        let output = input.replacingOccurrences(of: "foo", with: "bar")
        return TransformResult(
            text: output,
            offsetMap: .identity(lengthUTF16: output.utf16.count)
        )
    }
}

@Suite("Bug #98 — Text Transforms")
@MainActor
struct TransformsBug98Tests {

    // -----------------------------------------------------------------------
    // ROOT CAUSE TEST 1: Transforms set AFTER text load → text not transformed
    // -----------------------------------------------------------------------

    @Test("setting activeTransforms after text is loaded should re-apply transforms")
    func transformsAfterLoad_shouldReapply() {
        let coordinator = ReaderUnifiedCoordinator()

        // Simulate text loaded via loadTextContent (sets both sourceText and textContent)
        coordinator.sourceText = "hello foo world"
        coordinator.textContent = "hello foo world"

        // Now transforms arrive (e.g., loadReplacementRules completed after text load)
        coordinator.activeTransforms = [FooBarTransform()]

        // Fix: didSet on activeTransforms re-applies transforms from sourceText
        #expect(coordinator.textContent == "hello bar world",
                "textContent should be re-transformed when activeTransforms changes after load")
    }

    // -----------------------------------------------------------------------
    // ROOT CAUSE TEST 2: Chinese conversion toggle doesn't update displayed text
    // -----------------------------------------------------------------------

    @Test("changing Chinese conversion after load should update textContent")
    func chineseConversionToggle_shouldUpdateContent() {
        let coordinator = ReaderUnifiedCoordinator()

        // Simulate text loaded (sourceText stored by load method)
        coordinator.sourceText = "国家"
        coordinator.textContent = "国家"

        // User toggles simp→trad conversion
        coordinator.activeTransforms = [SimpTradTransform(direction: .simpToTrad)]

        // Fix: didSet re-applies transform from sourceText → "國家"
        #expect(coordinator.textContent != "国家",
                "textContent should change when Chinese conversion transform is added")
    }

    // -----------------------------------------------------------------------
    // ROOT CAUSE TEST 3: Removing transforms doesn't revert text
    // -----------------------------------------------------------------------

    @Test("removing all transforms should revert to original text")
    func removeTransforms_shouldRevert() {
        let coordinator = ReaderUnifiedCoordinator()

        // Simulate: source text loaded, then transformed
        coordinator.sourceText = "hello world"
        coordinator.activeTransforms = [UppercaseTransform()]
        // didSet fires → textContent becomes "HELLO WORLD"
        #expect(coordinator.textContent == "HELLO WORLD")

        // User disables all transforms
        coordinator.activeTransforms = []

        // Fix: didSet re-applies (empty transforms → identity → sourceText)
        #expect(coordinator.textContent == "hello world",
                "textContent should revert to original when transforms are removed")
    }

    // -----------------------------------------------------------------------
    // RACE CONDITION: transforms not ready at load time
    // -----------------------------------------------------------------------

    @Test("late-arriving transforms should be applied to already-loaded text")
    func applyTransforms_empty_returnsIdentity() {
        let coordinator = ReaderUnifiedCoordinator()
        coordinator.activeTransforms = []

        // Simulate text loaded while transforms are empty (race)
        coordinator.sourceText = "original text foo"
        coordinator.textContent = "original text foo"

        #expect(coordinator.textContent == "original text foo")

        // Now transforms arrive late...
        coordinator.activeTransforms = [FooBarTransform()]

        // Fix: didSet re-applies from sourceText
        #expect(coordinator.textContent == "original text bar",
                "Late-arriving transforms should be applied to already-loaded text")
    }

    // -----------------------------------------------------------------------
    // SOURCE TEXT PRESERVATION
    // -----------------------------------------------------------------------

    @Test("coordinator should preserve source text for re-transformation")
    func sourceTextPreserved_forRetransformation() {
        let coordinator = ReaderUnifiedCoordinator()

        // Set source text and apply initial transform
        coordinator.sourceText = "foo baz foo"
        coordinator.activeTransforms = [FooBarTransform()]
        // didSet fires → textContent = "bar baz bar"
        #expect(coordinator.textContent == "bar baz bar")

        // Switch to a different transform
        coordinator.activeTransforms = [UppercaseTransform()]

        // Fix: re-applies UppercaseTransform to sourceText ("foo baz foo") → "FOO BAZ FOO"
        #expect(coordinator.textContent == "FOO BAZ FOO",
                "After changing transforms, text should reflect the new transform on source text")
    }

    // -----------------------------------------------------------------------
    // TRANSFORM ORDERING
    // -----------------------------------------------------------------------

    @Test("replacement rules should apply before Chinese conversion")
    func transformOrdering_replacementBeforeConversion() {
        // This tests the correct ordering as documented in loadReplacementRules:
        // 1. ReplacementTransform (string/regex rules)
        // 2. SimpTradTransform (simp↔trad)
        //
        // If replacement rules contain simplified chars, they should be replaced
        // BEFORE the simp→trad conversion runs.
        let rules = [
            ReplacementRuleDescriptor(
                pattern: "测试",
                replacement: "检测",
                isRegex: false,
                enabled: true,
                order: 0
            )
        ]
        let replacement = ReplacementTransform(rules: rules)
        let conversion = SimpTradTransform(direction: .simpToTrad)

        let result = TextMapper.apply(
            transforms: [replacement, conversion],
            to: "这是测试文本"
        )

        // "测试" → "检测" (replacement), then "检测" → "檢測" (trad conversion)
        // Full chain: "这是测试文本" → "这是检测文本" → "這是檢測文本"
        #expect(result.text.contains("檢測"),
                "Replacement should happen before conversion: 测试→检测→檢測")
    }

    // -----------------------------------------------------------------------
    // REGEX REPLACEMENT: invalid pattern should not crash
    // -----------------------------------------------------------------------

    @Test("invalid regex rule should not crash and should skip gracefully")
    func invalidRegex_shouldNotCrash() {
        let rules = [
            ReplacementRuleDescriptor(
                pattern: "[invalid(regex",
                replacement: "fixed",
                isRegex: true,
                enabled: true,
                order: 0
            )
        ]
        let transform = ReplacementTransform(rules: rules)
        let result = transform.transform(input: "hello world")

        // Should not crash, and text should pass through unchanged
        #expect(result.text == "hello world",
                "Invalid regex should skip gracefully without crashing")
    }
}
#endif
