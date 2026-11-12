import CoreGraphics

/// Ephemeral evidence for one completely observed word. Coordinates use the captured layout's
/// keyboard-view space (including the strip). Not Codable: never persisted, logged or exported.
nonisolated struct KeyboardTouchWord: Equatable, Sendable {
    struct Sample: Equatable, Sendable {
        let text: String
        let point: CGPoint
        /// Original geometric hit; never silently relabeled by the attribution map.
        let key: KeyboardKey
        var attributedKey: KeyboardKey? = nil
    }

    let layout: KeyboardLayout
    var samples: [Sample]
    /// Aligned edits may still decode, but deletion/retyping must never teach.
    var learningIntact = true
    var text: String { samples.map(\.text).joined() }
}

/// Keeps only a bounded, contiguous word whose characters all came from unambiguous key taps.
/// Missing context, a partial word or an edit we cannot align means spelling-only fallback.
@MainActor
final class KeyboardTouchInput {
    static let maxSamples = 64
    private var word: KeyboardTouchWord?
    // Survives loss of all samples, so delete-all/retype cannot regain learning trust.
    private var editedWord = false
    var isLearningIntact: Bool { !editedWord }
    // One RAM-only bit, independent of complete tap evidence (also covers partial words).
    // Backspacing is explicit disagreement: the rest of this word must stay geometric.
    private(set) var attributionSuppressed = false

    func clear() { word = nil; editedWord = false }

    func clearAtBoundary() {
        clear()
        attributionSuppressed = false
    }

    func evidence(beforeInput: String?) -> KeyboardTouchWord? {
        guard let word, AutocorrectEngine.currentToken(in: beforeInput) == word.text else {
            self.word = nil
            return nil
        }
        return word
    }

    func append(text: String, point: CGPoint, key: KeyboardKey, layout: KeyboardLayout,
                before: String?, after: String?, attributedKey: KeyboardKey? = nil) {
        if attributedKey != nil {
            // Disqualify even a partially observed word: a later keep must not count our guess.
            editedWord = true
            word?.learningIntact = false
        }
        guard before != nil, text.count == 1, text.first?.isLetter == true,
              point.x.isFinite, point.y.isFinite, layout.layer == .letters,
              layout.field == .text, (attributedKey ?? key).character?.lowercased() == text.lowercased(),
              AutocorrectEngine.currentToken(in: after) == (AutocorrectEngine.currentToken(in: before) ?? "") + text else {
            word = nil
            return
        }
        if let token = AutocorrectEngine.currentToken(in: before) {
            guard let current = evidence(beforeInput: before), current.text == token,
                  current.layout == layout, current.samples.count < Self.maxSamples else {
                word = nil
                return
            }
        } else {
            word = KeyboardTouchWord(layout: layout, samples: [], learningIntact: !editedWord)
        }
        word?.samples.append(.init(text: text, point: point, key: key, attributedKey: attributedKey))
    }

    func deletedBackward(before: String?, after: String?) {
        attributionSuppressed = true
        let evidence = evidence(beforeInput: before)
        editedWord = true
        guard var current = evidence else { return }
        current.learningIntact = false
        current.samples.removeLast()
        guard !current.samples.isEmpty,
              AutocorrectEngine.currentToken(in: after) == current.text else {
            word = nil
            return
        }
        word = current
    }
}
