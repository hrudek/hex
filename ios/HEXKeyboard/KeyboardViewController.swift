import SwiftUI
import UIKit

@MainActor
final class KeyboardViewController: UIInputViewController, UIGestureRecognizerDelegate {
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
    /// The compact bar's drag zone: the handle, the top padding, and the 26 pt top bar.
    private static let compactDragZone: CGFloat = KeyboardLayout.grabberZoneHeight + 4 + 26

    /// A drag on the top of either keyboard resizes it live; release switches or settles back.
    private struct ResizeDrag {
        let direction: KeyboardGrabberDrag.Direction
        let fromHeight: CGFloat
        let toHeight: CGFloat
        var isArmed = false
    }

    private lazy var resizePan: UIPanGestureRecognizer = {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handleResizePan(_:)))
        pan.maximumNumberOfTouches = 1
        pan.cancelsTouchesInView = true
        pan.delaysTouchesBegan = false
        pan.delegate = self
        return pan
    }()
    private var resizeDrag: ResizeDrag?
    private var surfaceBottom: NSLayoutConstraint?
    private var surfaceDragHeight: NSLayoutConstraint?
    private let dragHaptics = UISelectionFeedbackGenerator()

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

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        cancelResizeDrag()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        cancelResizeDrag()
        pollTimer?.invalidate()
        pollTimer = nil
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        fullKeyboard?.handleMemoryWarning()
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        if let fullKeyboard, resizeDrag == nil {
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
        view.addGestureRecognizer(resizePan)
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
        endResizeDrag()
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
        let swaps = mounted && wantsFull != (fullKeyboard != nil)
        // Handles and their zone change height, so they wait for idle like a swap. A swap
        // sizes the new surface itself, so the old one isn't resized first.
        if !swaps && resizeDrag == nil && (!mounted || canSwapSurface) {
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
        // A resize drag owns the height until it ends.
        guard resizeDrag == nil else { return }
        guard !mounted || swaps else { return }
        guard !mounted || canSwapSurface else { return }
        if viewModel.canShowFullKeyboard != switching {
            viewModel.canShowFullKeyboard = switching
        }

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
        let bottom = next.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        NSLayoutConstraint.activate([
            next.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            next.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            next.topAnchor.constraint(equalTo: view.topAnchor),
            bottom,
        ])
        surfaceBottom = bottom
        surfaceDragHeight = nil
        surface = next
        schedulePoll(force: false)
    }

    // MARK: - Resize drag

    /// Where a drag may start: the top zone of the shown keyboard, while switching is offered and idle.
    private var resizeDragZone: CGFloat {
        guard viewModel.canShowFullKeyboard, canSwapSurface else { return 0 }
        if let fullKeyboard { return fullKeyboard.dragZoneHeight }
        return surface == nil ? 0 : Self.compactDragZone
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard gestureRecognizer === resizePan else { return true }
        return touch.location(in: view).y < resizeDragZone
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === resizePan, resizeDragZone > 0 else { return false }
        // Decide by the distance moved, not the speed: a fast flick still reads as vertical.
        let t = resizePan.translation(in: view)
        return abs(t.y) > abs(t.x) * 1.3
    }

    @objc private func handleResizePan(_ pan: UIPanGestureRecognizer) {
        let translation = pan.translation(in: view).y
        switch pan.state {
        case .began:
            beginResizeDrag()
            updateResizeDrag(translation: translation)
        case .changed:
            guard canSwapSurface else { return cancelResizeDrag() }
            updateResizeDrag(translation: translation)
        case .ended:
            guard let drag = resizeDrag else { return }
            let commits = canSwapSurface && KeyboardGrabberDrag.commits(
                translation: translation,
                velocity: pan.velocity(in: view).y,
                direction: drag.direction
            )
            if commits {
                switchLayout(to: drag.direction == .down ? .compact : .full)
            } else {
                cancelResizeDrag()
            }
        default:
            cancelResizeDrag()
        }
    }

    private func beginResizeDrag() {
        guard let surface, resizeDrag == nil else { return }
        let full = FullKeyboardView.height(
            for: FullKeyboardView.orientation(for: traitCollection),
            allowsCompactKeyboard: true
        )
        let from = heightConstraint?.constant ?? compactHeight
        let direction: KeyboardGrabberDrag.Direction = fullKeyboard != nil ? .down : .up
        resizeDrag = ResizeDrag(direction: direction, fromHeight: from, toHeight: direction == .down ? compactHeight : full)
        fullKeyboard?.dragDidBegin()
        if viewModel.activeTray != .none {
            viewModel.setActiveTray(.none, reduceMotion: true)
        }
        // The surface keeps its own height and rides the top edge, like a sheet; the rest clips.
        view.clipsToBounds = true
        surfaceBottom?.isActive = false
        let height = surface.heightAnchor.constraint(equalToConstant: from)
        height.isActive = true
        surfaceDragHeight = height
        if hasFullAccess { dragHaptics.prepare() }
    }

    private func updateResizeDrag(translation: CGFloat) {
        guard var drag = resizeDrag else { return }
        let height = KeyboardGrabberDrag.height(
            from: drag.fromHeight,
            to: drag.toHeight,
            translation: translation,
            direction: drag.direction
        )
        applyHeight(height)
        let armed = KeyboardGrabberDrag.isArmed(translation: translation, direction: drag.direction)
        if armed != drag.isArmed {
            drag.isArmed = armed
            if armed && hasFullAccess { dragHaptics.selectionChanged() }
            fullKeyboard?.setDragArmed(armed)
            if viewModel.isGrabberArmed != armed { viewModel.isGrabberArmed = armed }
        }
        resizeDrag = drag
    }

    /// Back to the shown keyboard's own height.
    private func cancelResizeDrag() {
        guard let drag = resizeDrag else { return }
        endResizeDrag()
        let duration = UIAccessibility.isReduceMotionEnabled ? 0 : 0.22
        heightConstraint?.constant = drag.fromHeight
        UIView.animate(withDuration: duration, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
            self.view.superview?.layoutIfNeeded()
            self.view.layoutIfNeeded()
        }
        applyHeight(drag.fromHeight)
    }

    /// Restores the surface's constraints; the caller sets the height.
    private func endResizeDrag() {
        guard resizeDrag != nil else { return }
        resizeDrag = nil
        surfaceDragHeight?.isActive = false
        surfaceDragHeight = nil
        surfaceBottom?.isActive = true
        view.clipsToBounds = false
        fullKeyboard?.setDragArmed(false)
        if viewModel.isGrabberArmed { viewModel.isGrabberArmed = false }
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
            cancelResizeDrag()
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

        // A status change cancels the drag even while the finger is held still. Once
        // cancelled it cannot become eligible again when the bridge returns to idle.
        if !canSwapSurface { cancelResizeDrag() }
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
