import AVFAudio
import Foundation
import Observation
import UIKit

struct DictationLogText: Codable, Equatable, Sendable {
    static let maximumBytes = 4_000
    let text: String
    let truncated: Bool
    let originalUTF8Bytes: Int
    let wordCount: Int

    init(_ source: String) {
        originalUTF8Bytes = source.utf8.count
        wordCount = CleanupGuard.wordCount(source)
        truncated = originalUTF8Bytes > Self.maximumBytes
        text = Self.capped(source)
    }

    /// A Character (including combining marks / joined emoji) is never split. The ellipsis
    /// is inside the budget; an individual Character larger than the budget is omitted.
    private static func capped(_ source: String) -> String {
        guard source.utf8.count > maximumBytes else { return source }
        var result = "", bytes = 0
        for character in source {
            let count = String(character).utf8.count
            guard bytes + count <= maximumBytes - "…".utf8.count else { break }
            result.append(character)
            bytes += count
        }
        return result + "…"
    }

    func recapped() -> Self {
        // Preserve pre-truncation counts when reading our own file, but never trust its text cap.
        Self(text: Self.capped(text), truncated: truncated || text.utf8.count > Self.maximumBytes,
             originalUTF8Bytes: max(originalUTF8Bytes, text.utf8.count), wordCount: max(0, wordCount))
    }

    private init(text: String, truncated: Bool, originalUTF8Bytes: Int, wordCount: Int) {
        self.text = text
        self.truncated = truncated
        self.originalUTF8Bytes = originalUTF8Bytes
        self.wordCount = wordCount
    }
}

enum DictationLogStatus: String, Codable, Sendable {
    case transcribing, finished, asrFailed, cancelled, interrupted

    var label: String {
        switch self {
        case .transcribing: "Transcribing…"
        case .finished: "Finished"
        case .asrFailed: "Speech recognition failed"
        case .cancelled: "Cancelled"
        case .interrupted: "The app ended before this dictation finished"
        }
    }
}

enum DictationLogCleanupPath: String, Codable, Sendable { case hexPlus, upstream, none }

enum DictationLogASRFailure: String, Codable, Sendable {
    case modelNotReady, cancelled, noSpeech, other

    static func classify(_ error: any Error) -> Self {
        if error is CancellationError { return .cancelled }
        if let error = error as? ParakeetTranscriber.TranscriberError {
            switch error {
            case .notPrepared: return .modelNotReady
            case .emptyTranscript: return .noSpeech
            }
        }
        if #available(iOS 26.0, *), let error = error as? AppleSpeechTranscriber.TranscriberError {
            switch error {
            case .unavailable: return .modelNotReady
            case .emptyTranscript: return .noSpeech
            case .authorizationDenied: return .other
            }
        }
        return .other
    }
}

/// All cross-queue state is immutable value snapshots, never a controller, model or AVAudioSession.
struct DictationLogContext: Codable, Equatable, Sendable {
    var createdAt = Date()
    var appVersion = "unknown"
    var appBuild = "unknown"
    var systemVersion = "unknown"
    var keyboardJob = false
    var copyToPasteboard = false
    var style = "Polished"
    var speechEngine = "unknown"
    var speechLanguage = "unknown"
    var recordingDuration: TimeInterval = 0
    var inputPortTypes: [String] = []
    var bluetoothInput = false
    var loudestAverageDBFS: Float?
    var cleanupPath: DictationLogCleanupPath = .none
    var vocabularyCount = 0

    @MainActor
    static func capture(keyboardJob: Bool, copyToPasteboard: Bool, style: DictationStyle,
                        engine: String, language: String, duration: TimeInterval,
                        loudestAverage: Float?, cleanupPath: DictationLogCleanupPath,
                        vocabularyCount: Int) -> Self {
        var context = Self()
        context.appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        context.appBuild = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        context.systemVersion = UIDevice.current.systemVersion
        context.keyboardJob = keyboardJob
        context.copyToPasteboard = copyToPasteboard
        context.style = style.label
        context.speechEngine = engine
        context.speechLanguage = language
        context.recordingDuration = duration
        let inputs = AVAudioSession.sharedInstance().currentRoute.inputs
        context.inputPortTypes = inputs.map { $0.portType.rawValue } // Never the device name or UID.
        context.bluetoothInput = inputs.contains {
            $0.portType == .bluetoothHFP || $0.portType == .bluetoothLE || $0.portType == .bluetoothA2DP
        }
        context.loudestAverageDBFS = loudestAverage
        context.cleanupPath = cleanupPath
        context.vocabularyCount = vocabularyCount
        return context
    }
}

struct DictationLogEntry: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var schemaVersion = DictationLogDocument.version
    var context: DictationLogContext
    var status: DictationLogStatus = .transcribing
    var asrFailure: DictationLogASRFailure?
    var asrErrorType: String?
    var recognized: DictationLogText?
    var aiInput: DictationLogText?
    var aiAnswer: DictationLogText?
    var finalText: DictationLogText?
    var answerUse: String?
    var cleanupOutcome: String?
    var cleanupSummary: String?
    var cleanupChanged: Bool?
    var pipelineChanged: Bool?
    var upstreamOutcome: String?
    var firstSpellingChanged = false
    var secondSpellingChanged = false
    var asrMilliseconds: Int64?
    var cleanupMilliseconds: Int64?
    var modelMilliseconds: Int64?
    var stopToFinalMilliseconds: Int64?
    var promptRevision = CleanupPrompt.revision
    var guardRevision = CleanupGuard.revision

    var sourceLabel: String { context.keyboardJob ? "Keyboard" : "App" }
    var outputLabel: String {
        var outputs = ["shown in app"]
        if context.keyboardJob { outputs.append("provided to keyboard") }
        if context.copyToPasteboard, finalText?.originalUTF8Bytes ?? 0 > 0 { outputs.append("copied to clipboard") }
        return outputs.joined(separator: "; ")
    }
    var lateAnswerLabel: String {
        switch cleanupOutcome {
        case "failed(deadline)": "arrived after the 4 s deadline; not used"
        case "failed(expired)": "arrived after iOS ended the background time; not used"
        default: "arrived after cleanup had resolved; not used"
        }
    }
    var answerLabel: String { answerUse == "late" ? lateAnswerLabel : (answerUse ?? "No model answer") }

    mutating func recap() {
        recognized = recognized?.recapped()
        aiInput = aiInput?.recapped()
        aiAnswer = aiAnswer?.recapped()
        finalText = finalText?.recapped()
    }
}

struct DictationLogDocument: Codable, Sendable {
    static let version = 1
    var schemaVersion = version
    var entries: [DictationLogEntry]
}

struct DictationLogToken: Equatable, Sendable {
    let enabled: Bool
    let epoch: UInt64
}

@MainActor
@Observable
final class DictationLogStore {
    static let shared = DictationLogStore(
        storage: DictationLogStorage(url: URL.applicationSupportDirectory
            .appendingPathComponent("HexPlus", isDirectory: true).appendingPathComponent("dictation-log.json")))
    static let maximumEntries = 20
    private(set) var entries: [DictationLogEntry] = [] // newest first
    private(set) var epoch: UInt64 = 0
    private(set) var isEnabled: Bool
    private(set) var storageProblem: String?
    private let settings: HexPlusSettings
    private var storageRequest: UInt64 = 0
    let storage: DictationLogStorage

    init(storage: DictationLogStorage, settings: HexPlusSettings = HexPlusSettings()) {
        self.storage = storage
        self.settings = settings
        isEnabled = settings.dictationLog
        let loaded = storage.load(enabled: isEnabled)
        storageProblem = loaded.problem ? Self.problem : nil
        var seen = Set<UUID>()
        entries = Array(loaded.entries.sorted { $0.context.createdAt > $1.context.createdAt }
            .filter { seen.insert($0.id).inserted }.prefix(Self.maximumEntries))
        for index in entries.indices {
            entries[index].recap()
            if entries[index].status == .transcribing { entries[index].status = .interrupted }
        }
        if isEnabled, !entries.isEmpty { persist() }
    }

    private static let problem = "The dictation log could not be saved or deleted. Dictation still works."

    func token() -> DictationLogToken { DictationLogToken(enabled: isEnabled, epoch: epoch) }

    func begin(token: DictationLogToken, context: DictationLogContext,
               stoppedAt: ContinuousClock.Instant? = nil,
               clock: @escaping @MainActor () -> ContinuousClock.Instant = { .now }) -> DictationLogRecording? {
        guard token.enabled, isEnabled, token.epoch == epoch else { return nil }
        let entry = DictationLogEntry(context: context)
        entries.insert(entry, at: 0)
        entries = Array(entries.prefix(Self.maximumEntries))
        persist()
        return DictationLogRecording(entryID: entry.id, epoch: epoch, store: self, stoppedAt: stoppedAt, clock: clock)
    }

    func setEnabled(_ enabled: Bool) {
        settings.dictationLog = enabled
        guard isEnabled != enabled else { return }
        isEnabled = enabled
        // Both edges invalidate every old capture's permission, even before it reached ASR.
        clear()
    }

    func clear() {
        epoch &+= 1
        entries = []
        submit(nil)
    }

    fileprivate func update(_ id: UUID, epoch: UInt64, _ mutate: (inout DictationLogEntry) -> Void) {
        guard isEnabled, self.epoch == epoch, let index = entries.firstIndex(where: { $0.id == id }) else { return }
        mutate(&entries[index])
        persist()
    }

    private func persist() {
        do {
            let encoder = JSONEncoder()
            var data = try encoder.encode(DictationLogDocument(entries: entries))
            while data.count > DictationLogStorage.maximumBytes, !entries.isEmpty {
                entries.removeLast()
                data = try encoder.encode(DictationLogDocument(entries: entries))
            }
            submit(data)
        } catch { storageProblem = Self.problem }
    }

    private func submit(_ data: Data?) {
        storageRequest &+= 1
        let request = storageRequest
        storage.submit(data, epoch: epoch) { [weak self] epoch, success in
            Task { @MainActor [weak self] in
                guard let self, self.epoch == epoch, self.storageRequest == request else { return }
                self.storageProblem = success ? nil : Self.problem
            }
        }
    }
}

/// One capture, one immutable entry ID and permission epoch; never a global current draft.
@MainActor
final class DictationLogRecording: CleanupTextDiagnostics {
    let entryID: UUID
    private let epoch: UInt64
    private weak var store: DictationLogStore?
    private let clock: @MainActor () -> ContinuousClock.Instant
    private let stopped: ContinuousClock.Instant
    private var terminal: DictationLogStatus?
    private var raw: String?

    fileprivate init(entryID: UUID, epoch: UInt64, store: DictationLogStore,
                     stoppedAt: ContinuousClock.Instant?, clock: @escaping @MainActor () -> ContinuousClock.Instant) {
        self.entryID = entryID
        self.epoch = epoch
        self.store = store
        self.clock = clock
        stopped = stoppedAt ?? clock()
    }

    private func update(_ mutate: (inout DictationLogEntry) -> Void) {
        store?.update(entryID, epoch: epoch, mutate)
    }

    func recognized(_ text: String, spelled: String, asrMilliseconds: Int64) {
        guard terminal == nil else { return }
        raw = text
        update {
            $0.recognized = DictationLogText(text)
            $0.aiInput = text == spelled ? nil : DictationLogText(spelled)
            $0.firstSpellingChanged = text != spelled
            $0.asrMilliseconds = asrMilliseconds
        }
    }

    func upstreamResult(_ result: String?, input: String) {
        guard terminal == nil else { return }
        update { $0.upstreamOutcome = result.map { $0 == input ? "unchanged" : "changed" } ?? "no result" }
    }

    func cleanupResolved(_ observation: CleanupObservation, changed: Bool?) {
        guard terminal == nil else { return }
        update {
            $0.cleanupOutcome = observation.outcome.dictationLogLabel
            $0.cleanupSummary = CleanupDiagnostics.summary(observation.outcome,
                latencyMilliseconds: observation.latencyMilliseconds, changed: changed)
            $0.cleanupChanged = changed
            $0.cleanupMilliseconds = observation.latencyMilliseconds
        }
    }

    func modelFailed(modelMilliseconds: Int64) {
        guard terminal == nil else { return }
        update { $0.modelMilliseconds = modelMilliseconds }
    }

    func modelAnswer(_ text: String, use: CleanupAnswerUse, modelMilliseconds: Int64) {
        if let terminal {
            guard (terminal == .finished || terminal == .asrFailed), use == .late else { return }
        }
        update {
            $0.aiAnswer = DictationLogText(text)
            switch use {
            case .accepted: $0.answerUse = "accepted"
            case .rejected(let reason): $0.answerUse = "rejected(\(reason.label)); not used"
            case .late: $0.answerUse = "late"
            }
            $0.modelMilliseconds = modelMilliseconds
        }
    }

    func finish(text: String, beforeSpelling: String) {
        guard terminal == nil else { return }
        let elapsed = dictationLogMilliseconds(from: stopped, to: clock())
        update {
            $0.finalText = DictationLogText(text)
            $0.secondSpellingChanged = beforeSpelling != text
            $0.pipelineChanged = raw.map { $0 != text }
            $0.stopToFinalMilliseconds = elapsed
        }
        finishIfOpen(.finished)
    }

    func failASR(_ error: any Error, milliseconds: Int64) {
        guard terminal == nil else { return }
        update {
            $0.asrFailure = DictationLogASRFailure.classify(error)
            // Type name only, not CustomStringConvertible / localizedDescription / associated values.
            if $0.asrFailure == .other { $0.asrErrorType = String(String(reflecting: type(of: error)).prefix(200)) }
            $0.asrMilliseconds = milliseconds
        }
        finishIfOpen(.asrFailed)
    }

    func finishIfOpen(_ status: DictationLogStatus) {
        guard terminal == nil, status != .transcribing else { return }
        terminal = status
        raw = nil
        update { $0.status = status }
    }
}
