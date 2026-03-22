// Purpose: Tests for PageTurnAnimator — page turn animation types and logic.
// Validates animation enum codability, reduce-motion respect, and direction semantics.
//
// @coordinates-with PageTurnAnimator.swift

import Testing
import Foundation
@testable import vreader

@Suite("PageTurnAnimator")
struct PageTurnAnimatorTests {

    // MARK: - PageTurnAnimation Codable

    @Test func animation_codable_roundTrip_none() throws {
        let original = PageTurnAnimation.none
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PageTurnAnimation.self, from: data)
        #expect(decoded == original)
    }

    @Test func animation_codable_roundTrip_slide() throws {
        let original = PageTurnAnimation.slide
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PageTurnAnimation.self, from: data)
        #expect(decoded == original)
    }

    @Test func animation_codable_roundTrip_cover() throws {
        let original = PageTurnAnimation.cover
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PageTurnAnimation.self, from: data)
        #expect(decoded == original)
    }

    @Test func animation_rawValue_none() {
        #expect(PageTurnAnimation.none.rawValue == "none")
    }

    @Test func animation_rawValue_slide() {
        #expect(PageTurnAnimation.slide.rawValue == "slide")
    }

    @Test func animation_rawValue_cover() {
        #expect(PageTurnAnimation.cover.rawValue == "cover")
    }

    // MARK: - Direction

    @Test func direction_forward_backward_distinct() {
        let forward = PageTurnAnimator.Direction.forward
        let backward = PageTurnAnimator.Direction.backward
        #expect(forward != backward)
    }

    // MARK: - Animation Duration

    @Test func animation_none_durationIsZero() {
        #expect(PageTurnAnimator.duration(for: .none) == 0)
    }

    @Test func animation_slide_duration_300ms() {
        #expect(PageTurnAnimator.duration(for: .slide) == 0.3)
    }

    @Test func animation_cover_duration_300ms() {
        #expect(PageTurnAnimator.duration(for: .cover) == 0.3)
    }

    @Test func animation_respectsReduceMotion_returnsZero() {
        // When reduceMotion is simulated, all durations should be 0
        #expect(PageTurnAnimator.duration(for: .slide, reduceMotion: true) == 0)
        #expect(PageTurnAnimator.duration(for: .cover, reduceMotion: true) == 0)
        #expect(PageTurnAnimator.duration(for: .none, reduceMotion: true) == 0)
    }

    @Test func animation_respectsReduceMotion_nonReduced_normalDuration() {
        #expect(PageTurnAnimator.duration(for: .slide, reduceMotion: false) == 0.3)
        #expect(PageTurnAnimator.duration(for: .cover, reduceMotion: false) == 0.3)
    }

    // MARK: - All Cases

    @Test func animation_allCases() {
        let cases = PageTurnAnimation.allCases
        #expect(cases.count == 3)
        #expect(cases.contains(.none))
        #expect(cases.contains(.slide))
        #expect(cases.contains(.cover))
    }

    // MARK: - Sendable

    @Test func animation_isSendable() {
        let animation: Sendable = PageTurnAnimation.slide
        #expect(animation is PageTurnAnimation)
    }
}
