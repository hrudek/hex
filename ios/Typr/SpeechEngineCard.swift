import SwiftUI

/// What one engine row shows, computed from plain values so it is testable without views.
nonisolated struct SpeechEngineRowState: Equatable, Sendable {
    enum Action: Equatable, Sendable {
        case none
        /// Choose the engine (prepares it; Parakeet may download through FluidAudio).
        case use
        /// Prepare the chosen engine again after a failure or at launch.
        case prepare
        /// Whisper only: the explicit download.
        case download
        case cancelDownload
        case retryDownload
    }

    let engine: SpeechEngineChoice
    /// "In use", "In use · automatic" or "Chosen" (chosen but not ready yet).
    let badge: String?
    let status: String
    /// 0...1 when a download or preparation is running.
    let progress: Double?
    let action: Action
    let actionTitle: String?
    /// False for choosing/preparing while a dictation runs; downloads are always allowed.
    let actionEnabled: Bool
    let warning: String?
    let note: String?

    static func make(
        engine: SpeechEngineChoice,
        preferred: SpeechEngineChoice?,
        current: SpeechEngineChoice?,
        availability: SpeechEngineAvailability?,
        whisperInstall: WhisperInstallState,
        language: DictationLanguage,
        preparation: ModelPreparationProgress?,
        failure: String?,
        canChangeEngine: Bool
    ) -> SpeechEngineRowState {
        let isWhisper = engine == .whisperLargeV3Turbo
        let isChosen = preferred == engine
        let badge: String? = current == engine
            ? (preferred == nil ? "In use · automatic" : "In use")
            : (isChosen ? "Chosen" : nil)
        let warning: String? = engine == .parakeetV2 && language != .english
            ? "English only. With Language set to \(language.label), German speech is not recognized correctly; Typr keeps your chosen engine."
            : nil
        let note: String? = isWhisper
            ? "First use optimizes the model for this iPhone and can take several minutes. Your vocabulary and the tech glossary are applied after recognition (spelling and AI cleanup), not as Whisper hints."
            : nil

        func row(_ status: String, progress: Double? = nil, action: Action = .none, title: String? = nil) -> SpeechEngineRowState {
            let enabled: Bool
            switch action {
            case .use, .prepare: enabled = canChangeEngine
            default: enabled = true
            }
            return SpeechEngineRowState(engine: engine, badge: badge, status: status, progress: progress,
                                        action: action, actionTitle: title, actionEnabled: enabled,
                                        warning: warning, note: note)
        }

        if isWhisper {
            switch whisperInstall {
            case .downloading(let progress):
                let done = ByteCountFormatter.string(fromByteCount: progress.completedBytes, countStyle: .file)
                let total = ByteCountFormatter.string(fromByteCount: progress.totalBytes, countStyle: .file)
                return row("Downloading \(done) of \(total) (\(Int(progress.fraction * 100))%)",
                           progress: progress.fraction, action: .cancelDownload, title: "Cancel")
            case .verifying:
                return row("Checking the downloaded files")
            default:
                break
            }
        }
        if isChosen, current != engine, let preparation {
            return row(preparation.detail, progress: preparation.fractionCompleted)
        }
        if isChosen, current != engine, let failure {
            if isWhisper, whisperInstall != .installed {
                return row(failure, action: .retryDownload, title: "Retry")
            }
            return row(failure, action: .prepare, title: "Try again")
        }
        if isWhisper {
            switch whisperInstall {
            case .cancelled:
                return row("Download cancelled. Retry starts the download again; files already downloaded are kept.",
                           action: .retryDownload, title: "Retry")
            case .failed(let message):
                return row(message, action: .retryDownload, title: "Retry")
            default:
                break
            }
        }
        guard let availability else { return row("Checking this iPhone…") }
        guard availability.isSupported else { return row(availability.detail) }
        if current == engine {
            return isChosen
                ? row("Ready on this iPhone")
                : row("Ready on this iPhone", action: .use, title: "Use")
        }
        if isWhisper, whisperInstall != .installed {
            return row(availability.detail, action: .download, title: "Download (\(WhisperModelSpec.downloadSizeLabel))")
        }
        if isChosen {
            return row(availability.detail, action: .prepare, title: "Prepare")
        }
        let title = engine == .parakeetV2 && availability != .installed ? "Download and use" : "Use"
        return row(availability.detail, action: .use, title: title)
    }
}

/// The Speech engine section: Apple Speech, Parakeet V2 and Whisper Large V3 Turbo, each with
/// its languages and live status. Choosing applies to the next dictation and never falls back.
@MainActor
struct SpeechEngineCard: View {
    let dictation: DictationController
    @State private var installer = WhisperModelInstaller.shared
    @State private var availability: [SpeechEngineChoice: SpeechEngineAvailability] = [:]
    @State private var availabilityGeneration: UInt64 = 0
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Speech engine")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(TyprTheme.textMuted)
                .padding(.leading, 16)

            VStack(spacing: 0) {
                ForEach(Array(SpeechEngineChoice.allCases.enumerated()), id: \.element) { index, engine in
                    if index > 0 {
                        Divider().overlay(TyprTheme.borderWeak).padding(.leading, 16)
                    }
                    engineRow(state(for: engine))
                }
                Divider().overlay(TyprTheme.borderWeak).padding(.leading, 16)
                Text(footer)
                    .font(.system(size: 12))
                    .foregroundStyle(TyprTheme.textMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            }
            .background(TyprTheme.bgBase, in: RoundedRectangle(cornerRadius: TyprTheme.cardRadius, style: .continuous))
        }
        .task(id: refreshKey) {
            installer.refresh()
            await refreshAvailability()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                installer.refresh()
                Task { await refreshAvailability() }
            }
        }
    }

    /// Re-read availability when the language, the ready engine or the Whisper install changes.
    private var refreshKey: String {
        let failed: Bool
        if case .failed = dictation.phase { failed = true } else { failed = false }
        return "\(dictation.dictationLanguage.rawValue)|\(dictation.currentEngine?.rawValue ?? "-")|\(installer.state == .installed)|\(failed)"
    }

    private func refreshAvailability() async {
        let key = refreshKey
        availabilityGeneration &+= 1
        let generation = availabilityGeneration
        for engine in SpeechEngineChoice.allCases {
            let result = await dictation.engineAvailability(engine)
            guard !Task.isCancelled, refreshKey == key, availabilityGeneration == generation else { return }
            availability[engine] = result
        }
    }

    private var footer: String {
        var lines: [String] = []
        if let preferred = dictation.preferredEngine {
            lines.append("Chosen: \(preferred.displayName). Typr never switches to another engine by itself.")
        } else {
            lines.append("No engine chosen: Typr uses Apple Speech when available, else Parakeet V2.")
        }
        if !dictation.canChangeEngine {
            lines.append("Finish the current dictation to change the engine.")
        }
        lines.append("All engines run on this iPhone; audio never leaves it.")
        return lines.joined(separator: "\n")
    }

    private func state(for engine: SpeechEngineChoice) -> SpeechEngineRowState {
        var preparation: ModelPreparationProgress?
        var failure: String?
        if dictation.preferredEngine == engine {
            switch dictation.phase {
            case .preparingModel: preparation = dictation.modelPreparation
            case .failed(let message) where dictation.currentEngine == nil: failure = message
            default: break
            }
        }
        return SpeechEngineRowState.make(
            engine: engine,
            preferred: dictation.preferredEngine,
            current: dictation.currentEngine,
            availability: availability[engine],
            whisperInstall: installer.state,
            language: dictation.dictationLanguage,
            preparation: preparation,
            failure: failure,
            canChangeEngine: dictation.canChangeEngine
        )
    }

    private func perform(_ state: SpeechEngineRowState) {
        switch state.action {
        case .none: break
        case .use: dictation.selectEngine(state.engine)
        case .prepare: dictation.prepareModel()
        case .download, .retryDownload: installer.install()
        case .cancelDownload: installer.cancel()
        }
    }

    private func engineRow(_ state: SpeechEngineRowState) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(state.engine.displayName)
                    .font(.system(size: 15))
                    .foregroundStyle(TyprTheme.textBase)
                if let badge = state.badge {
                    Text(badge)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(badge.hasPrefix("In use") ? TyprTheme.success : TyprTheme.textMuted)
                }
                Spacer(minLength: 8)
                if let title = state.actionTitle {
                    Button(title) { perform(state) }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(TyprTheme.textBase)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 30)
                        .background(Color.white.opacity(0.09), in: Capsule())
                        .buttonStyle(.plain)
                        .disabled(!state.actionEnabled)
                        .opacity(state.actionEnabled ? 1 : 0.4)
                }
            }
            Text(state.engine.summary)
                .font(.system(size: 12))
                .foregroundStyle(TyprTheme.textMuted)
            Text("Languages: \(state.engine.languageSummary)")
                .font(.system(size: 12))
                .foregroundStyle(TyprTheme.textMuted)
            Text(state.status)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(TyprTheme.textBase)
            if let progress = state.progress {
                ProgressView(value: progress).tint(TyprTheme.textBase)
            }
            if let warning = state.warning {
                Text(warning)
                    .font(.system(size: 12))
                    .foregroundStyle(TyprTheme.warmMic)
            }
            if let note = state.note {
                Text(note)
                    .font(.system(size: 12))
                    .foregroundStyle(TyprTheme.textFaint)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
