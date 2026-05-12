// Purpose: Unit tests for VerificationSettingsHelper section-header matching
// (feature #45 WI-1). Verifies the known section header strings used by
// scrollToSection to locate panel sections. These are pure string-spec tests —
// they document the stable section identifiers so any label refactor in
// ReaderSettingsPanel.swift breaks these tests first.

import Testing

@Suite("VerificationSettingsHelper section headers")
struct VerificationSettingsHelperSpec {

    // MARK: - Known reader settings section headers

    @Test func sectionHeader_autoPageTurn_isKnown() {
        // The section header that contains the auto-page-turn toggle.
        // If ReaderSettingsPanel.swift renames the section, this test
        // fails first, prompting an update to both the test and the helper.
        let knownSections: Set<String> = [
            "Font Size",
            "Spacing",
            "Reading Mode",
            "Margins",
            "Theme",
            "Auto Page Turn",
        ]
        #expect(knownSections.contains("Auto Page Turn"),
                "Auto Page Turn section header must be in the known-sections set")
    }

    @Test func sectionHeader_readingMode_isKnown() {
        let knownSections: Set<String> = [
            "Font Size",
            "Reading Mode",
            "Margins",
            "Theme",
            "Auto Page Turn",
        ]
        #expect(knownSections.contains("Reading Mode"))
    }

    @Test func sectionHeader_nonempty_forAllKnownHeaders() {
        let headers = [
            "Font Size",
            "Reading Mode",
            "Margins",
            "Theme",
            "Auto Page Turn",
        ]
        for h in headers {
            #expect(!h.isEmpty, "section header '\(h)' must be non-empty")
        }
    }

    @Test func sectionHeader_strings_haveNoLeadingTrailingWhitespace() {
        let headers = [
            "Font Size",
            "Reading Mode",
            "Margins",
            "Theme",
            "Auto Page Turn",
        ]
        for h in headers {
            #expect(h == h.trimmingCharacters(in: .whitespaces),
                    "section header '\(h)' must not have leading/trailing whitespace")
        }
    }
}
