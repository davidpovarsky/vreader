// Purpose: Dynamic session profiles for Apple Foundation Models sessions.
// Tailors instructions, budgets, and capabilities without injecting privileged system instructions.

import Foundation

enum AppleFoundationModelsProfile: String, Sendable, Codable, CaseIterable {
    case currentSectionAssistant
    case chapterResearch
    case wholeBookResearch
    case libraryResearch
    case annotationMode
    case multimodalDocumentAnalysis

    var systemInstructionSuffix: String {
        switch self {
        case .currentSectionAssistant:
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
        case .currentSectionAssistant, .annotationMode: return 1024
        case .chapterResearch, .multimodalDocumentAnalysis: return 2048
        case .wholeBookResearch, .libraryResearch: return 4096
        }
    }
}
