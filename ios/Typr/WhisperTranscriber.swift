import CoreML
import Foundation
import WhisperKit

/// Typr's Whisper decoding choices as plain values, so tests can check them without WhisperKit
/// types. `decodingOptions` maps them one to one.
nonisolated struct WhisperDecodingPlan: Equatable, Sendable {
    /// Always transcribe in the spoken language; never translate.
    let translates: Bool
    /// "de", "en", or nil for automatic detection.
    let languageCode: String?
    /// True only for automatic: WhisperKit's default (`!usePrefillPrompt`, false) would force English.
    let detectLanguage: Bool
    let usePrefillPrompt: Bool
    let skipSpecialTokens: Bool
    let withoutTimestamps: Bool
    let wordTimestamps: Bool
    /// Long captures are split at pauses (energy VAD) instead of hard 30-second windows.
    let chunksByVoiceActivity: Bool
    /// Typr never passes vocabulary as a Whisper prompt; vocabulary is post-processing only.
    let usesPromptTokens: Bool

    init(language: DictationLanguage) {
        translates = false
        languageCode = language.whisperLanguageCode
        detectLanguage = language.whisperLanguageCode == nil
        usePrefillPrompt = true
        skipSpecialTokens = true
        withoutTimestamps = true
        wordTimestamps = false
        chunksByVoiceActivity = true
        usesPromptTokens = false
    }

    var decodingOptions: DecodingOptions {
        DecodingOptions(
            verbose: false,
            task: translates ? .translate : .transcribe,
            language: languageCode,
            usePrefillPrompt: usePrefillPrompt,
            detectLanguage: detectLanguage,
            skipSpecialTokens: skipSpecialTokens,
            withoutTimestamps: withoutTimestamps,
            wordTimestamps: wordTimestamps,
            promptTokens: nil,
            chunkingStrategy: chunksByVoiceActivity ? .vad : ChunkingStrategy.none
        )
    }
}

/// Whisper Large V3 Turbo on this iPhone through WhisperKit. Preparation is local only: it never
/// downloads (no `WhisperKit.download`, `download: false`, a Typr tokenizer set before loading so
/// WhisperKit's Hub tokenizer fallback is unreachable). Only `WhisperModelInstaller` downloads.
/// The non-Sendable `WhisperKit` instance never leaves this actor; it is released by ARC (never
/// `unloadModels()` while a transcription may hold it), and Typr never holds two instances.
actor WhisperTranscriber: LocalTranscribing {
    enum TranscriberError: LocalizedError, Equatable {
        case notInstalled
        case notPrepared
        case silentAudio
        case emptyTranscript
        case corruptModel(String)
        /// Specialization is expected and the storage it needs is not free (bytes available).
        case insufficientStorage(Int64)

        var errorDescription: String? {
            switch self {
            case .notInstalled:
                "Whisper Large V3 Turbo is not downloaded. Download it under Speech engine."
            case .notPrepared:
                "Whisper Large V3 Turbo is not ready."
            case .silentAudio:
                "The recording is too quiet for Whisper. Try speaking closer to the microphone."
            case .emptyTranscript:
                "Whisper returned no text. Please try dictating again."
            case .corruptModel(let detail):
                "The Whisper model on this iPhone could not be loaded: \(detail) Download Whisper again."
            case .insufficientStorage(let available):
                "Whisper must be optimized for this iPhone first, which needs about "
                    + ByteCountFormatter.string(fromByteCount: WhisperModelSpec.optimizationStorageBytes, countStyle: .file)
                    + " of free storage ("
                    + ByteCountFormatter.string(fromByteCount: available, countStyle: .file)
                    + " is free). Free up storage, then prepare Whisper again."
            }
        }
    }

    nonisolated static let loadingDetail = "Loading Whisper"
    nonisolated static let optimizingDetail = "Optimizing Whisper for this iPhone. This can take a few minutes."

    nonisolated let displayName = SpeechEngineChoice.whisperLargeV3Turbo.displayName

    private let store: WhisperModelStore
    private let preparedLanguage: DictationLanguage
    private let availableCapacity: @Sendable () -> Int64?
    private let environment: String
    private var kit: WhisperKit?

    init(
        store: WhisperModelStore = .production,
        language: DictationLanguage,
        availableCapacity: (@Sendable () -> Int64?)? = nil,
        environment: String = WhisperPreparationPlan.currentEnvironment()
    ) {
        self.store = store
        self.preparedLanguage = language
        self.availableCapacity = availableCapacity ?? { store.availableCapacity() }
        self.environment = environment
    }

    var languageName: String {
        Self.languageName(for: preparedLanguage)
    }

    /// The dictation log's language for a capture: what Whisper was asked to recognize.
    nonisolated static func languageName(for language: DictationLanguage) -> String {
        switch language {
        case .automatic: "Automatic (detected by Whisper)"
        case .german: "German"
        case .english: "English"
        }
    }

    nonisolated static var computeOptions: ModelComputeOptions {
        ModelComputeOptions(
            melCompute: WhisperModelSpec.melComputeUnits,
            audioEncoderCompute: WhisperModelSpec.audioEncoderComputeUnits,
            textDecoderCompute: WhisperModelSpec.textDecoderComputeUnits
        )
    }

    /// The loaded decoder must have V3's vocabulary; anything else is a wrong or damaged model.
    nonisolated static func validateLogitsSize(_ size: Int?) throws {
        guard size == WhisperModelSpec.expectedLogitsSize else {
            throw TranscriberError.corruptModel("unexpected vocabulary size \(size.map(String.init) ?? "unknown").")
        }
    }

    /// An amplitude gate, not a speech detector: it must not discard ordinary quiet speech.
    /// WhisperKit's default EnergyVAD threshold (0.02 RMS, about -34 dBFS) is intended for
    /// chunk boundaries and rejected valid low-level microphone recordings before inference.
    /// Use 0.005 RMS (about -46 dBFS) here, keeping a floor against silence/faint room hum.
    /// WhisperKit 1.1.1's decoder no-speech probability is not implemented, so removing the
    /// gate altogether would allow Whisper to hallucinate text for silence.
    nonisolated static func containsSpeech(_ samples: [Float]) -> Bool {
        guard !samples.isEmpty else { return false }
        return EnergyVAD(energyThreshold: 0.005).voiceActivity(in: samples).contains(true)
    }

    /// Chunk texts joined with single spaces, trimmed.
    nonisolated static func joinedText(_ texts: [String]) -> String {
        texts.joined(separator: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    func prepare(
        progressHandler: @escaping @Sendable (ModelPreparationProgress) -> Void
    ) async throws {
        guard kit == nil else { return }
        // Exact files and marker, or stop: preparation never downloads.
        guard store.isInstalled else { throw TranscriberError.notInstalled }
        // Before any model work (including the tokenizer): stop if specialization is expected
        // and the storage it needs is not free.
        let record = store.preparationRecord
        let plan = WhisperPreparationPlan.decide(record: record, environment: environment,
                                                 availableBytes: availableCapacity())
        if case .insufficientStorage(let available) = plan {
            throw TranscriberError.insufficientStorage(available)
        }

        progressHandler(ModelPreparationProgress(fractionCompleted: 0.05, detail: "Reading the Whisper tokenizer"))
        let tokenizer: TyprWhisperTokenizer
        do {
            tokenizer = try await TyprWhisperTokenizer.load(from: store.tokenizerFolder)
        } catch {
            store.removeMarker()
            throw TranscriberError.corruptModel(error.localizedDescription)
        }
        try Task.checkCancellation()

        progressHandler(ModelPreparationProgress(
            fractionCompleted: 0.15,
            detail: plan == .optimize ? Self.optimizingDetail : Self.loadingDetail
        ))
        // Marked before Core ML starts: if iOS terminates Typr while specializing, the next
        // preparation expects specialization again and checks storage first.
        store.writePreparationRecord(WhisperPreparationRecord(loadedEnvironment: record.loadedEnvironment,
                                                              inProgress: true))
        let kit: WhisperKit
        do {
            kit = try await loadKit(tokenizer: tokenizer)
        } catch {
            store.writePreparationRecord(WhisperPreparationRecord(loadedEnvironment: record.loadedEnvironment,
                                                                  inProgress: false))
            throw error
        }
        store.writePreparationRecord(WhisperPreparationRecord(loadedEnvironment: environment, inProgress: false))
        // Skipped with the loader above; without it language prefill and detection are wrong.
        kit.textDecoder.isModelMultilingual = true
        try Task.checkCancellation()
        self.kit = kit
        progressHandler(ModelPreparationProgress(fractionCompleted: 1, detail: "Whisper ready"))
    }

    /// Local only. Prewarming specializes the three models one at a time and releases each
    /// before the real load, so specialization never holds all model weights at once (WhisperKit's
    /// documented peak-memory trade-off; a cached load costs about twice as long, under a second).
    private func loadKit(tokenizer: TyprWhisperTokenizer) async throws -> WhisperKit {
        let config = WhisperKitConfig(
            modelFolder: store.modelFolder.path,
            tokenizerFolder: store.tokenizerFolder,
            computeOptions: Self.computeOptions,
            verbose: false,
            logLevel: .none,
            prewarm: false,
            load: false,
            download: false
        )
        let kit = try await WhisperKit(config)
        // Set before loading: loadModels() then skips its tokenizer loader (and its Hub fallback).
        kit.tokenizer = tokenizer
        do {
            try await kit.prewarmModels()
            try Task.checkCancellation()
            try await kit.loadModels()
            try Self.validateLogitsSize(kit.textDecoder.logitsSize)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw TranscriberError.corruptModel(error.localizedDescription)
        }
        return kit
    }

    func transcribe(_ audioURL: URL) async throws -> String {
        try await transcribe(audioURL, vocabulary: [], language: preparedLanguage)
    }

    func transcribe(_ audioURL: URL, vocabulary: [String]) async throws -> String {
        try await transcribe(audioURL, vocabulary: vocabulary, language: preparedLanguage)
    }

    /// `vocabulary` is deliberately unused: Whisper gets no prompt; Typr's spelling passes and
    /// cleanup apply the vocabulary afterwards.
    func transcribe(_ audioURL: URL, vocabulary: [String], language: DictationLanguage) async throws -> String {
        // A local strong reference keeps this capture's model alive even if the actor's is dropped.
        guard let kit else { throw TranscriberError.notPrepared }
        let samples = try AudioProcessor.loadAudioAsFloatArray(fromPath: audioURL.path)
        guard Self.containsSpeech(samples) else { throw TranscriberError.silentAudio }
        let results = try await kit.transcribe(
            audioArray: samples,
            decodeOptions: WhisperDecodingPlan(language: language).decodingOptions
        )
        try Task.checkCancellation()
        let text = Self.joinedText(results.map(\.text))
        guard !text.isEmpty else { throw TranscriberError.emptyTranscript }
        return text
    }
}
