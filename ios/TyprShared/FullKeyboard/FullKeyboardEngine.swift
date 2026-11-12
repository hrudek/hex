import QuartzCore
import UIKit

/// The text field the keys type into. `UITextDocumentProxy` in the keyboard; a fake in tests.
@MainActor
protocol KeyboardTextTarget: AnyObject {
    var documentContextBeforeInput: String? { get }
    var hasText: Bool { get }
    var autocapitalizationType: UITextAutocapitalizationType? { get }
    var autocorrectionType: UITextAutocorrectionType? { get }
    var isSecureTextEntry: Bool? { get }
    var keyboardType: UIKeyboardType? { get }
    var returnKeyType: UIReturnKeyType? { get }
    var enablesReturnKeyAutomatically: Bool? { get }
    var keyboardAppearance: UIKeyboardAppearance? { get }
    func insertText(_ text: String)
    func deleteBackward()
    func adjustTextPosition(byCharacterOffset offset: Int)
}

extension KeyboardTextTarget {
    var autocorrectionType: UITextAutocorrectionType? { .default }
    var isSecureTextEntry: Bool? { false }
    var enablesReturnKeyAutomatically: Bool? { false }
    func adjustTextPosition(byCharacterOffset offset: Int) {}
}

@MainActor
final class DocumentProxyTextTarget: KeyboardTextTarget {
    private let proxy: () -> UITextDocumentProxy

    init(_ proxy: @escaping () -> UITextDocumentProxy) {
        self.proxy = proxy
    }

    var documentContextBeforeInput: String? { proxy().documentContextBeforeInput }
    var hasText: Bool { proxy().hasText }
    var autocapitalizationType: UITextAutocapitalizationType? { proxy().autocapitalizationType }
    var autocorrectionType: UITextAutocorrectionType? { proxy().autocorrectionType }
    var isSecureTextEntry: Bool? { proxy().isSecureTextEntry }
    var keyboardType: UIKeyboardType? { proxy().keyboardType }
    var returnKeyType: UIReturnKeyType? { proxy().returnKeyType }
    var enablesReturnKeyAutomatically: Bool? { proxy().enablesReturnKeyAutomatically }
    var keyboardAppearance: UIKeyboardAppearance? { proxy().keyboardAppearance }
    func insertText(_ text: String) { proxy().insertText(text) }
    func deleteBackward() { proxy().deleteBackward() }
    func adjustTextPosition(byCharacterOffset offset: Int) { proxy().adjustTextPosition(byCharacterOffset: offset) }
}

/// Everything the keys do, apart from drawing: multitouch with rollover, shift, pages,
/// long-press accents, spacebar cursor trackpad, cautious autocorrect, double-space period,
/// auto-capitalization and accelerating delete. Touches are identified by any stable integer
/// so tests can drive it without `UITouch`.
@MainActor
final class FullKeyboardEngine {
    struct ActiveTouch: Equatable {
        var key: KeyboardKey
        var startPoint: CGPoint
        var point: CGPoint
        /// Captured geometry; layout changes and key-to-key slides make evidence ambiguous.
        var evidenceLayout: KeyboardLayout
        var hasUnambiguousPoint = true
        /// A character that already went in because another key went down after it.
        var committed: Bool
        /// The page a 123/ABC press came from; releasing over a character returns there.
        var returnLayer: KeyboardLayer?
        /// True once a spacebar press crosses `trackpadActivationDistance`.
        var isTrackpad = false
        var trackpadAnchorX: CGFloat = 0
    }

    static let accentHoldDelay: TimeInterval = 0.40
    static let accentSlop: CGFloat = 10
    static let trackpadActivationDistance: CGFloat = 10
    static let trackpadPointsPerCharacter: CGFloat = 7.5

    private(set) var shift = ShiftStateMachine()
    private(set) var layerState = KeyboardLayerState()
    private(set) var field: KeyboardFieldKind = .text
    private(set) var touches: [Int: ActiveTouch] = [:]
    /// Touch ids in the order they went down.
    private var touchOrder: [Int] = []
    private var lastSpaceAt: TimeInterval?

    private(set) var activeAccentMenu: AccentMenu?
    private var activeAccentTouchID: Int?
    private(set) var suggestions: [KeyboardSuggestion] = []
    private let suggestionWorker: KeyboardSuggestionWorker
    private let suggestionEngineID = UUID()
    private var textRevision: UInt64 = 0
    private(set) var suggestionsAreActive = true
    /// What the strip currently shows: its ownership, the taps it was ranked from and whether
    /// it is a finished ranking (not the interim literal chips).
    private struct PublishedStrip {
        let ownership: KeyboardSuggestionOwnership
        let evidence: KeyboardTouchWord?
        let final: Bool
    }
    private var published: PublishedStrip?
    private var attribution: (ownership: KeyboardSuggestionOwnership, map: KeyboardKeyMap)?
    static let suggestionContextLimit = 256
    static let suggestionContextUTF8Limit = 2_048
    private static let suggestionTokenLimit = 64

    /// Bounded RAM-only ownership, also checked at chip acceptance before any edit/learning.
    var suggestionOwnership: KeyboardSuggestionOwnership {
        let context = target.documentContextBeforeInput.flatMap(Self.boundedSuggestionContext)
        let token = AutocorrectEngine.currentToken(in: context)
        let route = KeyboardFieldRouting.route(for: target.keyboardType)
        let prose: Bool
        if case .keys(.text, _) = route { prose = true } else { prose = false }
        return .init(engine: suggestionEngineID, revision: textRevision, context: context,
                     token: token, field: field,
                     permitsCorrection: prose && target.autocorrectionType != .no && target.isSecureTextEntry != true,
                     configuration: autocorrect.suggestionConfiguration,
                     learning: autocorrect.learning.generation, feedbackEpoch: autocorrect.learning.feedbackEpoch,
                     resources: autocorrect.spatialDecoder?.resourceRevision ?? -1, layout: layout)
    }

    /// The longest whole-character suffix within 256 characters and 2,048 UTF-8 bytes, so
    /// emoji/ZWJ-heavy text still yields the current word. Nil only if the last character alone
    /// exceeds the byte cap (then it is no word token anyway).
    static func boundedSuggestionContext(_ before: String) -> String? {
        var start = before.endIndex
        var characters = 0
        var bytes = 0
        while start > before.startIndex, characters < suggestionContextLimit {
            let previous = before.index(before: start)
            let size = before[previous..<start].utf8.count
            guard bytes + size <= suggestionContextUTF8Limit else { break }
            bytes += size
            characters += 1
            start = previous
        }
        guard start < before.endIndex || before.isEmpty else { return nil }
        return String(before[start...])
    }

    let target: KeyboardTextTarget
    let autocorrect: AutocorrectEngine
    var width: CGFloat = 375 { didSet { if width != oldValue { rebuildLayout() } } }
    var orientation: KeyboardOrientation = .portrait { didSet { if orientation != oldValue { rebuildLayout() } } }
    var showsGlobe = false { didSet { if showsGlobe != oldValue { rebuildLayout() } } }
    var horizontalInset: CGFloat = 0 { didSet { if horizontalInset != oldValue { rebuildLayout() } } }
    /// Typr: without the suggestion bar the keys move up and no suggestions are computed.
    var showsStrip = true {
        didSet {
            guard showsStrip != oldValue else { return }
            rebuildLayout()
            refreshSuggestions()
        }
    }
    private(set) var layout = KeyboardLayout(width: 375)

    var clock: () -> TimeInterval = { CACurrentMediaTime() }
    /// Called whenever something visible changed (page, shift, pressed keys, suggestions, accents).
    var onChange: (() -> Void)?
    /// Called after the keys typed or deleted anything.
    var onEdit: (() -> Void)?
    /// Called when an accent cell or spacebar trackpad step ticks, for selection haptics.
    var onSelectionStep: (() -> Void)?

    init(target: KeyboardTextTarget, autocorrect: AutocorrectEngine? = nil,
         suggestionWorker: KeyboardSuggestionWorker? = nil) {
        self.target = target
        self.autocorrect = autocorrect ?? AutocorrectEngine()
        self.suggestionWorker = suggestionWorker ?? KeyboardSuggestionWorker()
        rebuildLayout()
    }

    var isUppercase: Bool { layerState.layer == .letters && shift.isUppercase }

    var isTrackpadActive: Bool {
        touches.values.contains(where: \.isTrackpad)
    }

    /// The key whose balloon shows: the newest character still held (hidden while an accent menu is up).
    var previewKey: KeyboardKey? {
        guard activeAccentMenu == nil else { return nil }
        for id in touchOrder.reversed() {
            if let touch = touches[id], touch.key.character != nil, !touch.committed {
                return touch.key
            }
        }
        return nil
    }

    var pressedKinds: Set<KeyKind> {
        Set(touches.values.map(\.key.kind))
    }

    func displayLabel(for key: KeyboardKey) -> String {
        guard let character = key.character else { return key.label }
        return isUppercase && layerState.layer == .letters ? character.uppercased() : character
    }

    // MARK: - Field

    /// Call when the keyboard appears or the field changes.
    func configureForField() {
        suggestionsAreActive = true
        autocorrect.contextResources.prepare { [weak self] in self?.refreshSuggestions() }
        switch KeyboardFieldRouting.route(for: target.keyboardType) {
        case .keys(let kind, let initialLayer):
            field = kind
            layerState.reset(to: initialLayer)
        case .handOff:
            field = .text
            layerState.reset(to: .numbers)
        }
        shift.reset()
        lastSpaceAt = nil
        autocorrect.clearPendingUndo()
        cancelAllTouches(republishing: false)
        rebuildLayout()
        refreshAutoCapitalization()
        refreshSuggestions()
    }

    /// Call after the text or the cursor changed outside these keys.
    func textDidChange() {
        invalidateTouchEvidence()
        lastSpaceAt = nil
        autocorrect.clearPendingUndo()
        refreshAutoCapitalization()
        refreshSuggestions()
    }

    /// Invalidates in-flight taps too: a late release must not recreate evidence after a cursor/field change.
    /// Chips are owned by text revision and layout, so current-word chips (now without taps) are
    /// republished rather than leaving the strip blank (layer switch, rebuild, key slide, cursor move).
    func discardTouchEvidence() {
        invalidateTouchEvidence()
        refreshSuggestions()
    }

    /// For callers that refresh right afterwards anyway. Applied manual choices clear the
    /// word without resetting the fast aggregate aim just trained by independent feedback.
    private func invalidateTouchEvidence(resetFastAim: Bool = true) {
        textRevision &+= 1
        suggestionWorker.cancel()
        autocorrect.discardEvidence(resetFastAim: resetFastAim)
        for id in touchOrder {
            touches[id]?.hasUnambiguousPoint = false
        }
    }

    func refreshAutoCapitalization() {
        let before = shift
        shift.refreshAutoCapitalization(
            AutoCapitalization.shouldCapitalize(
                mode: AutoCapitalization.Mode(target.autocapitalizationType),
                before: target.documentContextBeforeInput,
                hasText: target.hasText
            )
        )
        if shift != before { onChange?() }
    }

    func refreshSuggestions() {
        guard suggestionsAreActive else { return }
        textRevision &+= 1
        // No decoder, checker, personal snapshot construction or lexicon scan on this path.
        let evidence = autocorrect.touchInput.evidence(beforeInput: target.documentContextBeforeInput)
        let ownership = suggestionOwnership
        // Current before returning to the event loop, independent of strip/worker readiness.
        attribution = autocorrect.keyMap(layout: layout, context: ownership.context,
                                        permitsCorrection: ownership.permitsCorrection).map { (ownership, $0) }
        // No current word: only corpus next-word predictions after a separator (no tap evidence).
        guard showsStrip, field == .text, ownership.permitsCorrection,
              ownership.token.map({ $0.count <= Self.suggestionTokenLimit && $0.utf8.count <= 256 })
                ?? autocorrect.canPredictNextWord(after: ownership.context) else {
            suggestionWorker.cancel()
            publishSuggestions([], ownership: ownership, evidence: evidence, final: true)
            return
        }
        if let published, published.final, published.evidence == evidence,
           published.ownership.hasSameContent(as: ownership) {
            // Same word, taps and configuration (warmup, poll, remount): keep the finished
            // ranking without flicker, re-owned by this revision while the checker step reruns.
            publishSuggestions(suggestions.map { var owned = $0; owned.ownership = ownership; return owned },
                               ownership: ownership, evidence: evidence, final: true)
        } else if let token = ownership.token {
            // Clear old alternatives immediately. The current literal is safe and remains pickable
            // while ranking is delayed, including during rapid rollover or after undo.
            publishSuggestions([
                .init(displayText: "“\(token)”", replacement: token, kind: .keepLiteral, ownership: ownership),
                .init(displayText: token, replacement: token, kind: .primary(autoReplace: false), ownership: ownership)
            ], ownership: ownership, evidence: evidence, final: false)
        } else {
            // Never leave the previous word's chips pickable while predictions are prepared.
            publishSuggestions([], ownership: ownership, evidence: evidence, final: false)
        }
        suggestionWorker.submit(prepare: { [weak self] in
            guard let self, self.textRevision == ownership.revision,
                  self.suggestionsAreActive, self.suggestionOwnership == ownership else { return nil }
            return self.autocorrect.suggestionRequest(ownership: ownership, evidence: evidence)
        }, finish: { [weak self] result in
            // Revision first: do not even read a torn-down document proxy after dismissal.
            guard let self, self.textRevision == ownership.revision,
                  result.request.ownership == ownership,
                  self.suggestionOwnership == ownership, self.showsStrip else { return }
            let next = self.autocorrect.finishSuggestions(result).map { suggestion in
                // After-space predictions show (and insert) the host's auto-capitalization.
                var owned = ownership.token == nil ? self.casedPrediction(suggestion, before: ownership.context) : suggestion
                owned.ownership = ownership
                return owned
            }
            self.publishSuggestions(next, ownership: ownership, evidence: evidence, final: true)
        })
    }

    private func publishSuggestions(_ next: [KeyboardSuggestion], ownership: KeyboardSuggestionOwnership?,
                                    evidence: KeyboardTouchWord?, final: Bool) {
        published = ownership.map { PublishedStrip(ownership: $0, evidence: evidence, final: final) }
        guard next != suggestions else { return }
        suggestions = next
        onChange?()
    }

    /// Settings poll: learning loads/resets/switch, resource installation or a host context
    /// change without callback can make the shown chips unacceptable. Republish only then.
    func refreshSuggestionsIfStale() {
        guard suggestionsAreActive, let published,
              !published.ownership.hasSameContent(as: suggestionOwnership) else { return }
        refreshSuggestions()
    }

    func cancelSuggestions() {
        textRevision &+= 1
        suggestionWorker.cancel()
        publishSuggestions([], ownership: nil, evidence: nil, final: false)
    }

    func suspendSuggestions() {
        suggestionsAreActive = false
        cancelSuggestions()
    }

    /// Host activation or a keyboard touch: re-enable and refresh without touching layer, shift,
    /// undo, touches or menus (unlike `configureForField`).
    func resumeSuggestions() {
        suggestionsAreActive = true
        refreshSuggestions()
    }

    func waitForSuggestions() async { await suggestionWorker.waitUntilIdle() }

    func acceptSuggestion(_ suggestion: KeyboardSuggestion) {
        autocorrect.syncLearning()
        guard let ownership = suggestion.ownership,
              ownership.revision == textRevision, ownership == suggestionOwnership,
              showsStrip, field == .text, ownership.permitsCorrection else {
            // Refused (e.g. the sync above consumed a learning load/reset): replace the dead chips
            // so the next tap works. Bounded: one refresh, no re-entry into acceptance.
            refreshSuggestions()
            return
        }
        // Capture the word's taps before invalidating them: an explicit choice may teach Typr.
        let before = target.documentContextBeforeInput
        let evidence = autocorrect.touchInput.evidence(beforeInput: before)
        let token = AutocorrectEngine.currentToken(in: before)
        // Boundary chips own an exact bounded suffix, not just the current token. Ownership
        // above includes the entire captured context/revision; recheck the actual proxy suffix too.
        let original = suggestion.boundary?.original ?? token
        if suggestion.boundary != nil {
            guard let original, before?.hasSuffix(original) == true else { return }
        }
        let keepWasNew = token.map { !autocorrect.learning.protections.kept.contains(PersonalLexiconSnapshot.normalize($0)) } ?? false
        if let token {
            autocorrect.recordSuggestionFeedback(suggestion, literal: token, evidence: evidence)
        } else {
            // Prediction picks have no independently typed word: no unigram, label or pair.
            autocorrect.discardFeedback()
        }
        // Idempotent with the published chip: a prediction at a sentence start is capitalized.
        let replacement = token == nil && suggestion.boundary == nil
            ? casedPrediction(suggestion, before: before).replacement : suggestion.replacement
        invalidateTouchEvidence(resetFastAim: false)
        if let original {
            for _ in 0..<original.count {
                target.deleteBackward()
            }
        }
        autocorrect.clearPendingUndo()
        insert(replacement + " ", keepsFeedback: token != nil && suggestion.boundary == nil)
        if let boundary = suggestion.boundary {
            autocorrect.recordAppliedBoundary(boundary, replacement: suggestion.replacement)
        } else if suggestion.kind == .keepLiteral, let token {
            autocorrect.recordAppliedKeep(token, wasNew: keepWasNew)
        }
        // The suggestion's separator counts as the first space of double-space period.
        lastSpaceAt = clock()
    }

    /// Host auto-capitalization for a next-word prediction: first letter after `. ! ?`, a line
    /// break or at the field start (sentences/words modes), every letter for all-characters.
    /// Never lowercases, so dictionary-cased German nouns and names keep their capitals.
    static func casedPrediction(_ word: String, mode: AutoCapitalization.Mode, before: String?, hasText: Bool) -> String {
        guard AutoCapitalization.shouldCapitalize(mode: mode, before: before, hasText: hasText) else { return word }
        return mode == .allCharacters ? word.uppercased() : word.prefix(1).uppercased() + word.dropFirst()
    }

    private func casedPrediction(_ suggestion: KeyboardSuggestion, before: String?) -> KeyboardSuggestion {
        guard suggestion.boundary == nil else { return suggestion } // Owns an exact original suffix.
        let mode = AutoCapitalization.Mode(target.autocapitalizationType)
        let replacement = Self.casedPrediction(suggestion.replacement, mode: mode, before: before, hasText: target.hasText)
        guard replacement != suggestion.replacement else { return suggestion }
        var cased = KeyboardSuggestion(
            displayText: Self.casedPrediction(suggestion.displayText, mode: mode, before: before, hasText: target.hasText),
            replacement: replacement, kind: suggestion.kind, isCompletion: suggestion.isCompletion)
        cased.ownership = suggestion.ownership
        cased.isPersonal = suggestion.isPersonal
        return cased
    }

    // MARK: - Touches

    func touchBegan(id: Int, at point: CGPoint) {
        guard let key = layout.hitTest(point) else { return }
        // A touch proves the keyboard is visible, even if a host activation notice was missed.
        if !suggestionsAreActive { resumeSuggestions() }
        // Rollover: a new key going down commits any character or accent picker still held.
        for other in touchOrder {
            guard var touch = touches[other], touch.key.character != nil, !touch.committed else { continue }
            if activeAccentTouchID == other, let menu = activeAccentMenu {
                commitAccentSelection(menu.selectedOption)
                activeAccentMenu = nil
                activeAccentTouchID = nil
            } else {
                commitCharacter(touch)
            }
            touch.committed = true
            touches[other] = touch
        }

        var touch = ActiveTouch(
            key: key,
            startPoint: point,
            point: point,
            evidenceLayout: layout,
            committed: false,
            returnLayer: nil
        )
        switch key.kind {
        case .shift:
            shift.shiftDown(now: clock())
        case .delete:
            deleteBackward(allowAutocorrectUndo: true)
        case .layerSwitch(let next):
            touch.returnLayer = layerState.layer
            layerState.switchTo(next)
            if next == .letters { shift.reset() }
            rebuildLayout()
            if next == .letters { refreshAutoCapitalization() }
        case .character, .space, .returnKey, .typr, .globe:
            break
        }
        touches[id] = touch
        touchOrder.append(id)
        onChange?()
    }

    @discardableResult
    func openAccentMenuIfEligible(forTouch id: Int) -> Bool {
        guard activeAccentMenu == nil,
              let touch = touches[id],
              !touch.committed,
              let base = touch.key.character else { return false }
        let dx = touch.point.x - touch.startPoint.x
        let dy = touch.point.y - touch.startPoint.y
        guard (dx * dx + dy * dy).squareRoot() <= Self.accentSlop else { return false }
        guard let options = AccentCatalog.options(for: base, uppercase: isUppercase),
              options.count > 1 else { return false }
        activeAccentMenu = AccentMenu.build(
            for: touch.key.frame,
            rawOptions: options,
            in: layout.width,
            horizontalInset: layout.horizontalInset
        )
        activeAccentTouchID = id
        onChange?()
        return true
    }

    func touchMoved(id: Int, to point: CGPoint) {
        guard var touch = touches[id] else { return }
        touch.point = point

        // 1. Active long-press accent picker: horizontal drag selects the alternate character.
        if activeAccentTouchID == id, var menu = activeAccentMenu {
            let nextIndex = menu.index(for: point.x)
            touches[id] = touch
            if nextIndex != menu.selectedIndex {
                menu.selectedIndex = nextIndex
                activeAccentMenu = menu
                onSelectionStep?()
                onChange?()
            }
            return
        }

        // 2. Spacebar cursor trackpad: horizontal drag >= 10 pt slides the text caret.
        if touch.key.kind == .space {
            if !touch.isTrackpad, abs(point.x - touch.startPoint.x) >= Self.trackpadActivationDistance {
                discardTouchEvidence()
                touch.isTrackpad = true
                touch.trackpadAnchorX = point.x
                lastSpaceAt = nil
                autocorrect.clearPendingUndo()
                touches[id] = touch
                onSelectionStep?()
                onChange?()
                return
            }
            if touch.isTrackpad {
                let delta = point.x - touch.trackpadAnchorX
                let rawSteps = Int((delta / Self.trackpadPointsPerCharacter).rounded(.towardZero))
                if rawSteps != 0 {
                    touch.trackpadAnchorX += CGFloat(rawSteps) * Self.trackpadPointsPerCharacter
                    touches[id] = touch
                    target.adjustTextPosition(byCharacterOffset: rawSteps)
                    onSelectionStep?()
                    refreshAutoCapitalization()
                    refreshSuggestions()
                    return
                }
                touches[id] = touch
                return
            }
        }

        // 3. Sliding across character keys updates the active key and re-anchors the hold timer.
        if touch.key.character != nil, !touch.committed,
           let under = layout.hitTest(point), under.character != nil, under.kind != touch.key.kind {
            touch.hasUnambiguousPoint = false
            discardTouchEvidence()
            touch.key = under
            touch.startPoint = point
            touches[id] = touch
            onChange?()
            return
        }
        touches[id] = touch
    }

    func touchEnded(id: Int, at point: CGPoint) {
        guard var touch = touches.removeValue(forKey: id) else { return }
        touchOrder.removeAll { $0 == id }
        touch.point = point

        if activeAccentTouchID == id, let menu = activeAccentMenu {
            let index = menu.index(for: point.x)
            let chosen = menu.options[index]
            activeAccentMenu = nil
            activeAccentTouchID = nil
            if !touch.committed {
                commitAccentSelection(chosen)
            }
            onChange?()
            return
        }

        switch touch.key.kind {
        case .character:
            if !touch.committed {
                commitCharacter(touch)
            }
        case .shift:
            shift.shiftUp()
        case .space:
            if !touch.isTrackpad {
                typeSpace()
            }
        case .returnKey:
            if target.enablesReturnKeyAutomatically == true && !target.hasText {
                break
            }
            autocorrect.clearPendingUndo()
            // Return never autocorrects or settles learning.
            autocorrect.discardFeedback()
            insert("\n")
        case .layerSwitch:
            // Hold 123, slide to a key, let go: type it and go back.
            if let returnLayer = touch.returnLayer,
               let under = layout.hitTest(point),
               let character = under.character,
               under.kind != touch.key.kind {
                autocorrect.clearPendingUndo()
                typeCharacter(character)
                layerState.switchTo(returnLayer)
                rebuildLayout()
                refreshAutoCapitalization()
            }
        case .delete, .typr, .globe:
            break
        }
        onChange?()
    }

    func touchCancelled(id: Int) {
        discardTouchEvidence()
        if activeAccentTouchID == id {
            activeAccentMenu = nil
            activeAccentTouchID = nil
        }
        guard touches.removeValue(forKey: id) != nil else { return }
        touchOrder.removeAll { $0 == id }
        onChange?()
    }

    func cancelAllTouches() {
        cancelAllTouches(republishing: true)
    }

    private func cancelAllTouches(republishing: Bool) {
        if republishing { discardTouchEvidence() } else { invalidateTouchEvidence() }
        let hadTouches = !touches.isEmpty || activeAccentMenu != nil
        touches.removeAll()
        touchOrder.removeAll()
        activeAccentMenu = nil
        activeAccentTouchID = nil
        if shift.isHeld { shift.shiftUp() }
        if hadTouches { onChange?() }
    }

    // MARK: - Delete

    /// The delete key repeats after 360 ms, accelerates at 850 ms, and removes whole words after 1.4 s.
    static let repeatDelay: TimeInterval = 0.36
    static let repeatInterval: TimeInterval = 0.075
    static let fastRepeatAfter: TimeInterval = 0.85
    static let wordDeleteAfter: TimeInterval = 1.4

    func repeatDelete(heldFor: TimeInterval) {
        autocorrect.clearPendingUndo()
        if heldFor >= Self.wordDeleteAfter {
            deleteWordBackward()
        } else if heldFor >= Self.fastRepeatAfter {
            deleteBackward(allowAutocorrectUndo: false)
            deleteBackward(allowAutocorrectUndo: false)
        } else {
            deleteBackward(allowAutocorrectUndo: false)
        }
    }

    func deleteBackward(allowAutocorrectUndo: Bool = true) {
        autocorrect.syncLearning()
        let beforeDeletion = target.documentContextBeforeInput
        if allowAutocorrectUndo,
           let undo = autocorrect.consumePendingUndo(),
           let before = target.documentContextBeforeInput,
           before.hasSuffix(undo.insertedText) {
            for _ in 0..<undo.insertedText.count {
                target.deleteBackward()
            }
            target.insertText(undo.original)
            autocorrect.touchInput.clear()
            autocorrect.recordUndo(undo)
            autocorrect.touchInput.deletedBackward(before: nil, after: target.documentContextBeforeInput)
            lastSpaceAt = nil
            didEdit()
            return
        }
        autocorrect.clearPendingUndo()
        autocorrect.discardFeedback()
        target.deleteBackward()
        autocorrect.touchInput.deletedBackward(before: beforeDeletion, after: target.documentContextBeforeInput)
        lastSpaceAt = nil
        didEdit()
    }

    func deleteWordBackward() {
        autocorrect.discardFeedback()
        autocorrect.touchInput.clear()
        autocorrect.clearPendingUndo()
        guard let before = target.documentContextBeforeInput, !before.isEmpty else {
            deleteBackward(allowAutocorrectUndo: false)
            return
        }
        var count = 0
        var index = before.endIndex
        while index > before.startIndex, before[before.index(before: index)].isWhitespace {
            index = before.index(before: index)
            count += 1
        }
        while index > before.startIndex, !before[before.index(before: index)].isWhitespace {
            index = before.index(before: index)
            count += 1
        }
        for _ in 0..<max(1, count) {
            target.deleteBackward()
        }
        autocorrect.touchInput.deletedBackward(before: nil, after: target.documentContextBeforeInput)
        lastSpaceAt = nil
        didEdit()
    }

    // MARK: - Typing

    private func commitCharacter(_ touch: ActiveTouch) {
        let key = touch.key
        guard let character = key.character else { return }
        autocorrect.syncLearning()
        var attributed = key
        // Rollover commits previous letters first; their didEdit already prepared this map.
        // Unreported context/model/config changes or invalidated held geometry stay literal.
        if touch.hasUnambiguousPoint, touch.evidenceLayout == layout, !shift.isUppercase,
           let attribution, attribution.ownership == suggestionOwnership {
            attributed = attribution.map.attributedKey(
                at: touch.point, geometric: key, layout: layout,
                prefix: PersonalLexiconSnapshot.normalize(AutocorrectEngine.currentToken(
                    in: target.documentContextBeforeInput) ?? ""))
        }
        let inserted = attributed.character ?? character
        let text = layerState.layer == .letters && shift.isUppercase ? inserted.uppercased() : inserted
        if attributed != key { autocorrect.learning.increment(.reattributedTaps) }
        if layerState.layer == .letters {
            shift.didType()
        }
        autocorrect.clearPendingUndo()
        if touch.hasUnambiguousPoint, touch.evidenceLayout == layout {
            typeCharacter(text, sample: .init(text: text, point: touch.point, key: key,
                                              attributedKey: attributed == key ? nil : attributed))
        } else {
            typeCharacter(text)
        }
    }

    /// Sentence punctuation is a word boundary too, including hold-123/slide input.
    private func typeCharacter(_ text: String, sample: KeyboardTouchWord.Sample? = nil) {
        guard [".", ",", "?", "!"].contains(text), field == .text else {
            insert(text, sample: sample)
            return
        }
        let before = target.documentContextBeforeInput
        // Remove one word separator, never indentation, a newline or multiple spaces.
        if let before, before.hasSuffix(" "),
           let previous = before.dropLast().last, previous.isLetter || previous.isNumber {
            target.deleteBackward()
            // This word was already committed; do not reconsider an explicit choice.
            insert(text)
            return
        }
        if let (original, replacement) = autocorrect.replacementOnSpace(
            beforeInput: target.documentContextBeforeInput,
            field: field,
            autocorrectionType: target.autocorrectionType
        ) {
            for _ in 0..<original.count { target.deleteBackward() }
            target.insertText(replacement + text)
            autocorrect.recordAppliedCorrection(original: original, insertedText: replacement + text)
            autocorrect.discardFeedback()
            autocorrect.touchInput.clear()
            lastSpaceAt = nil
            layerState.didInsert(text)
            rebuildLayoutIfNeeded()
            didEdit()
        } else {
            insert(text)
        }
    }

    private func commitAccentSelection(_ chosen: String) {
        if layerState.layer == .letters {
            shift.didType()
        }
        autocorrect.clearPendingUndo()
        typeCharacter(chosen)
    }

    /// Typr: a tap on the Typr key types a space, exactly like the space bar
    /// (autocorrect, double-space period).
    func typeSpaceFromTyprKey() {
        typeSpace()
        onChange?()
    }

    private func typeSpace() {
        // Keep evidence through replacementOnSpace, then discard the completed word.
        _ = autocorrect.touchInput.evidence(beforeInput: target.documentContextBeforeInput)
        defer { autocorrect.touchInput.clear() }
        // Preserve the predecessor only for a new word's boundary, never a second separator.
        autocorrect.discardFeedback(preservingTrustedContext:
            AutocorrectEngine.currentToken(in: target.documentContextBeforeInput) != nil)
        let now = clock()
        if DoubleSpacePeriod.shouldReplace(before: target.documentContextBeforeInput, lastSpaceAt: lastSpaceAt, now: now) {
            autocorrect.clearPendingUndo()
            target.deleteBackward()
            target.insertText(". ")
            lastSpaceAt = nil
            layerState.didInsert(" ")
            rebuildLayoutIfNeeded()
            didEdit()
            return
        }
        if let (original, replacement) = autocorrect.replacementOnSpace(
            beforeInput: target.documentContextBeforeInput,
            field: field,
            autocorrectionType: target.autocorrectionType
        ) {
            for _ in 0..<original.count {
                target.deleteBackward()
            }
            let inserted = replacement + " "
            target.insertText(inserted)
            autocorrect.recordAppliedCorrection(original: original, insertedText: inserted)
            lastSpaceAt = now
            layerState.didInsert(" ")
            rebuildLayoutIfNeeded()
            didEdit()
            return
        }
        autocorrect.clearPendingUndo()
        insert(" ", keepsFeedback: true)
        lastSpaceAt = now
    }

    /// `keepsFeedback`: the boundary's own separator, which opened the pending word feedback.
    private func insert(_ text: String, sample: KeyboardTouchWord.Sample? = nil, keepsFeedback: Bool = false) {
        let before = target.documentContextBeforeInput
        target.insertText(text)
        if sample != nil, text.count == 1, text.first?.isLetter == true {
            autocorrect.settleFeedback(beforeInput: before, insertedLetter: text,
                                      afterInput: target.documentContextBeforeInput)
        } else if !keepsFeedback {
            autocorrect.discardFeedback()
        }
        if let sample {
            autocorrect.touchInput.append(text: text, point: sample.point, key: sample.key,
                                         layout: layout, before: before, after: target.documentContextBeforeInput,
                                         attributedKey: sample.attributedKey)
        } else {
            autocorrect.touchInput.clear()
        }
        lastSpaceAt = nil
        layerState.didInsert(text)
        rebuildLayoutIfNeeded()
        didEdit()
    }

    private func didEdit() {
        refreshAutoCapitalization()
        // Keyboard-originated edits (including the Typr key) also lift a stale suspension.
        suggestionsAreActive = true
        refreshSuggestions()
        onEdit?()
    }

    // MARK: - Layout

    private func rebuildLayoutIfNeeded() {
        if layout.layer != layerState.layer {
            rebuildLayout()
        }
    }

    private func rebuildLayout() {
        let previous = layout
        layout = KeyboardLayout(
            width: width,
            orientation: orientation,
            layer: layerState.layer,
            field: field,
            showsGlobe: showsGlobe,
            horizontalInset: horizontalInset,
            showsStrip: showsStrip
        )
        if layout != previous { discardTouchEvidence() }
    }
}
