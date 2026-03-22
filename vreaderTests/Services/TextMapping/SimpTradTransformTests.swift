// Purpose: Tests for SimpTradTransform — Simplified/Traditional Chinese conversion.
// Validates character conversion, offset mapping, edge cases, and performance.

import Testing
import Foundation
@testable import vreader

@Suite("SimpTradTransform")
struct SimpTradTransformTests {

    @Test func simpToTrad_basicCharacters() {
        let transform = SimpTradTransform(direction: .simpToTrad)
        let result = transform.transform(input: "国学书")
        // Expect traditional: 國學書
        #expect(result.text.contains("國"))
        #expect(result.text.contains("學"))
        #expect(result.text.contains("書"))
    }

    @Test func tradToSimp_basicCharacters() {
        let transform = SimpTradTransform(direction: .tradToSimp)
        let result = transform.transform(input: "國學書")
        #expect(result.text.contains("国"))
        #expect(result.text.contains("学"))
        #expect(result.text.contains("书"))
    }

    @Test func mixedScript_onlyCJKConverted() {
        let transform = SimpTradTransform(direction: .simpToTrad)
        let input = "Hello 国 World 学 Test"
        let result = transform.transform(input: input)
        // English parts should be unchanged
        #expect(result.text.contains("Hello"))
        #expect(result.text.contains("World"))
        #expect(result.text.contains("Test"))
        // CJK parts should be converted
        #expect(result.text.contains("國"))
        #expect(result.text.contains("學"))
        // Original simplified should be gone
        #expect(!result.text.contains("国"))
        #expect(!result.text.contains("学"))
    }

    @Test func emptyText_noOp() {
        let transform = SimpTradTransform(direction: .simpToTrad)
        let result = transform.transform(input: "")
        #expect(result.text == "")
        #expect(result.offsetMap.sourceLengthUTF16 == 0)
        #expect(result.offsetMap.displayLengthUTF16 == 0)
    }

    @Test func noneDirection_noOp() {
        let transform = SimpTradTransform(direction: .none)
        let input = "国学书"
        let result = transform.transform(input: input)
        #expect(result.text == input)
    }

    @Test func offsetMap_afterConversion_correct() {
        let transform = SimpTradTransform(direction: .simpToTrad)
        let input = "学生" // 2 chars
        let result = transform.transform(input: input)
        // Both chars are 1 UTF-16 code unit in both simplified and traditional
        #expect(result.offsetMap.sourceLengthUTF16 == input.utf16.count)
        #expect(result.offsetMap.displayLengthUTF16 == result.text.utf16.count)
        // Offset 0 should map to 0
        #expect(result.offsetMap.sourceToDisplay(0) == 0)
        // Display to source round-trip
        let displayOffset = result.offsetMap.sourceToDisplay(1)
        let backToSource = result.offsetMap.displayToSource(displayOffset)
        #expect(backToSource == 1)
    }

    @Test func punctuation_preserved() {
        let transform = SimpTradTransform(direction: .simpToTrad)
        let input = "你好，世界！"
        let result = transform.transform(input: input)
        // Punctuation should remain
        #expect(result.text.contains("，"))
        #expect(result.text.contains("！"))
    }

    @Test func alreadyInTargetScript_noChange() {
        // Traditional text with simpToTrad should not change
        let transform = SimpTradTransform(direction: .simpToTrad)
        let input = "國學書" // already traditional
        let result = transform.transform(input: input)
        #expect(result.text == input)
    }

    @Test func performance_1MBText_under500ms() {
        // Generate ~1MB of CJK text
        let chunk = "这是一段用于性能测试的中文文本内容"
        let repeatCount = 1_000_000 / (chunk.utf8.count)
        let largeText = String(repeating: chunk, count: max(1, repeatCount))

        let transform = SimpTradTransform(direction: .simpToTrad)
        let start = CFAbsoluteTimeGetCurrent()
        let result = transform.transform(input: largeText)
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        #expect(!result.text.isEmpty)
        #expect(elapsed < 0.5, "1MB CJK text conversion should complete in <500ms, took \(elapsed)s")
    }
}
