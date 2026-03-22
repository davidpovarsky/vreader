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

        // Simulate text already loaded (e.g., loadTextContent completed)
        coordinator.textContent = "hello foo world"

        // Now transforms arrive (e.g., loadReplacementRules completed after text load)
        coordinator.activeTransforms = [FooBarTransform()]

        // BUG: textContent is still "hello foo world" because setting activeTransforms
        // does NOT trigger re-application. The coordinator has no didSet observer or
        // onChange handler for activeTransforms.
        //
        // Correct behavior: textContent should reflect the new transforms.
        #expect(coordinator.textContent == "hello bar world",
                "textContent should be re-transformed when activeTransforms changes after load")
    }

    // -----------------------------------------------------------------------
    // ROOT CAUSE TEST 2: Chinese conversion toggle doesn't update displayed text
    // -----------------------------------------------------------------------

    @Test("changing Chinese conversion after load should update textContent")
    func chineseConversionToggle_shouldUpdateContent() {
        let coordinator = ReaderUnifiedCoordinator()

        // Load text without transforms
        coordinator.activeTransforms = []
        coordinator.textContent = "国家"  // Simplified Chinese

        // User toggles simp→trad conversion
        coordinator.activeTransforms = [SimpTradTransform(direction: .simpToTrad)]

        // BUG: textContent still shows "国家" (simplified) because the coordinator
        // doesn't re-apply transforms when activeTransforms changes.
        //
        // Correct behavior: textContent should show "國家" (traditional).
        #expect(coordinator.textContent != "国家",
                "textContent should change when Chinese conversion transform is added")
    }

    // -----------------------------------------------------------------------
    // ROOT CAUSE TEST 3: Removing transforms doesn't revert text
    // -----------------------------------------------------------------------

    @Test("removing all transforms should revert to original text")
    func removeTransforms_shouldRevert() {
        let coordinator = ReaderUnifiedCoordinator()

        // Set transforms first, then load text
        coordinator.activeTransforms = [UppercaseTransform()]
        // Simulate the load path calling applyTransforms internally
        // Since applyTransforms is private, we set textContent directly
        // to what applyTransforms would produce:
        coordinator.textContent = "HELLO WORLD"

        // User disables all transforms
        coordinator.activeTransforms = []

        // BUG: textContent is still "HELLO WORLD" — original text is lost.
        // The coordinator doesn't store the original source text, so it can't revert.
        //
        // Correct behavior: coordinator should store source text separately and
        // revert to it when transforms are removed.
        #expect(coordinator.textContent != "HELLO WORLD",
                "textContent should revert to original when transforms are removed")
    }

    // -----------------------------------------------------------------------
    // RACE CONDITION: transforms not ready at load time
    // -----------------------------------------------------------------------

    @Test("applyTransforms with empty activeTransforms returns source text unchanged")
    func applyTransforms_empty_returnsIdentity() {
        let coordinator = ReaderUnifiedCoordinator()
        coordinator.activeTransforms = []

        // This verifies the base case: when no transforms are set (race condition:
        // loadReplacementRules hasn't completed), the text passes through unchanged.
        // The text is loaded without transforms — this is the bug scenario.
        coordinator.textContent = "original text foo"

        // The text is unchanged because transforms were empty.
        // This isn't a failure — it's the setup for the race.
        #expect(coordinator.textContent == "original text foo")

        // Now transforms arrive late...
        coordinator.activeTransforms = [FooBarTransform()]

        // BUG: textContent still shows "original text foo"
        #expect(coordinator.textContent == "original text bar",
                "Late-arriving transforms should be applied to already-loaded text")
    }

    // -----------------------------------------------------------------------
    // SOURCE TEXT PRESERVATION
    // -----------------------------------------------------------------------

    @Test("coordinator should preserve source text for re-transformation")
    func sourceTextPreserved_forRetransformation() {
        let coordinator = ReaderUnifiedCoordinator()

        // Load with transform
        coordinator.activeTransforms = [FooBarTransform()]
        coordinator.textContent = "foo baz foo"
        // In current code, textContent is the raw value set externally.
        // If loadTextContent was used, it would call applyTransforms internally.
        // We simulate that result:
        // coordinator.textContent would be "bar baz bar" after applyTransforms

        // The coordinator should expose the source text for re-transformation.
        // BUG: No source text storage exists. The coordinator only has textContent
        // which is the display text. Once set, the original is lost.
        //
        // We can't test a property that doesn't exist, so we test the behavioral
        // consequence: changing transforms should produce correct output.
        coordinator.activeTransforms = [UppercaseTransform()]

        // If source text was "foo baz foo", applying UppercaseTransform should give
        // "FOO BAZ FOO". But since source is lost, textContent is still whatever
        // was previously set.
        //
        // This test documents the design gap. A fix would add a sourceText property.
        #expect(coordinator.textContent != "foo baz foo",
                "After changing transforms, text should reflect the new transform")
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
