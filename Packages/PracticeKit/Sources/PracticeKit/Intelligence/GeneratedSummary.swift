import Foundation
#if canImport(FoundationModels)
import FoundationModels

@Generable
struct GeneratedWeeklySummary {
    @Guide(description: "A short, specific headline about the week, under 8 words. No exclamation marks.")
    var headline: String

    @Guide(description: "Up to three factual observations drawn only from the data.", .maximumCount(3))
    var observations: [String]

    @Guide(description: "One practical, gentle suggestion for next week, under 25 words.")
    var suggestion: String
}

/// On-device weekly summary using Apple Intelligence. Falls back to the
/// rules-based summary whenever the model is unavailable or fails.
public enum WeeklySummaryGenerator {
    public static var isModelAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    public static func summary(for input: WeeklySummaryInput) async -> WeeklySummary {
        guard isModelAvailable, input.totalMinutes > 0 else { return RulesBasedSummary.make(input) }
        let session = LanguageModelSession(instructions: """
            You summarize a musician's practice week from aggregated numbers. \
            Be encouraging but plain. Never invent facts beyond the data. \
            You are not a teacher; don't give technical playing advice. \
            Never guilt the user about missed days.
            """)
        do {
            let response = try await session.respond(to: input.promptText, generating: GeneratedWeeklySummary.self)
            let content = response.content
            return WeeklySummary(headline: content.headline, observations: content.observations,
                                 suggestion: content.suggestion, isGenerated: true)
        } catch {
            return RulesBasedSummary.make(input)
        }
    }
}
#else
public enum WeeklySummaryGenerator {
    public static var isModelAvailable: Bool { false }
    public static func summary(for input: WeeklySummaryInput) async -> WeeklySummary { RulesBasedSummary.make(input) }
}
#endif
