import Foundation

/// Configured precedence for new recordings, not per-recording cleanup admission.
nonisolated enum TyprCleanupPath: Equatable, Sendable {
    case typr
    case upstreamExperiment
    case none
    case unsupportedOS

    static func resolve(frameworkAvailable: Bool, typrOn: Bool, upstreamOn: Bool) -> Self {
        guard frameworkAvailable else { return .unsupportedOS }
        if typrOn { return .typr }
        if upstreamOn { return .upstreamExperiment }
        return .none
    }
}

nonisolated struct TyprModelInfo: Equatable, Sendable {
    let path: TyprCleanupPath
    let osVersion: String
    let availabilityReason: String?

    var lines: [String] {
        let configuration: String
        switch path {
        case .typr:
            configuration = "Typr AI cleanup (general use, permissive content transformations)"
        case .upstreamExperiment:
            configuration = "Clean up with Apple Intelligence (Experiments) (general use, default guardrails)"
        case .none:
            return ["No model: AI cleanup and Clean up with Apple Intelligence are off"]
        case .unsupportedOS:
            return ["No model: requires iOS 26 or later"]
        }
        return [
            "Apple on-device foundation model · running on iOS \(osVersion)",
            "Used for new recordings by \(configuration)",
            availabilityReason.map { "Model availability: \($0)" }
                ?? "Model availability: available. Model version managed by Apple. Never used in Verbatim."
        ]
    }
}

/// Reads settings and only the selected configuration's availability. Never starts model work.
/// Plain (non-Sendable) closures inherit the main actor where they are formed, like
/// `CleanupAvailabilityCache`, so tests can count calls in captured locals.
@MainActor
struct TyprModelInfoReader {
    let frameworkAvailable: () -> Bool
    let typrOn: () -> Bool
    let upstreamOn: () -> Bool
    let typrReason: () -> String?
    let upstreamReason: () -> String?
    let osVersion: () -> String

    func read() -> TyprModelInfo {
        let path = TyprCleanupPath.resolve(
            frameworkAvailable: frameworkAvailable(),
            typrOn: typrOn(),
            upstreamOn: upstreamOn()
        )
        let reason: String?
        switch path {
        case .typr: reason = typrReason()
        case .upstreamExperiment: reason = upstreamReason()
        case .none, .unsupportedOS: reason = nil
        }
        return TyprModelInfo(path: path, osVersion: osVersion(), availabilityReason: reason)
    }

    static let production = TyprModelInfoReader(
        frameworkAvailable: {
            #if canImport(FoundationModels)
            if #available(iOS 26.0, *) { return true }
            #endif
            return false
        },
        typrOn: { TyprSettings().aiCleanup },
        upstreamOn: { AppleIntelligenceCleanupSettings().isEnabled },
        typrReason: { TranscriptCleanupProduction.unavailableReason },
        upstreamReason: { AppleIntelligenceCleanupAvailability.current.reason },
        osVersion: {
            let version = ProcessInfo.processInfo.operatingSystemVersion
            return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        }
    )
}
