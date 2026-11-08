import Foundation
import NaturalLanguage
import UIKit
#if canImport(FoundationModels)
import FoundationModels
#endif

@MainActor
enum TranscriptCleanupProduction {
    static func dependencies() -> TranscriptCleanupDependencies? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return TranscriptCleanupDependencies(cleaner: AppleIntelligenceCleaner(), language: CleanupLanguageDetector(),
                                                 background: CleanupBackgroundTasks(), isEnabled: { HexPlusSettings().aiCleanup },
                                                 observer: CleanupObservers(observers: [CleanupLogger(), diagnostics]))
        }
        #endif
        return nil
    }

    static let diagnostics = CleanupDiagnostics()

    /// The last dictation's cleanup outcome for the Hex+ card (no dictated text).
    static var lastSummary: String? { diagnostics.lastSummary() }

    private static let availabilityCache = CleanupAvailabilityCache { TranscriptCleanupProduction.freshUnavailableReason }

    static func invalidateAvailability() { availabilityCache.invalidate() }

    static var unavailableReason: String? { availabilityCache.reason }

    private static var freshUnavailableReason: String? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) { return AppleIntelligenceCleaner().unavailableReason }
        #endif
        return "Requires iOS 26 or later"
    }
}

@MainActor
private final class CleanupBackgroundTasks: BackgroundTaskStarting {
    func begin(expiration: @escaping @MainActor () -> Void) -> Int? {
        let token = UIApplication.shared.beginBackgroundTask(withName: "AI cleanup") {
            // UIKit delivers background expiration on the main thread.
            MainActor.assumeIsolated { expiration() }
        }
        return token == .invalid ? nil : token.rawValue
    }

    func end(_ token: Int) {
        UIApplication.shared.endBackgroundTask(UIBackgroundTaskIdentifier(rawValue: token))
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
@MainActor
private struct CleanupLanguageDetector: LanguageDetecting {
    func supports(_ text: String) -> Bool {
        guard CleanupGuard.wordCount(text) >= 3 else { return false }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let top = recognizer.languageHypotheses(withMaximum: 2).max(by: { $0.value < $1.value }),
              top.value >= 0.80 else { return false }
        return SystemLanguageModel(useCase: .general, guardrails: .permissiveContentTransformations).supportsLocale(Locale(identifier: top.key.rawValue))
    }
}

@available(iOS 26.0, *)
@MainActor
private struct AppleIntelligenceCleaner: TranscriptCleaning {
    var unavailableReason: String? {
        switch SystemLanguageModel(useCase: .general, guardrails: .permissiveContentTransformations).availability {
        case .available: return nil
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible: return "This device does not support Apple Intelligence"
            case .appleIntelligenceNotEnabled: return "Turn on Apple Intelligence in Settings to use this"
            case .modelNotReady: return "The Apple Intelligence model isn't ready yet"
            @unknown default: return "Apple Intelligence is unavailable"
            }
        @unknown default: return "Apple Intelligence is unavailable"
        }
    }

    func makeSession() -> any CleanupSession { AppleCleanupSession() }
}

@available(iOS 26.0, *)
@Generable
private struct CleanedTranscript {
    @Guide(description: "The transcript with only obvious local recognition errors and explicit self-corrections resolved; otherwise unchanged.")
    var text: String
}

@available(iOS 26.0, *)
@MainActor
private final class AppleCleanupSession: CleanupSession {
    private let model: SystemLanguageModel
    private let session: LanguageModelSession

    init() {
        let model = SystemLanguageModel(useCase: .general, guardrails: .permissiveContentTransformations)
        self.model = model
        session = LanguageModelSession(model: model, instructions: CleanupPrompt.instructions)
    }

    func prewarm() async { session.prewarm() }

    func clean(_ text: String, style: DictationStyle) async throws -> String {
        guard case .available = model.availability else { throw CleanupModelError.unavailable }
        let prompt = try CleanupPrompt.transcript(text, style: style)
        do {
            let response = try await session.respond(to: prompt, generating: CleanedTranscript.self,
                options: GenerationOptions(sampling: .greedy, maximumResponseTokens: min(1200, text.utf8.count / 2 + 128)))
            return response.content.text
        } catch let error as LanguageModelSession.GenerationError {
            switch error {
            case .exceededContextWindowSize: throw CleanupModelError.contextWindow
            case .refusal, .guardrailViolation: throw CleanupModelError.refused
            case .rateLimited: throw CleanupModelError.rateLimited
            default: throw CleanupModelError.generationFailed
            }
        } catch {
            throw CleanupModelError.generationFailed
        }
    }
}
#endif
