// Purpose: Dynamic session profiles for Apple Foundation Models sessions.
// Tailors instructions, budgets, and capabilities without injecting privileged system instructions.

import Foundation

enum AppleFoundationModelsProfile: String, Sendable, Codable, CaseIterable {
    case currentSection = "currentSection"
    case chapterResearch = "chapterResearch"
    case wholeBookResearch = "wholeBookResearch"
    case libraryResearch = "libraryResearch"
    case annotationMode = "annotationMode"
    case multimodalDocumentAnalysis = "multimodalDocumentAnalysis"

    static var currentSectionAssistant: AppleFoundationModelsProfile { .currentSection }

    var identifier: String {
        rawValue
    }

    var systemPromptDirective: String {
        systemInstructionSuffix
    }

    var systemInstructionSuffix: String {
        switch self {
        case .currentSection:
            return "Focus on the currently open section of the book. Answer concisely."
        case .chapterResearch:
            return "Analyze the current chapter context thoroughly and reference key events."
        case .wholeBookResearch:
            return "Synthesize broader book themes while respecting the reader's boundary."
        case .libraryResearch:
            return "Compare across available library books where relevant."
        case .annotationMode:
            return "Assist the reader in creating notes, highlights, and bookmarks safely."
        case .multimodalDocumentAnalysis:
            return "Analyze charts, diagrams, and visual layout on the document page."
        }
    }

    var defaultMaxTokens: Int {
        switch self {
        case .currentSection, .annotationMode: return 1024
        case .chapterResearch, .multimodalDocumentAnalysis: return 2048
        case .wholeBookResearch, .libraryResearch: return 4096
        }
    }

    static func profile(for scope: ChatContextScope) -> AppleFoundationModelsProfile {
        switch scope {
        case .section:
            return .currentSection
        case .chapter:
            return .chapterResearch
        case .bookSoFar, .wholeBook:
            return .wholeBookResearch
        }
    }
}
