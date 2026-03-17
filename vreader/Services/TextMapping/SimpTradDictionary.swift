// Purpose: Common character mappings for Simplified/Traditional Chinese
// conversion. Used as supplementary reference alongside ICU transforms.
//
// Key decisions:
// - ICU CFStringTransform is the primary conversion engine (OS-level).
// - This dictionary provides common verification pairs for testing.
// - Not an exhaustive dictionary — ICU handles the full Unicode range.
//
// @coordinates-with: SimpTradTransform.swift

import Foundation

/// Common Simplified↔Traditional Chinese character pairs for verification.
enum SimpTradDictionary {
    /// Sample simplified → traditional pairs for testing/verification.
    static let simpToTradPairs: [(simp: Character, trad: Character)] = [
        ("国", "國"), ("学", "學"), ("书", "書"), ("长", "長"),
        ("门", "門"), ("问", "問"), ("间", "間"), ("关", "關"),
        ("东", "東"), ("车", "車"), ("马", "馬"), ("鱼", "魚"),
        ("鸟", "鳥"), ("龙", "龍"), ("风", "風"), ("云", "雲"),
        ("电", "電"), ("飞", "飛"), ("头", "頭"), ("见", "見"),
        ("说", "說"), ("读", "讀"), ("写", "寫"), ("听", "聽"),
        ("认", "認"), ("让", "讓"), ("议", "議"), ("对", "對"),
        ("时", "時"), ("万", "萬"),
    ]

    /// Sample traditional → simplified pairs for testing/verification.
    static let tradToSimpPairs: [(trad: Character, simp: Character)] = {
        simpToTradPairs.map { (trad: $0.trad, simp: $0.simp) }
    }()

    /// Quick lookup: is this a known simplified character?
    static func isSimplifiedChar(_ char: Character) -> Bool {
        simpToTradPairs.contains { $0.simp == char }
    }

    /// Quick lookup: is this a known traditional character?
    static func isTraditionalChar(_ char: Character) -> Bool {
        simpToTradPairs.contains { $0.trad == char }
    }
}
