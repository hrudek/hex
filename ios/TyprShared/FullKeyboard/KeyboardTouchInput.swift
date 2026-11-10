import CoreGraphics

/// Ephemeral evidence for one completely observed word. Coordinates use the captured layout's
/// keyboard-view space (including the strip). Not Codable: never persisted, logged or exported.
nonisolated struct KeyboardTouchWord: Equatable {
    struct Sample: Equatable {
        let text: String
        let point: CGPoint
        let key: KeyboardKey
    }

    let layout: KeyboardLayout
    var samples: [Sample]
    var text: String { samples.map(\.text).joined() }
}

/// Keeps only a bounded, contiguous word whose characters all came from unambiguous key taps.
/// Missing context, a partial word or an edit we cannot align means spelling-only fallback.
@MainActor
final class KeyboardTouchInput {
    static let maxSamples = 64
    private var word: KeyboardTouchWord?

    func clear() { word = nil }

    func evidence(beforeInput: String?) -> KeyboardTouchWord? {
        guard let word, AutocorrectEngine.currentToken(in: beforeInput) == word.text else {
            clear()
            return nil
        }
        return word
    }

    func append(text: String, point: CGPoint, key: KeyboardKey, layout: KeyboardLayout,
                before: String?, after: String?) {
        guard before != nil, text.count == 1, text.first?.isLetter == true,
              point.x.isFinite, point.y.isFinite, layout.layer == .letters,
              layout.field == .text, key.character?.lowercased() == text.lowercased(),
              AutocorrectEngine.currentToken(in: after) == (AutocorrectEngine.currentToken(in: before) ?? "") + text else {
            clear()
            return
        }
        if let token = AutocorrectEngine.currentToken(in: before) {
            guard let current = evidence(beforeInput: before), current.text == token,
                  current.layout == layout, current.samples.count < Self.maxSamples else {
                clear()
                return
            }
        } else {
            word = KeyboardTouchWord(layout: layout, samples: [])
        }
        word?.samples.append(.init(text: text, point: point, key: key))
    }

    func deletedBackward(before: String?, after: String?) {
        guard var current = evidence(beforeInput: before) else { return }
        current.samples.removeLast()
        guard !current.samples.isEmpty,
              AutocorrectEngine.currentToken(in: after) == current.text else {
            clear()
            return
        }
        word = current
    }
}
