import AVFAudio
import Foundation
import Observation
import SwiftUI
import UIKit

@MainActor
@Observable
final class DictationController {
    static let shared = DictationController(
        autoPrepareOnInit: ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
        cleaner: AppleIntelligenceCleaner(),
        cleanup: TranscriptCleanupProduction.dependencies(),
        dictationLog: .shared
    )

    private static let minCaptureDuration: TimeInterval = 0.30
    private static let maxCaptureDuration: TimeInterval = 60.0
    private static let resultDeliveryTTL: TimeInterval = 30.0

    enum Phase: Equatable {
        case modelRequired
        case preparingModel
        case ready
        case requestingPermission
        case recording
        case transcribing
        case failed(String)

        var isBusy: Bool {
            switch self {
            case .preparingModel, .requestingPermission, .transcribing:
                true
            default:
                false
            }
        }
    }

    enum AutoReturnState: Equatable {
        case idle
        case attempting
        case succeeded
        case swipeFallback
    }

    private struct ActiveCaptureSession {
        let generation: UInt64
        let capture: any ActiveAudioCapture
        let startedAt: TimeInterval
        let keyboardJobID: String?
        let style: DictationStyle
        let usesCleanup: Bool
        let vocabularyTerms: [String]
        /// Every saved term, frozen for the log even while the experiment is off.
        let savedVocabularyTerms: [String]
        let vocabularyEnabled: Bool
        let typrCleanupEnabled: Bool
        let copyToPasteboard: Bool
        let cleanupJob: CleanupJob?
        let cleanupSkipReason: CleanupSkipReason?
        let logToken: DictationLogToken?
        let logCleanupPath: DictationLogCleanupPath
        /// Dictation language and data-only preceding text for Typr cleanup, frozen at start.
        let cleanupContext: CleanupContext
    }

    private struct PendingKeyboardHandoff {
        let jobID: String?
        let style: DictationStyle
        let requestedAt: TimeInterval
        let attemptAutoReturn: Bool
    }

    private var transcriber: any LocalTranscribing
    private let transcriberFactory: () async -> any LocalTranscribing
    private let cleaner: (any TranscriptCleaning)?
    private let cleanupSettings: AppleIntelligenceCleanupSettings
    private let customVocabularySettings: CustomVocabularySettings
    private let audio: any AudioManaging
    private let keyboardBridge: KeyboardBridge
    private let fileManager: FileManager
    private let now: () -> TimeInterval
    private let liveActivity = LiveActivityCoordinator()
    private let hostReturner: HostReturner
    /// The app the current cold-start handoff came from, by bundle ID; nil when the keyboard could not name it.
    private var returnHost: String?

    private let cleanup: TranscriptCleanupDependencies?
    private let cleanupCoordinator = CleanupCoordinator()
    /// This session's recent results, in memory only, as cleanup context when the keyboard sent none.
    private let cleanupHistory = CleanupContextHistory()
    private let languageSettings: TyprSettings
    private var pendingCleanupJob: CleanupJob?
    private var cleanupHeartbeat: Task<Void, Never>?
    private let dictationLog: DictationLogStore?
    private var transcribingLog: DictationLogRecording?
    @ObservationIgnored private var loudestAverageDBFS: Float?

    private func endCleanupJob() {
        if let job = pendingCleanupJob {
            cleanupCoordinator.cancel(job.id)
            job.finish()
        }
        pendingCleanupJob = nil
        cleanupHeartbeat?.cancel()
        cleanupHeartbeat = nil
    }

    private var jobGeneration: UInt64 = 0
    private var modelPrepGeneration: UInt64 = 0
    private var activeCapture: ActiveCaptureSession?
    private var meterTask: Task<Void, Never>?
    private var transcriptionTask: Task<Void, Never>?
    private var keyboardSessionTask: Task<Void, Never>?
    private var autoReturnFallbackTask: Task<Void, Never>?

    private var lastKeyboardCommandID: String?
    private var lastHandledLaunchJobID: String?
    private var activeKeyboardJobID: String?
    private var keyboardResultID: String?
    private var keyboardFeedbackOffer: DictationFeedbackOffer?
    private var keyboardResultExpiresAt: TimeInterval?
    private var keyboardResult: String?
    private var keyboardMessage: String?
    private var pendingHandoff: PendingKeyboardHandoff?
    private var keyboardSessionExpiresAt: TimeInterval = 0
    private var suspendedWarmSessionOnInterruption = false

    private(set) var phase = Phase.modelRequired
    private(set) var isModelReady = false
    private(set) var transcript = ""
    private(set) var lastLoggedTranscriptID: UUID?
    @ObservationIgnored private(set) var audioLevel: Float = 0
    @ObservationIgnored private(set) var loudnessDB: Float = -120
    @ObservationIgnored private var rawRecordingDuration: TimeInterval = 0
    private(set) var recordingWholeSeconds: Int = 0
    private(set) var recordingDuration: TimeInterval {
        get { rawRecordingDuration }
        set {
            rawRecordingDuration = newValue
            let whole = max(0, Int(newValue))
            if recordingWholeSeconds != whole {
                recordingWholeSeconds = whole
            }
        }
    }
    private(set) var copied = false
    private(set) var keyboardSessionEnabled = false
    @ObservationIgnored private var rawKeyboardSessionRemaining: TimeInterval = 0
    private(set) var keyboardSessionDisplayRemaining = "0:00"
    private(set) var keyboardSessionRemaining: TimeInterval {
        get { rawKeyboardSessionRemaining }
        set {
            rawKeyboardSessionRemaining = newValue
            let formatted = TyprTheme.formatRemaining(newValue)
            if keyboardSessionDisplayRemaining != formatted {
                keyboardSessionDisplayRemaining = formatted
            }
        }
    }
    @ObservationIgnored private var lastPublishedSnapshotSignature: String?
    @ObservationIgnored private var lastPublishedSnapshotAt: TimeInterval = -100
    private(set) var warmDuration: WarmSessionDuration
    private(set) var style: DictationStyle
    private(set) var allowBluetoothMic: Bool
    private(set) var autoReturnState: AutoReturnState = .idle
    private(set) var handoffNotice: String?
    private(set) var engineName = "Local speech"
    private(set) var transcriptionLanguage = "English"
    /// The chosen dictation language (Typr settings); Automatic keeps the previous behavior.
    private(set) var dictationLanguage: DictationLanguage
    private(set) var modelPreparation = ModelPreparationProgress(
        fractionCompleted: 0,
        detail: "Checking model files"
    )

    init(
        audio: (any AudioManaging)? = nil,
        keyboardBridge: KeyboardBridge? = nil,
        transcriber: (any LocalTranscribing)? = nil,
        transcriberFactory: (() async -> any LocalTranscribing)? = nil,
        fileManager: FileManager = .default,
        now: @escaping () -> TimeInterval = { Date().timeIntervalSince1970 },
        autoPrepareOnInit: Bool = true,
        hostReturner: HostReturner? = nil,
        cleaner: (any TranscriptCleaning)? = nil,
        cleanupSettings: AppleIntelligenceCleanupSettings = AppleIntelligenceCleanupSettings(),
        customVocabularySettings: CustomVocabularySettings = CustomVocabularySettings(),
        cleanup: TranscriptCleanupDependencies? = nil,
        dictationLog: DictationLogStore? = nil,
        languageSettings: TyprSettings = TyprSettings()
    ) {
        let resolvedBridge = keyboardBridge ?? KeyboardBridge()
        let resolvedAudio = audio ?? SystemAudioManager()
        let initialTranscriber = transcriber ?? ParakeetTranscriber()

        self.cleanup = cleanup
        self.dictationLog = dictationLog
        self.languageSettings = languageSettings
        self.dictationLanguage = languageSettings.dictationLanguage
        self.audio = resolvedAudio
        self.keyboardBridge = resolvedBridge
        self.transcriber = initialTranscriber
        self.transcriberFactory = transcriberFactory ?? Self.defaultTranscriber
        self.cleaner = cleaner
        self.cleanupSettings = cleanupSettings
        self.customVocabularySettings = customVocabularySettings
        self.fileManager = fileManager
        self.now = now
        self.warmDuration = resolvedBridge.warmDuration
        self.style = resolvedBridge.style
        self.allowBluetoothMic = resolvedBridge.allowBluetoothMic
        self.hostReturner = hostReturner ?? .live

        let hasCachedModel = ParakeetTranscriber.hasCachedModel
        resolvedBridge.publish(.offline)
        resolvedBridge.setModelInstalled(hasCachedModel)

        wireAudioCallbacks()
        wireSystemIntentBus()

        if Self.applyLaunchFixtureIfPresent(to: self) {
            return
        }

        if autoPrepareOnInit {
            if hasCachedModel {
                engineName = "Parakeet V2"
                prepareModel()
            } else if #available(iOS 26.0, *), AppleSpeechTranscriber.isAvailable {
                let language = dictationLanguage
                Task { [weak self] in
                    guard let self else { return }
                    if await AppleSpeechTranscriber.preferredLocale(language: language) != nil {
                        self.engineName = "Apple Speech"
                        self.prepareModel()
                    } else {
                        self.engineName = "Parakeet V2"
                    }
                }
            }
        }
    }

    var isRecording: Bool {
        phase == .recording
    }

    var primaryTitle: String {
        switch phase {
        case .modelRequired, .failed:
            "Prepare \(engineName)"
        case .preparingModel:
            "Preparing \(engineName)"
        case .ready:
            "Start dictation"
        case .requestingPermission:
            "Checking microphone"
        case .recording:
            "Finish"
        case .transcribing:
            "Transcribing…"
        }
    }

    // MARK: - Settings

    func setWarmDuration(_ duration: WarmSessionDuration) {
        warmDuration = duration
        keyboardBridge.warmDuration = duration

        if keyboardSessionEnabled {
            if let seconds = duration.seconds {
                keyboardSessionExpiresAt = now() + seconds
                keyboardSessionRemaining = seconds
                publishKeyboardSnapshot()
            } else if phase == .ready {
                endWarmSession()
            }
        }
    }

    /// Used by the settings segmented control: picking a duration warms immediately; picking Off ends it.
    func selectWarmDuration(_ duration: WarmSessionDuration) {
        setWarmDuration(duration)
        if duration == .off {
            if keyboardSessionEnabled {
                endWarmSession()
            }
        } else if !keyboardSessionEnabled {
            requestWarmSession(attemptAutoReturn: false)
        }
    }

    func setStyle(_ newStyle: DictationStyle) {
        style = newStyle
        keyboardBridge.style = newStyle
    }

    /// The language picker: stored for the next recording's cleanup. Apple Speech holds one locale,
    /// so an idle, prepared Apple Speech engine is prepared again for the new language; otherwise the
    /// next preparation (relaunch, retry) uses it.
    func setDictationLanguage(_ language: DictationLanguage) {
        guard language != dictationLanguage else { return }
        dictationLanguage = language
        languageSettings.dictationLanguage = language
        if isModelReady, phase == .ready, activeCapture == nil, transcriber.displayName == "Apple Speech" {
            prepareModel()
        }
    }

    func setAllowBluetoothMic(_ allow: Bool) {
        guard allowBluetoothMic != allow else { return }
        allowBluetoothMic = allow
        keyboardBridge.allowBluetoothMic = allow
        if keyboardSessionEnabled, phase == .ready {
            try? audio.startKeepalive(allowBluetooth: allow)
        }
    }

    // MARK: - Standalone & System Actions

    func performPrimaryAction() {
        switch phase {
        case .modelRequired, .failed:
            prepareModel()
        case .ready:
            startRecording(copyToPasteboard: false)
        case .recording:
            finishRecording()
        case .preparingModel, .requestingPermission, .transcribing:
            break
        }
    }

    func cancelCurrentJob() {
        transcribingLog?.finishIfOpen(.cancelled)
        transcribingLog = nil
        endCleanupJob()
        jobGeneration &+= 1
        transcriptionTask?.cancel()
        transcriptionTask = nil
        liveActivity.endImmediately()

        if let session = activeCapture {
            activeCapture = nil
            stopMetering()
            session.capture.stop()
            try? fileManager.removeItem(at: session.capture.url)
        }

        if activeKeyboardJobID != nil {
            keyboardMessage = nil
        }
        activeKeyboardJobID = nil
        audioLevel = 0
        loudnessDB = -120
        recordingDuration = 0
        if phase == .recording || phase == .transcribing || phase == .requestingPermission {
            phase = .ready
        }
        restoreAudioAfterCapture()
        publishKeyboardSnapshot()
    }

    func clearTranscript() {
        transcript = ""
        copied = false
    }

    func copyTranscript() {
        guard !transcript.isEmpty else { return }
        UIPasteboard.general.string = transcript
        copied = true
    }

    func toggleWarmSession() {
        if keyboardSessionEnabled {
            endWarmSession()
        } else {
            if warmDuration == .off {
                setWarmDuration(.fifteenMinutes)
            }
            requestWarmSession(attemptAutoReturn: false)
        }
    }

    func endWarmSession(message: String? = nil) {
        keyboardSessionTask?.cancel()
        keyboardSessionTask = nil
        pendingHandoff = nil
        suspendedWarmSessionOnInterruption = false

        // Cancel an unaccepted in-progress recording, but preserve any already-accepted transcription!
        if let session = activeCapture {
            endCleanupJob()
            jobGeneration &+= 1
            activeCapture = nil
            stopMetering()
            session.capture.stop()
            try? fileManager.removeItem(at: session.capture.url)
            activeKeyboardJobID = nil
            audioLevel = 0
            loudnessDB = -120
            recordingDuration = 0
            liveActivity.endImmediately()
            if phase == .recording {
                phase = .ready
            }
        }

        keyboardSessionEnabled = false
        keyboardSessionRemaining = 0
        keyboardSessionExpiresAt = 0
        keyboardMessage = message

        if phase != .recording {
            audio.deactivateSession()
        }

        publishKeyboardSnapshot()
    }

    func noteSceneDidEnterBackground() {
        autoReturnFallbackTask?.cancel()
        autoReturnFallbackTask = nil
        if case .attempting = autoReturnState {
            autoReturnState = .succeeded
        }
    }

    // MARK: - Keyboard Launch & Auto-Return

    func handleKeyboardLaunch(_ request: KeyboardLaunchRequest) {
        if case .setup = request {
            return
        }
        autoReturnFallbackTask?.cancel()
        autoReturnState = .idle
        handoffNotice = nil
        returnHost = request.host

        let currentTime = now()
        if request.isHandoffExpired(at: currentTime) {
            handoffNotice = "Timed out"
            pendingHandoff = PendingKeyboardHandoff(
                jobID: nil,
                style: style,
                requestedAt: currentTime,
                attemptAutoReturn: false
            )
            fulfillPendingHandoffOrPrepare()
            return
        }

        switch request {
        case .setup:
            break

        case .startSession:
            pendingHandoff = PendingKeyboardHandoff(
                jobID: nil,
                style: style,
                requestedAt: currentTime,
                attemptAutoReturn: true
            )
            fulfillPendingHandoffOrPrepare()

        case .startRecording(let jobID, _, let requestedStyle, _):
            guard !jobID.isEmpty, jobID != lastHandledLaunchJobID else { return }
            lastHandledLaunchJobID = jobID
            if let requestedStyle {
                setStyle(requestedStyle)
            }
            pendingHandoff = PendingKeyboardHandoff(
                jobID: jobID,
                style: requestedStyle ?? style,
                requestedAt: currentTime,
                attemptAutoReturn: true
            )
            fulfillPendingHandoffOrPrepare()
        }
    }

    private func fulfillPendingHandoffOrPrepare() {
        guard let handoff = pendingHandoff else { return }

        if now() - handoff.requestedAt > KeyboardLaunchRequest.handoffWindow {
            handoffNotice = "Timed out"
            pendingHandoff = PendingKeyboardHandoff(
                jobID: nil,
                style: handoff.style,
                requestedAt: now(),
                attemptAutoReturn: false
            )
        }

        switch phase {
        case .modelRequired, .failed:
            prepareModel()
        case .ready:
            activateWarmSessionAndRunHandoff()
        case .preparingModel, .requestingPermission, .recording, .transcribing:
            break
        }
    }

    private func requestWarmSession(attemptAutoReturn: Bool) {
        pendingHandoff = PendingKeyboardHandoff(
            jobID: nil,
            style: style,
            requestedAt: now(),
            attemptAutoReturn: attemptAutoReturn
        )
        fulfillPendingHandoffOrPrepare()
    }

    private func activateWarmSessionAndRunHandoff() {
        guard phase == .ready else { return }
        let handoff = pendingHandoff
        pendingHandoff = nil

        // If a one-shot recording was requested (`warmDuration == .off` and a jobID is present),
        // go straight into recording and release the mic as soon as capture finishes.
        if warmDuration == .off, let jobID = handoff?.jobID {
            let expired = handoff.map { now() - $0.requestedAt > KeyboardLaunchRequest.handoffWindow } ?? false
            if !expired {
                startRecording(
                    keyboardJobID: jobID,
                    styleOverride: handoff?.style,
                    copyToPasteboard: false,
                    attemptAutoReturnOnStart: handoff?.attemptAutoReturn ?? false
                )
            } else {
                handoffNotice = "Timed out"
                autoReturnState = .swipeFallback
            }
            return
        }

        if keyboardSessionEnabled, audio.isKeepaliveRunning {
            refreshWarmExpiry()
            if let jobID = handoff?.jobID {
                let expired = handoff.map { now() - $0.requestedAt > KeyboardLaunchRequest.handoffWindow } ?? false
                if !expired {
                    startRecording(
                        keyboardJobID: jobID,
                        styleOverride: handoff?.style,
                        copyToPasteboard: false,
                        attemptAutoReturnOnStart: handoff?.attemptAutoReturn ?? false
                    )
                    return
                } else {
                    handoffNotice = "Timed out"
                }
            }
            maybeAutoReturnAfterActivation(allowed: handoff?.attemptAutoReturn ?? false)
            return
        }

        jobGeneration &+= 1
        let requestGen = jobGeneration
        phase = .requestingPermission
        keyboardMessage = nil

        Task {
            let granted = await audio.requestPermission()
            guard self.jobGeneration == requestGen else { return }
            guard granted else {
                phase = .failed("Microphone access is off. Allow it in Settings to dictate.")
                publishKeyboardSnapshot()
                return
            }

            // If we also have a fresh recording job, begin capture directly so we don't bounce keepalive -> recorder!
            if let jobID = handoff?.jobID,
               let requestedAt = handoff?.requestedAt,
               self.now() - requestedAt <= KeyboardLaunchRequest.handoffWindow {
                self.enableWarmSessionBookkeeping()
                self.phase = .ready
                self.startKeyboardSessionLoop()
                self.startRecording(
                    keyboardJobID: jobID,
                    styleOverride: handoff?.style,
                    copyToPasteboard: false,
                    attemptAutoReturnOnStart: handoff?.attemptAutoReturn ?? false
                )
                return
            }

            if let jobID = handoff?.jobID, !jobID.isEmpty {
                self.handoffNotice = "Timed out"
            }

            do {
                try audio.startKeepalive(allowBluetooth: allowBluetoothMic)
                enableWarmSessionBookkeeping()
                phase = .ready
                startKeyboardSessionLoop()
                publishKeyboardSnapshot()
                maybeAutoReturnAfterActivation(allowed: handoff?.attemptAutoReturn ?? false)
            } catch {
                audio.deactivateSession()
                phase = .failed(error.localizedDescription)
                publishKeyboardSnapshot()
            }
        }
    }

    private func enableWarmSessionBookkeeping() {
        let seconds = warmDuration.seconds ?? (15 * 60)
        keyboardSessionEnabled = true
        keyboardSessionExpiresAt = now() + seconds
        keyboardSessionRemaining = seconds
    }

    private func refreshWarmExpiry() {
        guard keyboardSessionEnabled, let seconds = warmDuration.seconds else { return }
        keyboardSessionExpiresAt = now() + seconds
        keyboardSessionRemaining = seconds
    }

    /// Back to the app the dictation came from, else the swipe-back cue.
    /// A field inside Typr itself needs no return.
    private func maybeAutoReturnAfterActivation(allowed: Bool) {
        guard allowed else { return }
        guard let host = returnHost else {
            autoReturnState = .swipeFallback
            return
        }
        guard host != HostReturnCatalog.typrBundleID else { return }
        triggerAutoReturn(to: host)
    }

    private func triggerAutoReturn(to host: String) {
        autoReturnFallbackTask?.cancel()
        autoReturnState = .attempting
        let returner = hostReturner

        Task {
            let opened = await returner.open(host)
            guard case .attempting = self.autoReturnState else { return }
            if !opened {
                self.autoReturnState = .swipeFallback
                return
            }
            self.autoReturnFallbackTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(950))
                guard !Task.isCancelled, let self else { return }
                if case .attempting = self.autoReturnState {
                    self.autoReturnState = .swipeFallback
                }
            }
        }
    }

    // MARK: - Model Preparation

    func prepareModel() {
        modelPrepGeneration &+= 1
        let prepGen = modelPrepGeneration
        phase = .preparingModel
        copied = false
        modelPreparation = ModelPreparationProgress(
            fractionCompleted: 0,
            detail: "Checking model files"
        )

        Task {
            do {
                let candidate = await transcriberFactory()
                guard self.modelPrepGeneration == prepGen else { return }
                engineName = candidate.displayName
                try await candidate.prepare { [weak self] progress in
                    Task { @MainActor [weak self] in
                        guard let self, self.modelPrepGeneration == prepGen else { return }
                        self.modelPreparation = progress
                    }
                }
                guard self.modelPrepGeneration == prepGen else { return }
                self.transcriber = candidate
                self.transcriptionLanguage = await candidate.languageName
                self.keyboardBridge.setModelInstalled(true)
                self.isModelReady = true
                self.phase = .ready
                self.publishKeyboardSnapshot()
                if self.pendingHandoff != nil {
                    self.activateWarmSessionAndRunHandoff()
                }
            } catch {
                guard self.modelPrepGeneration == prepGen else { return }
                self.keyboardBridge.setModelInstalled(ParakeetTranscriber.hasCachedModel)
                self.pendingHandoff = nil
                self.phase = .failed(error.localizedDescription)
                self.publishKeyboardSnapshot()
            }
        }
    }

    private static func defaultTranscriber() async -> any LocalTranscribing {
        let language = TyprSettings().dictationLanguage
        if #available(iOS 26.0, *),
           AppleSpeechTranscriber.isAvailable,
           let locale = await AppleSpeechTranscriber.preferredLocale(language: language) {
            return AppleSpeechTranscriber(locale: locale)
        }
        return ParakeetTranscriber()
    }

    // MARK: - Capture & Generation-Scoped Transcription

    func startRecording(
        keyboardJobID: String? = nil,
        styleOverride: DictationStyle? = nil,
        copyToPasteboard: Bool = false,
        attemptAutoReturnOnStart: Bool = false,
        keyboardContext: String? = nil
    ) {
        guard activeCapture == nil else { return }
        if let keyboardJobID, keyboardJobID == activeKeyboardJobID {
            return
        }
        activeKeyboardJobID = keyboardJobID
        if keyboardJobID != nil {
            keyboardMessage = nil
        }

        // Bumping generation invalidates any stale winding-down transcription task so it can never
        // overwrite our new capture's phase, job state, or temporary WAV file.
        jobGeneration &+= 1
        let captureGeneration = jobGeneration
        transcribingLog?.finishIfOpen(.cancelled)
        transcribingLog = nil
        transcriptionTask?.cancel()
        transcriptionTask = nil
        endCleanupJob()
        let effectiveStyle = styleOverride ?? style
        let usesCleanup = cleanupSettings.isEnabled
        let vocabularyEnabled = customVocabularySettings.isEnabled
        let savedVocabularyTerms = customVocabularySettings.terms
        let vocabularyTerms = vocabularyEnabled ? savedVocabularyTerms : []
        let enabled = cleanup?.isEnabled() == true
        let logToken = dictationLog?.token()
        let logCleanupPath: DictationLogCleanupPath = effectiveStyle == .verbatim ? .none
            : (enabled ? .typr : (usesCleanup && cleaner != nil ? .upstream : .none))
        let cleanupEnabled = enabled && effectiveStyle != .verbatim
        let disabledCleanupReason: CleanupSkipReason? = !enabled ? .off : (effectiveStyle == .verbatim ? .verbatim : nil)
        let cleanupContext = CleanupContext.make(language: languageSettings.dictationLanguage, keyboard: keyboardContext,
                                                 previousDictations: cleanupHistory.recent(at: now()))

        phase = .requestingPermission
        copied = false

        Task {
            let granted = await audio.requestPermission()
            guard self.jobGeneration == captureGeneration else { return }
            guard granted else {
                activeKeyboardJobID = nil
                let message = "Microphone access is off. Allow it in Settings."
                keyboardMessage = keyboardJobID == nil ? nil : message
                phase = .failed(message)
                publishKeyboardSnapshot()
                return
            }

            let captureURL = fileManager.temporaryDirectory
                .appendingPathComponent("typr-\(captureGeneration)-\(UUID().uuidString)")
                .appendingPathExtension("wav")

            do {
                let capture = try audio.beginCapture(
                    at: captureURL,
                    maxDuration: Self.maxCaptureDuration,
                    allowBluetooth: allowBluetoothMic
                )
                guard self.jobGeneration == captureGeneration else {
                    capture.stop()
                    try? fileManager.removeItem(at: captureURL)
                    return
                }

                let startedAt = now()
                var cleanupJob: CleanupJob?
                var cleanupSkipReason = disabledCleanupReason
                if cleanupEnabled, let cleanup {
                    if cleanup.cleaner.unavailableReason != nil {
                        cleanupSkipReason = .unavailable
                    } else if cleanupCoordinator.reservedBy != nil {
                        cleanupSkipReason = .busy
                    } else {
                        let job = CleanupJob(session: cleanup.cleaner.makeSession(), background: cleanup.background)
                        cleanupJob = job
                        pendingCleanupJob = job
                        cleanupCoordinator.prewarm(job)
                    }
                }
                activeCapture = ActiveCaptureSession(
                    generation: captureGeneration,
                    capture: capture,
                    startedAt: startedAt,
                    keyboardJobID: keyboardJobID,
                    style: effectiveStyle,
                    usesCleanup: usesCleanup,
                    vocabularyTerms: vocabularyTerms,
                    savedVocabularyTerms: savedVocabularyTerms,
                    vocabularyEnabled: vocabularyEnabled,
                    typrCleanupEnabled: enabled,
                    copyToPasteboard: copyToPasteboard,
                    cleanupJob: cleanupJob,
                    cleanupSkipReason: cleanupSkipReason,
                    logToken: logToken,
                    logCleanupPath: logCleanupPath,
                    cleanupContext: cleanupContext
                )
                refreshWarmExpiry()
                audioLevel = 0
                loudnessDB = -120
                loudestAverageDBFS = nil
                recordingDuration = 0
                phase = .recording
                liveActivity.startRecording(startedAt: Date(timeIntervalSince1970: startedAt))
                startMetering(for: captureGeneration)
                publishKeyboardSnapshot()

                if attemptAutoReturnOnStart {
                    maybeAutoReturnAfterActivation(allowed: true)
                }
            } catch {
                try? fileManager.removeItem(at: captureURL)
                activeKeyboardJobID = nil
                keyboardMessage = keyboardJobID == nil ? nil : error.localizedDescription
                phase = .failed(error.localizedDescription)
                restoreAudioAfterCapture()
                publishKeyboardSnapshot()
            }
        }
    }

    func finishRecording() {
        guard let session = activeCapture else { return }
        let stoppedAt = ContinuousClock.now
        activeCapture = nil

        stopMetering()
        let finalDuration = max(recordingDuration, session.capture.currentTime)
        session.capture.stop()
        audioLevel = 0
        loudnessDB = -120

        let captureURL = session.capture.url
        let captureGeneration = session.generation
        let keyboardJobID = session.keyboardJobID

        guard finalDuration >= Self.minCaptureDuration else {
            endCleanupJob()
            try? fileManager.removeItem(at: captureURL)
            recordingDuration = 0
            activeKeyboardJobID = nil
            keyboardMessage = nil
            phase = .ready
            liveActivity.endImmediately()
            restoreAudioAfterCapture()
            publishKeyboardSnapshot()
            return
        }

        let recording = session.logToken.flatMap { token in
            dictationLog?.begin(token: token, context: .capture(
                keyboardJob: keyboardJobID != nil, copyToPasteboard: session.copyToPasteboard,
                style: session.style, engine: transcriber.displayName, language: transcriptionLanguage,
                duration: finalDuration, loudestAverage: loudestAverageDBFS,
                cleanupPath: session.logCleanupPath, vocabularyCount: session.vocabularyTerms.count,
                vocabularyEnabled: session.vocabularyEnabled,
                upstreamCleanupEnabled: session.usesCleanup,
                typrCleanupEnabled: session.typrCleanupEnabled,
                vocabularyTerms: session.savedVocabularyTerms,
                cleanupContext: session.cleanupContext),
                stoppedAt: stoppedAt)
        }
        transcribingLog = recording
        phase = .transcribing
        if let job = session.cleanupJob {
            job.begin()
            cleanupHeartbeat = Task { [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(1)) } catch { return }
                    guard let self, self.jobGeneration == captureGeneration, self.phase == .transcribing else { return }
                    self.publishKeyboardSnapshot()
                }
            }
        }
        liveActivity.markTranscribing(startedAt: Date(timeIntervalSince1970: session.startedAt))
        restoreAudioAfterCapture()
        publishKeyboardSnapshot()

        let activeTranscriber = transcriber

        transcriptionTask?.cancel()
        transcriptionTask = Task { [weak self] in
            let asrStarted = ContinuousClock.now
            defer {
                recording?.finishIfOpen(.cancelled) // Also outside the generation fence: stale tasks terminate their own entry.
                try? FileManager.default.removeItem(at: captureURL)
                session.cleanupJob?.finish()
                if let self, self.jobGeneration == captureGeneration {
                    self.transcribingLog = nil
                    self.endCleanupJob()
                }
            }

            do {
                let rawText = try await activeTranscriber.transcribe(
                    captureURL,
                    vocabulary: session.vocabularyTerms
                )
                guard let self, self.jobGeneration == captureGeneration, !Task.isCancelled else {
                    return
                }
                // Spelling runs before optional cleanup so cleanup sees the preferred
                // words, then again after formatting because a style can lowercase a
                // term or capitalize a sentence start ("iPhone" -> "IPhone").
                let asrMilliseconds = dictationLogMilliseconds(from: asrStarted)
                var firstPass = DictationLogSpellingPass()
                let observeFirst: ((String, String, String) -> Void)? = recording == nil ? nil : { before, after, term in
                    firstPass.record(before: before, after: after, term: term)
                }
                let spelled = VocabularySpelling.apply(session.vocabularyTerms, to: rawText, onReplacement: observeFirst)
                recording?.recognized(rawText, spelled: spelled, asrMilliseconds: asrMilliseconds, spellingPass: firstPass)
                var text = spelled
                if let cleanup = self.cleanup, session.cleanupSkipReason != .off {
                    // Typr AI cleanup is on: it replaces upstream's cleanup experiment.
                    if session.cleanupSkipReason == .verbatim {
                        // Verbatim remains synchronous: no prepare, model call, lease or await.
                        self.cleanupCoordinator.recordSkip(.verbatim, dependencies: cleanup, diagnostics: recording)
                    } else {
                        text = await self.cleanupCoordinator.clean(spelled, style: session.style, job: session.cleanupJob,
                            dependencies: cleanup, skipReason: session.cleanupSkipReason,
                            vocabulary: session.vocabularyTerms, context: session.cleanupContext, diagnostics: recording)
                        guard self.jobGeneration == captureGeneration, !Task.isCancelled else { return }
                    }
                } else {
                    if let cleanup = self.cleanup {
                        // Off remains synchronous: no prepare, model call, lease or await.
                        self.cleanupCoordinator.recordSkip(.off, dependencies: cleanup, diagnostics: recording)
                    }
                    text = await self.cleanedTranscriptIfEnabled(spelled, session: session, recording: recording)
                    guard self.jobGeneration == captureGeneration, !Task.isCancelled else {
                        return
                    }
                }
                let beforeSpelling = TranscriptFormatter.format(text, style: session.style)
                recording?.processingStages(cleanupOutput: text, formattedText: beforeSpelling)
                var secondPass = DictationLogSpellingPass()
                let observeSecond: ((String, String, String) -> Void)? = recording == nil ? nil : { before, after, term in
                    secondPass.record(before: before, after: after, term: term)
                }
                let formatted = VocabularySpelling.apply(session.vocabularyTerms, to: beforeSpelling, onReplacement: observeSecond)
                recording?.finish(text: formatted, beforeSpelling: beforeSpelling, spellingPass: secondPass)
                self.cleanupHistory.record(formatted, at: self.now())
                self.recordingDuration = 0
                self.transcript = formatted
                // Exact recording correlation, never whichever archive row happens to be latest.
                self.lastLoggedTranscriptID = recording.flatMap { recording in
                    guard let entry = self.dictationLog?.entry(recording.entryID),
                          entry.status == .finished, entry.finalText?.text == DictationLogText(formatted).text else { return nil }
                    return recording.entryID
                }
                if session.copyToPasteboard && !formatted.isEmpty {
                    UIPasteboard.general.string = formatted
                    self.copied = true
                    self.liveActivity.finishCopied()
                } else {
                    self.liveActivity.endImmediately()
                }

                if keyboardJobID != nil {
                    self.keyboardResultID = UUID().uuidString
                    self.keyboardResult = formatted
                    self.keyboardResultExpiresAt = self.now() + Self.resultDeliveryTTL
                    if let recording, let resultID = self.keyboardResultID, let keyboardJobID {
                        self.keyboardFeedbackOffer = self.dictationLog?.makeKeyboardFeedbackOffer(
                            recording: recording, jobID: keyboardJobID, resultID: resultID,
                            expiresAt: Date(timeIntervalSince1970: self.now() + 600))
                    }
                    self.keyboardMessage = nil
                }
                self.activeKeyboardJobID = nil
                self.refreshWarmExpiry()
                self.phase = .ready
                self.publishKeyboardSnapshot()
            } catch {
                guard !Task.isCancelled, let self, self.jobGeneration == captureGeneration else {
                    return
                }
                recording?.failASR(error, milliseconds: dictationLogMilliseconds(from: asrStarted))
                self.recordingDuration = 0
                self.activeKeyboardJobID = nil
                self.liveActivity.endImmediately()
                self.keyboardMessage = keyboardJobID == nil ? nil : error.localizedDescription
                self.phase = .failed(error.localizedDescription)
                self.publishKeyboardSnapshot()
            }
        }
    }

    /// The cleanup experiment's one pass, before formatting. Any failure keeps the raw text.
    private func cleanedTranscriptIfEnabled(
        _ rawText: String,
        session: ActiveCaptureSession,
        recording: DictationLogRecording?
    ) async -> String {
        guard session.usesCleanup,
              session.style != .verbatim,
              !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let cleaner,
              cleaner.isAvailable else {
            if session.logCleanupPath == .upstream {
                let reason: String
                if !session.usesCleanup { reason = "disabled" }
                else if session.style == .verbatim { reason = "verbatim" }
                else if rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { reason = "empty input" }
                else if cleaner == nil { reason = "cleaner not configured" }
                else { reason = "cleaner unavailable" }
                recording?.upstreamResult(nil, input: rawText, reason: reason)
            }
            return rawText
        }
        let result = await cleaner.clean(rawText)
        if !Task.isCancelled {
            recording?.upstreamResult(result, input: rawText,
                reason: result == nil ? "cleaner returned nil; API exposes no failure reason" : nil)
        }
        return result ?? rawText
    }

    private func restoreAudioAfterCapture() {
        if keyboardSessionEnabled, let seconds = warmDuration.seconds, seconds > 0 {
            let remaining = keyboardSessionExpiresAt - now()
            if remaining <= 0 {
                keyboardSessionEnabled = false
                keyboardSessionRemaining = 0
                keyboardSessionExpiresAt = 0
                audio.deactivateSession()
                return
            }
            // An interruption stopped the input; `.interruptionEnded` resumes the session.
            guard !suspendedWarmSessionOnInterruption else { return }
            do {
                // The capture recorded from the keepalive input, so it is normally still
                // running. Restarting it here would fail in the background and end the session.
                try audio.ensureKeepalive(allowBluetooth: allowBluetoothMic)
            } catch {
                keyboardSessionEnabled = false
                keyboardSessionRemaining = 0
                keyboardSessionExpiresAt = 0
                keyboardMessage = error.localizedDescription
                audio.deactivateSession()
            }
        } else {
            keyboardSessionEnabled = false
            keyboardSessionRemaining = 0
            keyboardSessionExpiresAt = 0
            audio.deactivateSession()
        }
    }

    private func startMetering(for generation: UInt64) {
        stopMetering()
        meterTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self,
                      let session = self.activeCapture,
                      session.generation == generation else {
                    break
                }

                // Recorder readiness is a sample, not the capture's lifetime. A transient
                // false must not strand the app meter and keyboard heartbeat until Stop.
                // Completion/interruption callbacks and explicit Stop own capture teardown.
                guard session.capture.isRecording else {
                    try? await Task.sleep(for: .milliseconds(33))
                    continue
                }

                let db = session.capture.averagePowerDB()
                self.loudnessDB = db
                if db.isFinite { self.loudestAverageDBFS = max(self.loudestAverageDBFS ?? db, db) }
                self.audioLevel = max(0, min(1, (db + 48) / 48))
                self.recordingDuration = session.capture.currentTime
                self.publishKeyboardSnapshot(minInterval: 0.10)

                if self.recordingDuration >= Self.maxCaptureDuration - 0.25 {
                    self.finishRecording()
                    return
                }

                try? await Task.sleep(for: .milliseconds(33))
            }
        }
    }

    private func stopMetering() {
        meterTask?.cancel()
        meterTask = nil
    }

    // MARK: - Warm Session Loop & Snapshot Truth

    private func startKeyboardSessionLoop() {
        keyboardSessionTask?.cancel()
        keyboardSessionTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.keyboardSessionEnabled else { return }

                // Never expire an in-flight recording or accepted transcription mid-work.
                if self.phase != .recording && self.phase != .transcribing {
                    let remaining = self.keyboardSessionExpiresAt - self.now()
                    if remaining <= 0 {
                        self.endWarmSession()
                        return
                    }
                    self.keyboardSessionRemaining = remaining

                    // Verify the keepalive engine is genuinely alive so we never publish a stuck "Ready".
                    if self.phase == .ready && !self.audio.isKeepaliveRunning && !self.suspendedWarmSessionOnInterruption {
                        do {
                            try self.audio.startKeepalive(allowBluetooth: self.allowBluetoothMic)
                        } catch {
                            self.endWarmSession()
                            return
                        }
                    }
                }

                self.consumeKeyboardCommand()
                if self.phase != .recording {
                    self.publishKeyboardSnapshot(minInterval: 0.60)
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    func processPendingKeyboardCommandForTesting() {
        consumeKeyboardCommand()
        publishKeyboardSnapshot()
    }

    func updateRecordingDurationForTesting(_ duration: TimeInterval) {
        recordingDuration = duration
    }

    private func consumeKeyboardCommand() {
        dictationLog?.drainKeyboardFeedback()
        guard let command = keyboardBridge.latestCommand(),
              command.id != lastKeyboardCommandID else { return }
        lastKeyboardCommandID = command.id

        // Ignore stale commands left in UserDefaults from >10s ago.
        guard now() - command.sentAt <= KeyboardLaunchRequest.handoffWindow else { return }

        switch command.kind {
        case .start:
            guard phase == .ready, activeKeyboardJobID == nil else { return }
            setStyle(command.style)
            startRecording(
                keyboardJobID: command.jobID,
                styleOverride: command.style,
                copyToPasteboard: false,
                keyboardContext: command.context
            )
        case .stop:
            guard phase == .recording, activeKeyboardJobID == command.jobID else { return }
            finishRecording()
        case .cancel:
            guard (phase == .recording || phase == .transcribing),
                  activeKeyboardJobID == command.jobID else { return }
            cancelCurrentJob()
        }
    }

    private func publishKeyboardSnapshot(minInterval: TimeInterval = 0) {
        let currentTime = now()

        if let expires = keyboardResultExpiresAt, expires <= currentTime {
            keyboardResultID = nil
            keyboardFeedbackOffer = nil
            keyboardResult = nil
            keyboardResultExpiresAt = nil
        }

        let state: KeyboardDictationState
        switch phase {
        case .recording:
            // Hardware truth guard: only claim `.recording` while an active capture is genuinely recording.
            if let session = activeCapture, session.capture.isRecording {
                state = .recording
            } else {
                state = keyboardSessionEnabled ? .ready : .offline
            }
        case .transcribing:
            state = .transcribing
        case .failed:
            state = .failed
        case .modelRequired, .preparingModel, .requestingPermission:
            state = .offline
        case .ready:
            state = (keyboardSessionEnabled && audio.isKeepaliveRunning) ? .ready : .offline
        }

        let failureMessage: String?
        if case .failed(let message) = phase {
            failureMessage = message
        } else {
            failureMessage = keyboardMessage
        }

        let signature = "\(state.rawValue)|\(activeKeyboardJobID ?? "")|\(keyboardResultID ?? "")|\(failureMessage ?? "")"
        if minInterval > 0,
           signature == lastPublishedSnapshotSignature,
           currentTime - lastPublishedSnapshotAt < minInterval {
            return
        }
        lastPublishedSnapshotSignature = signature
        lastPublishedSnapshotAt = currentTime

        let effectiveHeartbeat: TimeInterval
        if state == .recording || state == .transcribing || (keyboardSessionEnabled && audio.isKeepaliveRunning) {
            effectiveHeartbeat = currentTime
        } else {
            effectiveHeartbeat = 0
        }

        keyboardBridge.publish(
            KeyboardSnapshot(
                state: state,
                heartbeat: effectiveHeartbeat,
                expiresAt: keyboardSessionEnabled ? keyboardSessionExpiresAt : 0,
                recordingStartedAt: activeCapture?.startedAt,
                audioLevel: state == .recording ? audioLevel : 0,
                loudnessDB: state == .recording ? loudnessDB : nil,
                jobID: activeKeyboardJobID,
                resultID: keyboardResultID,
                resultExpiresAt: keyboardResultExpiresAt,
                transcript: keyboardResult,
                message: failureMessage,
                feedbackOffer: keyboardFeedbackOffer?.resultID == keyboardResultID ? keyboardFeedbackOffer : nil
            )
        )
    }

    // MARK: - Audio Interruptions, Route Changes, & System Intents

    private func wireAudioCallbacks() {
        audio.onUnexpectedCaptureEnd = { [weak self] finishedURL, succeeded in
            guard let self,
                  let session = self.activeCapture,
                  session.capture.url == finishedURL else {
                return
            }
            if succeeded {
                self.finishRecording()
            } else {
                self.cancelCurrentJob()
                self.phase = .failed("Recording stopped unexpectedly.")
                self.publishKeyboardSnapshot()
            }
        }

        audio.onSystemEvent = { [weak self] event in
            self?.handleAudioSystemEvent(event)
        }
    }

    func handleAudioSystemEvent(_ event: AudioSystemEvent) {
        switch event {
        case .interruptionBegan:
            suspendedWarmSessionOnInterruption = keyboardSessionEnabled
            if phase == .recording {
                // Save spoken audio if >= 300ms; otherwise cancel cleanly so "Listening" never sticks during a call.
                if let session = activeCapture, max(recordingDuration, session.capture.currentTime) >= Self.minCaptureDuration {
                    audio.stopKeepalive()
                    finishRecording()
                } else {
                    cancelCurrentJob()
                    keyboardMessage = "Interrupted"
                }
            } else {
                audio.stopKeepalive()
            }
            publishKeyboardSnapshot()

        case .interruptionEnded(let shouldResume):
            guard suspendedWarmSessionOnInterruption else { return }
            suspendedWarmSessionOnInterruption = false
            guard keyboardSessionEnabled, keyboardSessionExpiresAt > now() else {
                endWarmSession()
                return
            }
            if shouldResume || UIApplication.shared.applicationState == .active {
                do {
                    try audio.startKeepalive(allowBluetooth: allowBluetoothMic)
                    publishKeyboardSnapshot()
                } catch {
                    endWarmSession()
                }
            } else {
                endWarmSession()
            }

        case .routeOldDeviceUnavailable:
            // e.g. AirPods placed in case: finish active speech >= 300ms or rebind keepalive tap to built-in mic.
            if phase == .recording {
                if let session = activeCapture, max(recordingDuration, session.capture.currentTime) >= Self.minCaptureDuration {
                    finishRecording()
                } else {
                    cancelCurrentJob()
                }
            } else if keyboardSessionEnabled && phase == .ready {
                do {
                    try audio.startKeepalive(allowBluetooth: allowBluetoothMic)
                    publishKeyboardSnapshot()
                } catch {
                    endWarmSession()
                }
            }

        case .routeNewDeviceAvailable:
            if keyboardSessionEnabled && phase == .ready && allowBluetoothMic {
                try? audio.startKeepalive(allowBluetooth: allowBluetoothMic)
                publishKeyboardSnapshot()
            }

        case .mediaServicesReset:
            if phase == .recording {
                cancelCurrentJob()
            }
            if keyboardSessionEnabled {
                do {
                    try audio.startKeepalive(allowBluetooth: allowBluetoothMic)
                    publishKeyboardSnapshot()
                } catch {
                    endWarmSession()
                }
            }
        }
    }

    private func wireSystemIntentBus() {
        Task {
            await TyprSystemCommandBus.shared.register { [weak self] command in
                guard let self else { return nil }
                return await self.performSystemCommand(command)
            }
        }
    }

    private func performSystemCommand(_ command: TyprSystemCommand) async -> String? {
        switch command {
        case .toggleDictation:
            if phase == .recording {
                finishRecording()
                if let task = transcriptionTask {
                    await task.value
                }
                return transcript
            }
            if phase == .modelRequired || isFailedPhase {
                prepareModel()
                try? await waitUntilReady(timeoutSeconds: 10)
            }
            guard phase == .ready else { return nil }
            startRecording(copyToPasteboard: true)
            return ""

        case .stopDictation:
            guard phase == .recording else { return transcript }
            finishRecording()
            if let task = transcriptionTask {
                await task.value
            }
            return transcript

        case .cancelDictation:
            cancelCurrentJob()
            return nil

        case .warmSession:
            if !keyboardSessionEnabled {
                if warmDuration == .off {
                    setWarmDuration(.fifteenMinutes)
                }
                requestWarmSession(attemptAutoReturn: false)
            }
            return nil
        }
    }

    private var isFailedPhase: Bool {
        if case .failed = phase { return true }
        return false
    }

    private func waitUntilReady(timeoutSeconds: TimeInterval) async throws {
        let deadline = now() + timeoutSeconds
        while phase == .preparingModel && now() < deadline {
            try await Task.sleep(for: .milliseconds(100))
        }
    }

    // MARK: - Launch Fixtures for Simulator Verification (`--snap-state <name>`)

    private static func applyLaunchFixtureIfPresent(to controller: DictationController) -> Bool {
        let args = ProcessInfo.processInfo.arguments
        guard let flagIndex = args.firstIndex(of: "--snap-state"),
              flagIndex + 1 < args.count else {
            return false
        }
        let scene = args[flagIndex + 1]
        controller.engineName = "Apple Speech"
        controller.transcriptionLanguage = "English"
        controller.keyboardBridge.setModelInstalled(true)
        controller.isModelReady = true

        switch scene {
        case "setup":
            controller.phase = .ready
            controller.warmDuration = .fifteenMinutes
            controller.keyboardSessionEnabled = false

        case "ready":
            controller.phase = .ready
            controller.warmDuration = .off
            controller.keyboardSessionEnabled = false
            controller.transcript = "Meet at ten on Thursday and bring the updated design notes."

        case "warm":
            controller.phase = .ready
            controller.warmDuration = .fifteenMinutes
            controller.keyboardSessionEnabled = true
            controller.keyboardSessionRemaining = 14 * 60 + 42
            controller.keyboardSessionExpiresAt = Date().timeIntervalSince1970 + 14 * 60 + 42
            controller.transcript = "Meet at ten on Thursday and bring the updated design notes."

        case "recording":
            controller.phase = .recording
            controller.warmDuration = .fifteenMinutes
            controller.audioLevel = 0.74
            controller.loudnessDB = -31.0
            controller.recordingDuration = 6.4
            controller.keyboardSessionEnabled = true
            controller.keyboardSessionRemaining = 14 * 60 + 54

        case "transcribing":
            controller.phase = .transcribing
            controller.warmDuration = .fifteenMinutes
            controller.keyboardSessionEnabled = true
            controller.keyboardSessionRemaining = 14 * 60 + 52

        case "handoff-listening", "handoff-no-home-bar":
            controller.phase = .recording
            controller.audioLevel = 0.68
            controller.loudnessDB = -32.5
            controller.recordingDuration = 3.2
            controller.keyboardSessionEnabled = true
            controller.keyboardSessionRemaining = 14 * 60 + 57
            controller.autoReturnState = .swipeFallback
            Task { @MainActor in
                let start = Date().timeIntervalSince1970 - 3.0
                var simTime: Float = 0.0
                while !Task.isCancelled {
                    controller.loudnessDB = DotScopeSimulation.demoLoudness(at: simTime) + 4.5
                    controller.recordingDuration = Date().timeIntervalSince1970 - start
                    simTime += 0.033
                    try? await Task.sleep(for: .milliseconds(33))
                }
            }

        case "handoff-tour":
            controller.phase = .recording
            controller.audioLevel = 0.68
            controller.loudnessDB = -32.0
            controller.recordingDuration = 0.0
            controller.keyboardSessionEnabled = true
            controller.keyboardSessionRemaining = 14 * 60 + 58
            controller.autoReturnState = .swipeFallback
            Task { @MainActor in
                let boot = Date().timeIntervalSince1970
                var simTime: Float = 0.0
                while !Task.isCancelled {
                    let elapsed = Date().timeIntervalSince1970 - boot
                    if elapsed < 3.4 {
                        if controller.phase != .recording {
                            withAnimation(TyprMotion.stage) {
                                controller.phase = .recording
                            }
                        }
                        controller.loudnessDB = DotScopeSimulation.demoLoudness(at: simTime) + 4.5
                        controller.recordingDuration = elapsed
                        simTime += 0.033
                    } else if elapsed < 4.7 {
                        if controller.phase != .transcribing {
                            withAnimation(TyprMotion.stage) {
                                controller.phase = .transcribing
                            }
                        }
                        controller.loudnessDB = -120.0
                    } else {
                        if controller.phase != .ready {
                            withAnimation(TyprMotion.stage) {
                                controller.phase = .ready
                            }
                        }
                    }
                    try? await Task.sleep(for: .milliseconds(33))
                }
            }

        case "handoff-returning":
            controller.phase = .recording
            controller.audioLevel = 0.62
            controller.recordingDuration = 1.1
            controller.keyboardSessionEnabled = true
            controller.keyboardSessionRemaining = 14 * 60 + 59
            controller.autoReturnState = .attempting

        case "hosted-keyboard-warm":
            controller.phase = .ready
            controller.warmDuration = .fifteenMinutes
            controller.keyboardSessionEnabled = true
            controller.keyboardSessionRemaining = 14 * 60 + 42
            controller.keyboardSessionExpiresAt = Date().timeIntervalSince1970 + 14 * 60 + 42
            Task { @MainActor in
                while !Task.isCancelled {
                    let t = Date().timeIntervalSince1970
                    controller.keyboardBridge.publish(
                        KeyboardSnapshot(
                            state: .ready,
                            heartbeat: t,
                            expiresAt: t + 14 * 60 + 42
                        )
                    )
                    try? await Task.sleep(for: .milliseconds(250))
                }
            }

        case "hosted-keyboard-recording", "hosted-keyboard-light":
            controller.phase = .ready
            controller.warmDuration = .fifteenMinutes
            controller.keyboardSessionEnabled = true
            controller.keyboardSessionRemaining = 14 * 60 + 55
            let startWall = Date().timeIntervalSince1970 - 4.0
            Task { @MainActor in
                var simTime: Float = 0.4
                while !Task.isCancelled {
                    let t = Date().timeIntervalSince1970
                    let db = -28.5 + 5.2 * sin(simTime * 19.0) + 2.4 * cos(simTime * 7.3)
                    controller.keyboardBridge.publish(
                        KeyboardSnapshot(
                            state: .recording,
                            heartbeat: t,
                            expiresAt: t + 15 * 60,
                            recordingStartedAt: startWall,
                            audioLevel: 0.78,
                            loudnessDB: db,
                            jobID: "hosted-demo-job"
                        )
                    )
                    simTime += 0.033
                    try? await Task.sleep(for: .milliseconds(33))
                }
            }

        case "hosted-keyboard-tour":
            controller.phase = .ready
            controller.warmDuration = .fifteenMinutes
            controller.keyboardSessionEnabled = true
            controller.keyboardSessionRemaining = 14 * 60 + 58
            Task { @MainActor in
                let boot = Date().timeIntervalSince1970
                let freshResultID = "hosted-tour-\(UUID().uuidString)"
                var simTime: Float = 0.0
                while !Task.isCancelled {
                    let t = Date().timeIntervalSince1970
                    let elapsed = t - boot
                    if elapsed < 2.5 {
                        controller.keyboardBridge.publish(
                            KeyboardSnapshot(
                                state: .ready,
                                heartbeat: t,
                                expiresAt: t + 15 * 60
                            )
                        )
                    } else if elapsed < 5.2 {
                        let db = DotScopeSimulation.demoLoudness(at: simTime) + 4.5
                        controller.keyboardBridge.publish(
                            KeyboardSnapshot(
                                state: .recording,
                                heartbeat: t,
                                expiresAt: t + 15 * 60,
                                recordingStartedAt: boot + 2.5,
                                audioLevel: 0.78,
                                loudnessDB: db,
                                jobID: "hosted-tour-job"
                            )
                        )
                        simTime += 0.033
                    } else if elapsed < 6.4 {
                        controller.keyboardBridge.publish(
                            KeyboardSnapshot(
                                state: .transcribing,
                                heartbeat: t,
                                expiresAt: t + 15 * 60,
                                jobID: "hosted-tour-job"
                            )
                        )
                    } else {
                        controller.keyboardBridge.publish(
                            KeyboardSnapshot(
                                state: .ready,
                                heartbeat: t,
                                expiresAt: t + 14 * 60 + 54,
                                resultID: freshResultID,
                                resultExpiresAt: boot + 30,
                                transcript: "See you at ten."
                            )
                        )
                    }
                    try? await Task.sleep(for: .milliseconds(33))
                }
            }

        default:
            return false
        }
        return true
    }
}
