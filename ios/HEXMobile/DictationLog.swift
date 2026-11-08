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
    // Optional additions keep schema-1 history readable; nil means not recorded, never off.
    var vocabularyEnabled: Bool?
    var upstreamCleanupEnabled: Bool?
    var hexPlusCleanupEnabled: Bool?
    var vocabularySnapshot: DictationLogText?

    @MainActor
    static func capture(keyboardJob: Bool, copyToPasteboard: Bool, style: DictationStyle,
                        engine: String, language: String, duration: TimeInterval,
                        loudestAverage: Float?, cleanupPath: DictationLogCleanupPath,
                        vocabularyCount: Int, vocabularyEnabled: Bool? = nil,
                        upstreamCleanupEnabled: Bool? = nil, hexPlusCleanupEnabled: Bool? = nil,
                        vocabularyTerms: [String]? = nil) -> Self {
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
        context.vocabularyEnabled = vocabularyEnabled
        context.upstreamCleanupEnabled = upstreamCleanupEnabled
        context.hexPlusCleanupEnabled = hexPlusCleanupEnabled
        context.vocabularySnapshot = vocabularyTerms.map {
            DictationLogText($0.prefix(100).map { String(reflecting: $0) }.joined(separator: ", "))
        }
        return context
    }
}

struct DictationLogReplacement: Codable, Equatable, Sendable {
    var before: DictationLogText
    var after: DictationLogText
    var term: DictationLogText

    mutating func recap() {
        before = before.recapped()
        after = after.recapped()
        term = term.recapped()
    }
}

struct DictationLogSpellingPass: Codable, Equatable, Sendable {
    static let maximumReplacements = 20
    var changes: [DictationLogReplacement] = []
    var totalChanges = 0

    mutating func record(before: String, after: String, term: String) {
        totalChanges += 1
        guard changes.count < Self.maximumReplacements else { return }
        changes.append(DictationLogReplacement(before: DictationLogText(before),
            after: DictationLogText(after), term: DictationLogText(term)))
    }

    mutating func recap() {
        changes = Array(changes.prefix(Self.maximumReplacements))
        for index in changes.indices { changes[index].recap() }
        totalChanges = max(totalChanges, changes.count)
    }
}

struct DictationLogEntry: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var schemaVersion = DictationLogDocument.version
    var context: DictationLogContext
    var revision: Int? = 1
    var rating: String?
    var issues: [String]?
    var ratingOrder: DictationFeedbackOrder?
    var referenceOrder: DictationFeedbackOrder?
    var status: DictationLogStatus = .transcribing
    var asrFailure: DictationLogASRFailure?
    var asrErrorType: String?
    var recognized: DictationLogText?
    var aiInput: DictationLogText?
    var aiAnswer: DictationLogText?
    var finalText: DictationLogText?
    // Optional schema-1 additions: nil is missing evidence, never inferred unchanged.
    var cleanupOutput: DictationLogText?
    var formattedText: DictationLogText?
    var expectedText: DictationLogText?
    var feedbackNote: DictationLogText?
    var upstreamReason: String?
    var answerUse: String?
    var cleanupOutcome: String?
    var cleanupSummary: String?
    var cleanupChanged: Bool?
    var pipelineChanged: Bool?
    var upstreamOutcome: String?
    var firstSpellingChanged = false
    var secondSpellingChanged = false
    var firstSpellingPass: DictationLogSpellingPass?
    var secondSpellingPass: DictationLogSpellingPass?
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
        cleanupOutput = cleanupOutput?.recapped()
        formattedText = formattedText?.recapped()
        expectedText = expectedText?.recapped()
        feedbackNote = feedbackNote?.recapped()
        context.vocabularySnapshot = context.vocabularySnapshot?.recapped()
        firstSpellingPass?.recap()
        secondSpellingPass?.recap()
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
    static let shared = DictationLogStore(storage: DictationLogStorage(url: URL.applicationSupportDirectory
        .appendingPathComponent("HexPlus", isDirectory: true).appendingPathComponent("dictation-log.json")))
    static let maximumEntries = 50 // full-entry cache, NOT archive retention
    private(set) var entries: [DictationLogEntry] = []
    private(set) var metadata: [DictationLogMetadata] = []
    private(set) var epoch: UInt64 = 0
    private var storageGeneration: UInt64 = 0
    private(set) var archiveID = UUID()
    private(set) var isEnabled: Bool
    private(set) var isLoading = true
    private(set) var storageProblem: String?
    private(set) var exporting = false
    private(set) var exportURL: URL?
    private var active = Set<UUID>()
    private var pinned: UUID?
    private var deleted = Set<UUID>()
    private var dirty: [UUID: DictationLogEntry] = [:]
    private let settings: HexPlusSettings
    let storage: DictationLogStorage
    private static let problem = "Some dictation log files could not be read, saved or deleted. Originals are preserved when possible. Retry; dictation still works."

    init(storage: DictationLogStorage, settings: HexPlusSettings = HexPlusSettings()) {
        self.storage = storage; self.settings = settings; isEnabled = settings.dictationLog
        reload()
    }
    func reload() {
        let generation = storageGeneration
        isLoading = true
        storage.load { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self, self.storageGeneration == generation else { return }
                self.archiveID = result.archiveID
                let local = Set(self.metadata.map(\.id)).union(self.deleted)
                self.metadata += result.metadata.filter { !local.contains($0.id) }
                self.metadata.sort { $0.date > $1.date }
                self.isLoading = false
                if result.problem { self.storageProblem = Self.problem }
                self.loadRecent()
            }
        }
    }
    func token() -> DictationLogToken { DictationLogToken(enabled: isEnabled, epoch: epoch) }
    func begin(token: DictationLogToken, context: DictationLogContext,
               stoppedAt: ContinuousClock.Instant? = nil,
               clock: @escaping @MainActor () -> ContinuousClock.Instant = { .now }) -> DictationLogRecording? {
        guard token.enabled, isEnabled, token.epoch == epoch else { return nil }
        let entry = DictationLogEntry(context: context)
        active.insert(entry.id); put(entry)
        return DictationLogRecording(entryID: entry.id, epoch: epoch, store: self, stoppedAt: stoppedAt, clock: clock)
    }
    func setEnabled(_ enabled: Bool) {
        settings.dictationLog = enabled
        guard isEnabled != enabled else { return }
        // Deliberate retention exception: OFF stops collection, it does not delete history.
        // Finalize before fencing callbacks so a persisted capture never stays transcribing.
        for var entry in entries where entry.status == .transcribing {
            entry.status = .interrupted; entry.revision = (entry.revision ?? 1) + 1; put(entry)
        }
        isEnabled = enabled; epoch &+= 1; active = []
    }
    func clear() {
        epoch &+= 1; storageGeneration &+= 1
        let generation = storageGeneration; let identity = UUID()
        exportURL = nil; exporting = false; active = []; pinned = nil
        // Keep visible evidence on failure. Fresh post-clear captures are separate and survive.
        let oldIDs = Set(metadata.map(\.id))
        deleted.formUnion(oldIDs)
        storage.clear(archiveID: identity) { [weak self] success in
            Task { @MainActor [weak self] in
                guard let self, self.storageGeneration == generation else { return }
                if success {
                    self.archiveID = identity
                    self.entries.removeAll { oldIDs.contains($0.id) }
                    self.metadata.removeAll { oldIDs.contains($0.id) }
                    for id in oldIDs { self.dirty[id] = nil }
                    self.isLoading = false; self.storageProblem = nil
                } else {
                    self.deleted.subtract(oldIDs)
                    self.storageProblem = Self.problem
                    self.reload()
                }
            }
        }
    }
    func delete(_ id: UUID) {
        deleted.insert(id); exportURL = nil
        let generation = storageGeneration
        storage.delete(id) { [weak self] success in
            Task { @MainActor [weak self] in
                guard let self, self.storageGeneration == generation else { return }
                if success {
                    self.entries.removeAll { $0.id == id }; self.metadata.removeAll { $0.id == id }
                    self.dirty[id] = nil; self.active.remove(id)
                } else { self.storageProblem = Self.problem }
            }
        }
    }
    func entry(_ id: UUID) -> DictationLogEntry? { entries.first { $0.id == id } }
    func loadEntry(_ id: UUID, pin: Bool = false, then: (@MainActor (DictationLogEntry) -> Void)? = nil) {
        if pin { pinned = id }
        guard !deleted.contains(id) else { return }
        if let entry = entry(id) { then?(entry); return }
        let generation = storageGeneration
        storage.read(id) { [weak self] loaded in
            Task { @MainActor [weak self] in
                guard let self, self.storageGeneration == generation, !self.deleted.contains(id), let loaded else { return }
                // New mutations always win over old asynchronous reads.
                let value = self.entry(id) ?? loaded
                if self.entry(id) == nil { self.entries.append(value); self.trimCache() }
                then?(value)
            }
        }
    }
    func loadRecent() { for row in metadata.prefix(Self.maximumEntries) { loadEntry(row.id) } }
    func saveFeedback(for id: UUID, expectedText: String, note: String) {
        guard expectedText.utf8.count <= 4_000, note.utf8.count <= 4_000 else { return }
        let order = DictationFeedbackOrder.app()
        loadEntry(id) { [weak self] source in
            guard let self else { return }; var entry = source
            if let previous = entry.referenceOrder, order <= previous { return }
            entry.expectedText = expectedText.isEmpty ? nil : DictationLogText(expectedText)
            entry.feedbackNote = note.isEmpty ? nil : DictationLogText(note)
            entry.referenceOrder = order; entry.revision = (entry.revision ?? 1) + 1; self.put(entry)
        }
    }
    func rate(_ id: UUID, rating: String, issues: [String]? = nil,
              order: DictationFeedbackOrder = .app()) {
        loadEntry(id) { [weak self] source in
            guard let self else { return }; var entry = source
            if let previous = entry.ratingOrder, order <= previous { return }
            entry.rating = rating
            // Rating changes never silently erase categories, notes or reference.
            if let issues { entry.issues = issues }
            entry.ratingOrder = order; entry.revision = (entry.revision ?? 1) + 1; self.put(entry)
        }
    }
    fileprivate func update(_ id: UUID, epoch: UInt64, _ mutate: (inout DictationLogEntry) -> Void) {
        guard isEnabled, self.epoch == epoch, !deleted.contains(id), var entry = entry(id) else { return }
        mutate(&entry); entry.revision = (entry.revision ?? 1) + 1
        put(entry)
    }
    fileprivate func releaseRecording(_ id: UUID) { active.remove(id); trimCache() }
    private func trimCache() {
        let protected = active.union(dirty.keys).union(pinned.map { [$0] } ?? [])
        var count = 0
        entries = entries.sorted { $0.context.createdAt > $1.context.createdAt }.filter {
            if protected.contains($0.id) { return true }
            count += 1; return count <= Self.maximumEntries
        }
    }
    private func put(_ entry: DictationLogEntry) {
        entries.removeAll { $0.id == entry.id }; entries.insert(entry, at: 0)
        let bytes = metadata.first { $0.id == entry.id }?.bytes ?? 0
        metadata.removeAll { $0.id == entry.id }
        metadata.append(DictationLogMetadata(entry, bytes: max(bytes, (try? JSONEncoder().encode(entry).count) ?? 0)))
        metadata.sort { $0.date > $1.date }
        dirty[entry.id] = entry; trimCache()
        let generation = storageGeneration
        storage.save(entry) { [weak self] success in
            Task { @MainActor [weak self] in
                guard let self, self.storageGeneration == generation else { return }
                if success, self.dirty[entry.id]?.revision == entry.revision { self.dirty[entry.id] = nil }
                if !success { self.storageProblem = Self.problem }
                self.trimCache()
            }
        }
    }
    func retry() { for entry in dirty.values { put(entry) }; reload() }
    func releaseJSON(_ url: URL) {
        storage.removeExport(url)
        if exportURL == url { exportURL = nil }
    }
    func prepareJSON(ids: [UUID]? = nil) {
        guard !exporting else { return }
        if let exportURL { storage.removeExport(exportURL) }
        exporting = true; exportURL = nil; let generation = storageGeneration
        storage.export(ids: ids, build: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown") { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self, self.storageGeneration == generation else {
                    if case .success(let url) = result { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
                    return
                }
                self.exporting = false
                switch result {
                case .success(let url): self.exportURL = url
                case .failure: self.storageProblem = "JSON could not be prepared. Retry. No file was shared."
                }
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

    deinit {
        let id = entryID
        let owner = store
        Task { @MainActor [weak owner] in owner?.releaseRecording(id) }
    }

    private func update(_ mutate: (inout DictationLogEntry) -> Void) {
        store?.update(entryID, epoch: epoch, mutate)
    }

    func recognized(_ text: String, spelled: String, asrMilliseconds: Int64,
                    spellingPass: DictationLogSpellingPass? = nil) {
        guard terminal == nil else { return }
        raw = text
        update {
            $0.recognized = DictationLogText(text)
            $0.aiInput = text == spelled ? nil : DictationLogText(spelled)
            $0.firstSpellingChanged = text != spelled
            $0.firstSpellingPass = spellingPass
            $0.asrMilliseconds = asrMilliseconds
        }
    }

    func upstreamResult(_ result: String?, input: String, reason: String? = nil) {
        guard terminal == nil else { return }
        update {
            $0.upstreamOutcome = result.map { $0 == input ? "unchanged" : "changed" } ?? "no result"
            $0.upstreamReason = reason
        }
    }

    func processingStages(cleanupOutput: String, formattedText: String) {
        guard terminal == nil else { return }
        update {
            $0.cleanupOutput = DictationLogText(cleanupOutput)
            $0.formattedText = DictationLogText(formattedText)
        }
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

    func finish(text: String, beforeSpelling: String, spellingPass: DictationLogSpellingPass? = nil) {
        guard terminal == nil else { return }
        let elapsed = dictationLogMilliseconds(from: stopped, to: clock())
        update {
            $0.finalText = DictationLogText(text)
            $0.secondSpellingChanged = beforeSpelling != text
            $0.secondSpellingPass = spellingPass
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
