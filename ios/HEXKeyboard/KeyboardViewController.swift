import SwiftUI
import UIKit

@MainActor
final class KeyboardViewController: UIInputViewController {
    private let bridge = KeyboardBridge()
    private let viewModel = KeyboardViewModel()
    private var pollTimer: Timer?
    private var coldStartJobID = UUID().uuidString
    private var lastURLRefreshBucket: Int = 0
    private var lastFullAccessNote: TimeInterval = 0
    private var surface: UIView?
    private var fullKeyboard: FullKeyboardView?
    private var heightConstraint: NSLayoutConstraint?
    private var pollInterval: TimeInterval = 0
    private var didHandOffCurrentField = false
    private var didWarmLexicon = false
    /// The keyboard the person switched to in this extension session. It wins over the
    /// App Group value, so a poll never undoes a fresh switch, and it still holds when
    /// the App Group can't be written.
    private var sessionLayoutChoice: KeyboardLayoutChoice?

    private static let compactBarHeight: CGFloat = 140

    /// The compact bar, plus the drag handle's zone when it can switch to the full keyboard.
    private var compactHeight: CGFloat {
        Self.compactBarHeight + (viewModel.canShowFullKeyboard ? KeyboardLayout.grabberZoneHeight : 0)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureView()
        syncFromBridge(animated: false)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        coldStartJobID = UUID().uuidString
        didHandOffCurrentField = false
        mountSurface()
        fullKeyboard?.prepareForField()
        handOffNumericPadIfNeeded()
        syncFromBridge(animated: false)
        schedulePoll(force: true)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        warmFullKeyboardLexiconIfNeeded()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        pollTimer?.invalidate()
        pollTimer = nil
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        fullKeyboard?.handleMemoryWarning()
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        if let fullKeyboard {
            applyHeight(fullKeyboard.preferredHeight)
        }
    }

    override func textWillChange(_ textInput: UITextInput?) {
        super.textWillChange(textInput)
        if KeyboardFieldRouting.route(for: textDocumentProxy.keyboardType) != .handOff {
            didHandOffCurrentField = false
        }
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        updateKeyboardTraits()
        fullKeyboard?.textDidChange()
        handOffNumericPadIfNeeded()
    }

    private func handOffNumericPadIfNeeded() {
        guard fullKeyboard != nil else { return }
        if KeyboardFieldRouting.route(for: textDocumentProxy.keyboardType) == .handOff {
            guard !didHandOffCurrentField else { return }
            didHandOffCurrentField = true
            if needsInputModeSwitchKey {
                advanceToNextInputMode()
            }
        } else {
            didHandOffCurrentField = false
        }
    }

    private func warmFullKeyboardLexiconIfNeeded() {
        guard let fullKeyboard else { return }
        fullKeyboard.warmUpTextCheckerAsync()
        guard !didWarmLexicon else { return }
        didWarmLexicon = true
        // UIKit calls this completion on a background queue. A closure written
        // here would inherit the controller's main-actor isolation, and Swift 6
        // traps on its isolation check before the body runs, so keep it
        // @Sendable (nonisolated) and hop to the main actor explicitly.
        requestSupplementaryLexicon { @Sendable [weak self] lexicon in
            nonisolated(unsafe) let lexicon = lexicon
            Task { @MainActor in
                self?.fullKeyboard?.loadLexicon(lexicon)
            }
        }
    }

    private func configureView() {
        view.backgroundColor = .clear

        viewModel.inputViewController = self
        viewModel.onDictateTap = { [weak self] in self?.startWarmDictation() }
        viewModel.onStopTap = { [weak self] in self?.stopWarmDictation() }
        viewModel.onCancelTap = { [weak self] in self?.cancelWarmDictation() }
        viewModel.onStyleSelected = { [weak self] style in
            guard let self else { return }
            self.bridge.style = style
            if self.viewModel.style != style {
                self.viewModel.style = style
            }
            self.refreshColdStartURL(now: Date().timeIntervalSince1970, force: true)
        }
        viewModel.onReturnAppSelected = { [weak self] appID in
            guard let self else { return }
            self.bridge.returnAppID = appID
            if self.viewModel.returnAppID != appID {
                self.viewModel.returnAppID = appID
            }
            self.refreshColdStartURL(now: Date().timeIntervalSince1970, force: true)
        }
        viewModel.onSpace = { [weak self] in self?.textDocumentProxy.insertText(" ") }
        viewModel.onDelete = { [weak self] in self?.textDocumentProxy.deleteBackward() }
        viewModel.onReturn = { [weak self] in self?.textDocumentProxy.insertText("\n") }
        viewModel.onOpenURL = { [weak self] url in
            guard let self else { return }
            ContainingAppOpener.open(url, from: self)
        }
        viewModel.onShowFullKeyboard = { [weak self] in self?.switchLayout(to: .full) }
        viewModel.onShowCompactKeyboard = { [weak self] in self?.switchLayout(to: .compact) }

        let heightConstraint = view.heightAnchor.constraint(equalToConstant: Self.compactBarHeight)
        heightConstraint.priority = UILayoutPriority(999)
        heightConstraint.isActive = true
        self.heightConstraint = heightConstraint
        mountSurface()
    }

    /// No recording, transcription, or unanswered command: the surface may be swapped or resized.
    private var canSwapSurface: Bool {
        (viewModel.stagePhase == .idle || viewModel.stagePhase == .failed) && viewModel.pendingCommand == nil
    }

    /// A drag handle or the compact bar's keyboard key. Ignored while Hex records or waits
    /// on a command, without remembering it for later.
    private func switchLayout(to choice: KeyboardLayoutChoice) {
        guard canSwapSurface else { return }
        sessionLayoutChoice = choice
        FullKeyboardSettings().layoutChoice = choice
        viewModel.focusesFullKeyboardKeyOnAppear = choice == .compact
        mountSurface()
        fullKeyboard?.prepareForField()
        syncFromBridge(animated: false)
        warmFullKeyboardLexiconIfNeeded()
        // VoiceOver lands on the way back: the full keyboard's drag handle here; the compact
        // bar moves focus to its keyboard key itself (`focusesFullKeyboardKeyOnAppear`).
        if let fullKeyboard {
            UIAccessibility.post(notification: .screenChanged, argument: fullKeyboard.compactKeyboardAccessibilityElement)
        }
    }

    /// The dictation bar, or the full keyboard when its experiment is on (iPhone only) and
    /// the person hasn't switched to the compact bar. Only switches while idle.
    private func mountSurface() {
        let settings = FullKeyboardSettings()
        let isPhone = UIDevice.current.userInterfaceIdiom == .phone
        let experiment = settings.isEnabled
        let allowsCompact = settings.compactAllowed
        let switching = FullKeyboardSettings.offersSwitching(
            experimentEnabled: experiment,
            isPhone: isPhone,
            compactAllowed: allowsCompact
        )
        let wantsFull = FullKeyboardSettings.showsFullKeyboard(
            experimentEnabled: experiment,
            isPhone: isPhone,
            compactAllowed: allowsCompact,
            choice: sessionLayoutChoice ?? settings.layoutChoice
        )
        let mounted = surface != nil
        // Handles and their zone change height, so they wait for idle like a swap.
        if !mounted || canSwapSurface {
            if viewModel.canShowFullKeyboard != switching {
                viewModel.canShowFullKeyboard = switching
            }
            if let fullKeyboard {
                fullKeyboard.allowsCompactKeyboard = switching
                applyHeight(fullKeyboard.preferredHeight)
            } else if mounted {
                applyHeight(compactHeight)
            }
        }
        guard !mounted || wantsFull != (fullKeyboard != nil) else { return }
        guard !mounted || canSwapSurface else { return }

        fullKeyboard?.prepareForRemoval()
        if viewModel.activeTray != .none {
            viewModel.setActiveTray(.none, reduceMotion: true)
        }
        children.forEach { child in
            child.willMove(toParent: nil)
            child.removeFromParent()
        }
        surface?.removeFromSuperview()
        fullKeyboard = nil
        didWarmLexicon = false

        let next: UIView
        if wantsFull {
            let keyboard = FullKeyboardView(
                model: viewModel,
                target: DocumentProxyTextTarget { [unowned self] in self.textDocumentProxy }
            )
            keyboard.hostController = self
            keyboard.allowsHaptics = { [weak self] in self?.hasFullAccess ?? false }
            keyboard.allowsCompactKeyboard = switching
            fullKeyboard = keyboard
            next = keyboard
            // The new view has no traits until it is added; size it from the controller's.
            applyHeight(FullKeyboardView.height(
                for: FullKeyboardView.orientation(for: traitCollection),
                allowsCompactKeyboard: switching
            ))
        } else {
            let hosting = UIHostingController(rootView: KeyboardSurfaceView(model: viewModel))
            hosting.view.backgroundColor = .clear
            addChild(hosting)
            hosting.didMove(toParent: self)
            next = hosting.view
            applyHeight(compactHeight)
        }
        next.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(next)
        NSLayoutConstraint.activate([
            next.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            next.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            next.topAnchor.constraint(equalTo: view.topAnchor),
            next.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        surface = next
        schedulePoll(force: false)
    }

    /// The one place the keyboard's height changes: mount, rotation, handles, and switching.
    private func applyHeight(_ height: CGFloat) {
        if heightConstraint?.constant != height {
            heightConstraint?.constant = height
        }
        if preferredContentSize.height != height {
            preferredContentSize.height = height
        }
    }

    /// The dictation bar polls at 25 Hz; the full keyboard at 4 Hz, and 30 Hz while recording.
    private func schedulePoll(force: Bool) {
        let busy = viewModel.stagePhase == .recording || viewModel.stagePhase == .transcribing
            || viewModel.pendingCommand != nil
        let interval: TimeInterval = fullKeyboard == nil ? 0.04 : (busy ? 1.0 / 30 : 0.25)
        guard force || (pollTimer != nil && interval != pollInterval) else { return }
        pollInterval = interval
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.syncFromBridge(animated: true)
            }
        }
    }

    private func syncFromBridge(animated: Bool) {
        let now = Date().timeIntervalSince1970
        updateKeyboardTraits()
        fullKeyboard?.syncSettings()

        #if targetEnvironment(simulator)
        let simSnap = bridge.snapshot()
        let effectiveFullAccess = hasFullAccess || simSnap.isAvailable(at: now)
        #else
        let effectiveFullAccess = hasFullAccess
        #endif

        guard effectiveFullAccess else {
            viewModel.applyBridgeState(
                hasFullAccess: false,
                snapshot: .offline,
                isModelInstalled: false,
                style: viewModel.style,
                returnAppID: viewModel.returnAppID,
                now: now,
                clearPending: true,
                animated: animated
            )
            return
        }

        if now - lastFullAccessNote >= 5 {
            lastFullAccessNote = now
            bridge.fullAccessSeenAt = now
        }

        let snap = bridge.snapshot()
        var insertedResult = false

        if snap.hasDeliverableResult(at: now),
           let resultID = snap.resultID,
           let rawTranscript = snap.transcript,
           bridge.lastInsertedResultID != resultID {
            let insertion = TranscriptFormatter.insertionText(
                for: rawTranscript,
                beforeContext: textDocumentProxy.documentContextBeforeInput,
                afterContext: textDocumentProxy.documentContextAfterInput
            )
            textDocumentProxy.insertText(insertion)
            fullKeyboard?.didInsertDictation(insertion)
            bridge.lastInsertedResultID = resultID
            insertedResult = true
            coldStartJobID = UUID().uuidString
        }

        let quickReturnApps = bridge.quickReturnApps
        if viewModel.quickReturnApps != quickReturnApps {
            viewModel.quickReturnApps = quickReturnApps
        }

        viewModel.applyBridgeState(
            hasFullAccess: true,
            snapshot: snap,
            isModelInstalled: bridge.isModelInstalled,
            style: bridge.style,
            returnAppID: bridge.returnAppID,
            now: now,
            clearPending: insertedResult,
            animated: animated
        )

        refreshColdStartURL(now: now, force: false)
        schedulePoll(force: false)
    }

    private func refreshColdStartURL(now: TimeInterval, force: Bool) {
        let bucket = Int(now / 2.0)
        guard force || bucket != lastURLRefreshBucket else { return }
        lastURLRefreshBucket = bucket
        mountSurface()

        let request: KeyboardLaunchRequest
        if bridge.isModelInstalled {
            request = .startRecording(
                jobID: coldStartJobID,
                requestedAt: now,
                style: bridge.style,
                returnAppID: bridge.returnAppID
            )
        } else {
            request = .startSession(
                requestedAt: now,
                returnAppID: bridge.returnAppID
            )
        }
        viewModel.coldStartURL = request.url
    }

    private func updateKeyboardTraits() {
        let globe = needsInputModeSwitchKey
        if viewModel.needsGlobeKey != globe {
            viewModel.needsGlobeKey = globe
        }
        // Fields that ask for a dark keyboard get one even in light mode, like the system keyboard.
        overrideUserInterfaceStyle = textDocumentProxy.keyboardAppearance == .dark ? .dark : .unspecified
        let nextReturn: String = switch textDocumentProxy.returnKeyType {
        case .send: "Send"
        case .google, .yahoo, .search: "Search"
        case .go: "Go"
        case .done: "Done"
        case .join: "Join"
        case .next: "Next"
        case .route: "Route"
        case .continue: "Continue"
        case .emergencyCall: "SOS"
        default: "Return"
        }
        if viewModel.returnKeyLabel != nextReturn {
            viewModel.returnKeyLabel = nextReturn
        }
    }

    private func startWarmDictation() {
        let now = Date().timeIntervalSince1970
        guard viewModel.hasFullAccess, viewModel.currentSnapshot.isAvailable(at: now) else { return }
        let jobID = UUID().uuidString
        viewModel.setPendingCommand(
            KeyboardViewModel.PendingCommand(kind: .start, jobID: jobID, sentAt: now),
            now: now,
            animated: true
        )
        bridge.send(.start, jobID: jobID, style: viewModel.style, sentAt: now)
    }

    private func stopWarmDictation() {
        let now = Date().timeIntervalSince1970
        guard let jobID = viewModel.currentSnapshot.jobID ?? viewModel.pendingCommand?.jobID else { return }
        viewModel.setPendingCommand(
            KeyboardViewModel.PendingCommand(kind: .stop, jobID: jobID, sentAt: now),
            now: now,
            animated: true
        )
        bridge.send(.stop, jobID: jobID, style: viewModel.style, sentAt: now)
    }

    private func cancelWarmDictation() {
        let now = Date().timeIntervalSince1970
        guard let jobID = viewModel.currentSnapshot.jobID ?? viewModel.pendingCommand?.jobID else { return }
        viewModel.setPendingCommand(
            KeyboardViewModel.PendingCommand(kind: .cancel, jobID: jobID, sentAt: now),
            now: now,
            animated: true
        )
        bridge.send(.cancel, jobID: jobID, style: viewModel.style, sentAt: now)
    }
}
