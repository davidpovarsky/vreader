// Purpose: Unit tests for AppleFoundationModelsProfile.
// Validates dynamic profile mapping for Foundation Models sessions based on assistant scope and action mode.

import Testing
import Foundation
@testable import vreader

@Suite("AppleFoundationModelsProfileTests")
struct AppleFoundationModelsProfileTests {

    @Test func profileMappingMatchesScopeAndContext() {
        let sectionProfile = AppleFoundationModelsProfile.profile(for: .section)
        #expect(sectionProfile == .currentSection)

        let chapterProfile = AppleFoundationModelsProfile.profile(for: .chapter)
        #expect(chapterProfile == .chapterResearch)

        let wholeBookProfile = AppleFoundationModelsProfile.profile(for: .wholeBook)
        #expect(wholeBookProfile == .wholeBookResearch)
    }

    @Test func profileDescriptionsAreInformative() {
        for profile in AppleFoundationModelsProfile.allCases {
            #expect(!profile.identifier.isEmpty)
            #expect(!profile.systemPromptDirective.isEmpty)
        }
    }
}
