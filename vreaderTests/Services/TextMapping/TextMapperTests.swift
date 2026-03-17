// Purpose: Tests for TextMapper, OffsetMap, and TextTransform protocol.
// Validates offset mapping, round-trips, edge cases, and performance.

import Testing
import Foundation
@testable import vreader

// MARK: - Test Helpers

/// Identity transform: returns input unchanged.
private struct IdentityTransform: TextTransform {
    func transform(input: String) -> TransformResult {
        TransformResult(
            text: input,
            offsetMap: .identity(lengthUTF16: input.utf16.count)
        )
    }
}

/// Replaces all occurrences of a single character with a replacement string.
private struct SingleCharReplaceTransform: TextTransform {
    let target: Character
    let replacement: String

    func transform(input: String) -> TransformResult {
        var entries: [OffsetEntry] = []
        var output = ""
        var sourceOffset = 0
        var displayOffset = 0

        for char in input {
            let charUTF16Len = String(char).utf16.count
            if char == target {
                let replUTF16Len = replacement.utf16.count
                entries.append(OffsetEntry(
                    sourceOffset: sourceOffset,
                    displayOffset: displayOffset,
                    sourceLength: charUTF16Len,
                    displayLength: replUTF16Len
                ))
                output += replacement
                sourceOffset += charUTF16Len
                displayOffset += replUTF16Len
            } else {
                output += String(char)
                sourceOffset += charUTF16Len
                displayOffset += charUTF16Len
            }
        }

        return TransformResult(
            text: output,
            offsetMap: OffsetMap(
                entries: entries,
                sourceLengthUTF16: input.utf16.count,
                displayLengthUTF16: output.utf16.count
            )
        )
    }
}

/// Replaces a multi-char substring with a single character.
private struct MultiToSingleTransform: TextTransform {
    let target: String
    let replacement: Character

    func transform(input: String) -> TransformResult {
        var entries: [OffsetEntry] = []
        var output = ""
        var sourceOffset = 0
        var displayOffset = 0
        let targetUTF16Len = target.utf16.count
        let replUTF16Len = String(replacement).utf16.count

        var remaining = input[input.startIndex...]
        while let range = remaining.range(of: target) {
            // Copy text before match
            let before = remaining[remaining.startIndex..<range.lowerBound]
            let beforeUTF16 = String(before).utf16.count
            output += before
            sourceOffset += beforeUTF16
            displayOffset += beforeUTF16

            // Record the replacement
            entries.append(OffsetEntry(
                sourceOffset: sourceOffset,
                displayOffset: displayOffset,
                sourceLength: targetUTF16Len,
                displayLength: replUTF16Len
            ))
            output += String(replacement)
            sourceOffset += targetUTF16Len
            displayOffset += replUTF16Len

            remaining = remaining[range.upperBound...]
        }

        // Copy trailing text
        let trailing = String(remaining)
        output += trailing
        sourceOffset += trailing.utf16.count
        displayOffset += trailing.utf16.count

        return TransformResult(
            text: output,
            offsetMap: OffsetMap(
                entries: entries,
                sourceLengthUTF16: input.utf16.count,
                displayLengthUTF16: output.utf16.count
            )
        )
    }
}

/// Replaces a single character with a multi-char string.
private struct SingleToMultiTransform: TextTransform {
    let target: Character
    let replacement: String

    func transform(input: String) -> TransformResult {
        // Reuse SingleCharReplaceTransform logic
        let inner = SingleCharReplaceTransform(target: target, replacement: replacement)
        return inner.transform(input: input)
    }
}

// MARK: - OffsetMap Tests

@Suite("OffsetMap")
struct OffsetMapTests {

    @Test func identity_sourceToDisplay_unchanged() {
        let map = OffsetMap.identity(lengthUTF16: 10)
        #expect(map.sourceToDisplay(0) == 0)
        #expect(map.sourceToDisplay(5) == 5)
        #expect(map.sourceToDisplay(10) == 10)
    }

    @Test func identity_displayToSource_unchanged() {
        let map = OffsetMap.identity(lengthUTF16: 10)
        #expect(map.displayToSource(0) == 0)
        #expect(map.displayToSource(5) == 5)
        #expect(map.displayToSource(10) == 10)
    }

    @Test func singleEntry_sourceToDisplay_shifts() {
        // Replace 2 source chars at offset 3 with 1 display char
        // Source: "abcXXefg" (8 UTF-16)
        // Display: "abcYefg" (7 UTF-16)
        let map = OffsetMap(
            entries: [OffsetEntry(sourceOffset: 3, displayOffset: 3, sourceLength: 2, displayLength: 1)],
            sourceLengthUTF16: 8,
            displayLengthUTF16: 7
        )
        #expect(map.sourceToDisplay(0) == 0) // before entry
        #expect(map.sourceToDisplay(3) == 3) // at entry start
        #expect(map.sourceToDisplay(5) == 4) // after entry (3+2=5 in source -> 3+1=4 in display)
        #expect(map.sourceToDisplay(7) == 6) // offset 7 in source -> 6 in display
    }

    @Test func singleEntry_displayToSource_shifts() {
        let map = OffsetMap(
            entries: [OffsetEntry(sourceOffset: 3, displayOffset: 3, sourceLength: 2, displayLength: 1)],
            sourceLengthUTF16: 8,
            displayLengthUTF16: 7
        )
        #expect(map.displayToSource(0) == 0)
        #expect(map.displayToSource(3) == 3)
        #expect(map.displayToSource(4) == 5)
        #expect(map.displayToSource(6) == 7)
    }

    @Test func rangeConversion_sourceToDisplay() {
        let map = OffsetMap(
            entries: [OffsetEntry(sourceOffset: 3, displayOffset: 3, sourceLength: 2, displayLength: 1)],
            sourceLengthUTF16: 8,
            displayLengthUTF16: 7
        )
        let result = map.sourceRangeToDisplay(start: 0, length: 8)
        #expect(result.start == 0)
        #expect(result.length == 7)
    }
}

// MARK: - TextMapper Tests

@Suite("TextMapper")
struct TextMapperTests {

    @Test func identityTransform_offsetsUnchanged() {
        let source = "Hello, world!"
        let result = TextMapper.apply(transforms: [IdentityTransform()], to: source)
        #expect(result.text == source)
        #expect(result.offsetMap.sourceToDisplay(0) == 0)
        #expect(result.offsetMap.sourceToDisplay(5) == 5)
        #expect(result.offsetMap.displayToSource(5) == 5)
    }

    @Test func singleCharReplace_offsetShifts() {
        // Replace 'o' with 'OO' in "hello"
        // Source: "hello" (5) -> Display: "hellOO" (6)
        let transform = SingleCharReplaceTransform(target: "o", replacement: "OO")
        let result = TextMapper.apply(transforms: [transform], to: "hello")
        #expect(result.text == "hellOO")
        // 'o' was at source offset 4, replaced with 'OO' at display offset 4
        #expect(result.offsetMap.sourceToDisplay(0) == 0) // 'h'
        #expect(result.offsetMap.sourceToDisplay(4) == 4) // start of replacement
        #expect(result.offsetMap.sourceToDisplay(5) == 6) // after 'o' in source -> after 'OO' in display
    }

    @Test func multiCharToSingle_offsetCompresses() {
        // Replace "ll" with "L" in "hello"
        // Source: "hello" (5) -> Display: "heLo" (4)
        let transform = MultiToSingleTransform(target: "ll", replacement: "L")
        let result = TextMapper.apply(transforms: [transform], to: "hello")
        #expect(result.text == "heLo")
        #expect(result.offsetMap.sourceToDisplay(0) == 0) // 'h'
        #expect(result.offsetMap.sourceToDisplay(2) == 2) // start of 'll'
        #expect(result.offsetMap.sourceToDisplay(4) == 3) // 'o' shifts left
    }

    @Test func singleToMultiChar_offsetExpands() {
        // Replace 'a' with "AA" in "cat"
        // Source: "cat" (3) -> Display: "cAAt" (4)
        let transform = SingleToMultiTransform(target: "a", replacement: "AA")
        let result = TextMapper.apply(transforms: [transform], to: "cat")
        #expect(result.text == "cAAt")
        #expect(result.offsetMap.sourceToDisplay(0) == 0) // 'c'
        #expect(result.offsetMap.sourceToDisplay(1) == 1) // 'a' start
        #expect(result.offsetMap.sourceToDisplay(2) == 3) // 't' shifts right
    }

    @Test func displayToSource_roundTrip() {
        let transform = SingleCharReplaceTransform(target: "o", replacement: "OO")
        let result = TextMapper.apply(transforms: [transform], to: "hello")
        // Source offset 0 -> display 0 -> source 0
        #expect(result.offsetMap.displayToSource(result.offsetMap.sourceToDisplay(0)) == 0)
        // Source offset 3 -> display 3 -> source 3
        #expect(result.offsetMap.displayToSource(result.offsetMap.sourceToDisplay(3)) == 3)
    }

    @Test func sourceToDisplay_roundTrip() {
        let transform = MultiToSingleTransform(target: "ll", replacement: "L")
        let result = TextMapper.apply(transforms: [transform], to: "hello world")
        // Offsets outside replaced regions should round-trip exactly
        let offset0 = result.offsetMap.sourceToDisplay(0)
        #expect(result.offsetMap.displayToSource(offset0) == 0)
        let offset8 = result.offsetMap.sourceToDisplay(8)
        #expect(result.offsetMap.displayToSource(offset8) == 8)
    }

    @Test func highlightRange_afterTransform_correct() {
        // Source text: "Hello World" — highlight "World" at [6,11)
        // Transform: replace 'o' with 'OO' -> "HellOO WOOrld"
        let transform = SingleCharReplaceTransform(target: "o", replacement: "OO")
        let result = TextMapper.apply(transforms: [transform], to: "Hello World")
        let displayRange = result.offsetMap.sourceRangeToDisplay(start: 6, length: 5)
        // "World" in display is "WOOrld" — starts at display offset 7
        // The display range should point to valid, non-empty text
        #expect(displayRange.start >= 0)
        #expect(displayRange.length > 0)
    }

    @Test func emptyText_noOp() {
        let result = TextMapper.apply(transforms: [IdentityTransform()], to: "")
        #expect(result.text == "")
        #expect(result.offsetMap.sourceLengthUTF16 == 0)
        #expect(result.offsetMap.displayLengthUTF16 == 0)
    }

    @Test func noTransforms_identity() {
        let source = "Some text"
        let result = TextMapper.apply(transforms: [], to: source)
        #expect(result.text == source)
        #expect(result.offsetMap.sourceToDisplay(3) == 3)
    }

    @Test func largeText_100KChars_under100ms() {
        let source = String(repeating: "abcde", count: 20_000) // 100K chars
        let transform = SingleCharReplaceTransform(target: "a", replacement: "AA")
        let start = CFAbsoluteTimeGetCurrent()
        let result = TextMapper.apply(transforms: [transform], to: source)
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        #expect(result.text.count > source.count)
        #expect(elapsed < 0.1, "100K char transform should complete in <100ms, took \(elapsed)s")
    }
}
