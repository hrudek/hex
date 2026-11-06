import UIKit

nonisolated struct LexiconEntry: Sendable, Equatable {
    let userInput: String
    let documentText: String
}

/// `requestSupplementaryLexicon` completes on a background queue. Under Swift 6 a closure
/// written inside a `@MainActor` class is inferred as main-actor isolated and traps there,
/// which killed the keyboard extension. Build the completion outside any actor instead.
nonisolated enum LexiconDelivery {
    static func handler(
        deliver: @escaping @MainActor @Sendable ([LexiconEntry]) -> Void
    ) -> @Sendable (UILexicon) -> Void {
        { lexicon in
            let entries = lexicon.entries.map {
                LexiconEntry(userInput: $0.userInput, documentText: $0.documentText)
            }
            hop(entries, to: deliver)
        }
    }

    static func hop(
        _ entries: [LexiconEntry],
        to deliver: @escaping @MainActor @Sendable ([LexiconEntry]) -> Void
    ) {
        DispatchQueue.main.async { MainActor.assumeIsolated { deliver(entries) } }
    }
}
