import CoreGraphics

/// Ephemeral evidence for one completely observed word. Coordinates use the captured layout's
/// keyboard-view space (including the strip). Not Codable: never persisted, logged or exported.
nonisolated struct KeyboardTouchWord: Equatable, Sendable {
    struct Sample: Equatable, Sendable {
        let text: String
        let point: CGPoint
        let key: KeyboardKey
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
    private var previous: KeyboardTouchWord?
    private var space: KeyboardTouchWord.Sample?
    // Survives loss of all samples, so delete-all/retype cannot regain learning trust.
    private var editedWord = false
    var isLearningIntact: Bool { !editedWord }

    func clear() { word = nil; previous = nil; space = nil; editedWord = false }

    func boundaryEvidence(beforeInput: String?) -> KeyboardBoundaryTouch? {
        guard let current = evidence(beforeInput: beforeInput) else { return nil }
        var touch = KeyboardBoundaryTouch(current: current, previous: previous, space: space)
        if !touch.isUsable || beforeInput?.hasSuffix(touch.original) != true {
            previous = nil; space = nil
            touch = KeyboardBoundaryTouch(current: current)
        }
        return touch.isUsable ? touch : nil
    }

    func evidence(beforeInput: String?) -> KeyboardTouchWord? {
        guard let word else {
            if let previous, beforeInput?.hasSuffix(previous.text + " ") != true {
                self.previous = nil; space = nil
            }
            return nil
        }
        guard AutocorrectEngine.currentToken(in: beforeInput) == word.text else {
            self.word = nil
            previous = nil; space = nil
            return nil
        }
        return word
    }

    func append(text: String, point: CGPoint, key: KeyboardKey, layout: KeyboardLayout,
                before: String?, after: String?) {
        if text == " " {
            let completed = evidence(beforeInput: before)
            clear() // A second space never carries a window forward.
            if let before, after == before + " ", let completed, completed.learningIntact,
               completed.layout == layout, completed.samples.count < KeyboardBoundaryTouch.maxSamples,
               key.kind == .space, point.x.isFinite, point.y.isFinite {
                previous = completed
                space = .init(text: " ", point: point, key: key)
            }
            return
        }
        guard before != nil, text.count == 1, text.first?.isLetter == true,
              point.x.isFinite, point.y.isFinite, layout.layer == .letters,
              layout.field == .text, key.character?.lowercased() == text.lowercased(),
              AutocorrectEngine.currentToken(in: after) == (AutocorrectEngine.currentToken(in: before) ?? "") + text else {
            word = nil; previous = nil; space = nil
            return
        }
        if let token = AutocorrectEngine.currentToken(in: before) {
            guard let current = evidence(beforeInput: before), current.text == token,
                  current.layout == layout, current.samples.count < Self.maxSamples else {
                word = nil; previous = nil; space = nil
                return
            }
        } else {
            if let previous, before?.hasSuffix(previous.text + " ") != true || previous.layout != layout {
                self.previous = nil; space = nil
            }
            word = KeyboardTouchWord(layout: layout, samples: [], learningIntact: !editedWord)
        }
        word?.samples.append(.init(text: text, point: point, key: key))
        if (previous?.samples.count ?? 0) + (word?.samples.count ?? 0) + 1 > KeyboardBoundaryTouch.maxSamples {
            previous = nil; space = nil
        }
    }

    func deletedBackward(before: String?, after: String?) {
        let evidence = evidence(beforeInput: before)
        editedWord = true
        previous = nil; space = nil
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
