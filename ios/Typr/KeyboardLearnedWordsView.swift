import SwiftUI

/// Sensitive saved words are loaded only on this explicitly opened page.
@MainActor
struct KeyboardLearnedWordsView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var state: PersonalTypingModel.State?
    @State private var error: String?
    @State private var searchText = ""
    @State private var observer: KeyboardLearningObserver?
    private let fixture: Bool

    init(fixture: Bool = KeyboardLearnedWordsView.isFixtureRequested) {
        self.fixture = fixture
    }

    static var isFixtureRequested: Bool {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "--snap-state"), index + 1 < args.count else { return false }
        return args[index + 1] == "settings-keyboard-learned-words"
    }

    static func fixtureState() -> PersonalTypingModel.State {
        var state = PersonalTypingModel.State()
        state.kept = ["typr": KeyboardDiagnosticsFixture.now, "swift": KeyboardDiagnosticsFixture.now]
        state.rejected = [.init(typed: "teh", replacement: "the")]
        state.counts = ["hello": .init(count: 12, lastUpdated: KeyboardDiagnosticsFixture.now)]
        for _ in 0..<3 { state.bigrams?.record("world", after: "hello") }
        return state
    }

    var body: some View {
        List {
            Section {
                Text("Typr stores kept words, word counts, rejected corrections and which word followed which. Word pairs only: no sentences, apps or websites, and no typed-text history or per-word dates. Deleting a word here removes every pair containing it; Reset learning in Typing diagnostics clears all pairs. Swipe to delete an entry.")
                    .font(.footnote).foregroundStyle(.secondary)
                if let error { Text(error).foregroundStyle(.red) }
            }
            if let state {
                let results = SearchResults(state: state, query: searchText)
                let kept = results.kept
                let pairs = results.pairs
                let counts = results.counts
                Section("Kept words") {
                    ForEach(kept, id: \.self) { Text($0) }
                        .onDelete { offsets in delete(offsets.map { .kept(kept[$0]) }) }
                }
                Section("Rejected corrections") {
                    ForEach(pairs, id: \.self) { Text("\($0.typed) → \($0.replacement)") }
                        .onDelete { offsets in delete(offsets.map { .rejected(pairs[$0]) }) }
                }
                Section("Frequent words") {
                    ForEach(counts, id: \.self) { word in
                        HStack { Text(word); Spacer(); Text("\(state.counts[word]?.count ?? 0)").foregroundStyle(.secondary) }
                    }
                    .onDelete { offsets in delete(offsets.map { .count(counts[$0]) }) }
                }
                Section("Words in next-word pairs") {
                    ForEach(results.pairWords, id: \.self) { Text($0) }
                        .onDelete { offsets in delete(offsets.map { .pairWord(results.pairWords[$0]) }) }
                }
                if kept.isEmpty && pairs.isEmpty && counts.isEmpty && results.pairWords.isEmpty {
                    Text(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                         ? "No saved words or corrections."
                         : "No matching words or corrections.")
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("No saved learning available. Without Full Access, learning stays in the keyboard session and cannot be shown here. Full Access may be off, or nothing has been saved yet.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Manage learned words")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Search words and corrections")
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        .toolbar { EditButton() }
        .refreshable { reload() }
        .onAppear {
            reload()
            if !fixture { observer = KeyboardLearningObserver { reload() } }
        }
        .onDisappear { observer?.invalidate(); observer = nil }
        .onChange(of: scenePhase) { _, phase in if phase == .active { reload() } }
    }

    /// Filtering never changes saved learning; deletion uses these same visible arrays.
    struct SearchResults {
        let kept: [String]
        let pairs: [RejectedCorrection]
        let counts: [String]
        let pairWords: [String]

        init(state: PersonalTypingModel.State, query: String) {
            let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
            func matches(_ word: String) -> Bool {
                query.isEmpty || word.localizedStandardContains(query)
            }
            kept = state.kept.keys.filter { matches($0) }.sorted()
            pairs = state.rejected.filter { matches($0.typed) || matches($0.replacement) }
                .sorted { ($0.typed, $0.replacement) < ($1.typed, $1.replacement) }
            counts = state.counts.keys.filter { matches($0) }.sorted()
            pairWords = (state.bigrams?.words ?? []).filter { matches($0) }.sorted()
        }
    }

    private func reload() {
        state = fixture ? (state ?? Self.fixtureState()) : KeyboardLearningStore().learnedWords()
    }

    private func delete(_ entries: [KeyboardLearningStore.LearnedEntry]) {
        error = nil
        for entry in entries {
            if fixture {
                switch entry {
                case .kept(let word):
                    state?.kept.removeValue(forKey: word)
                    state?.bigrams?.purge(word)
                case .count(let word):
                    state?.counts.removeValue(forKey: word)
                    state?.bigrams?.purge(word)
                case .pairWord(let word): state?.bigrams?.purge(word)
                case .rejected(let pair): state?.rejected.removeAll { $0 == pair }
                }
            } else if !KeyboardLearningStore().deleteLearnedEntry(entry) {
                error = "Could not delete the saved entry. Try again."
                break
            }
        }
        reload()
    }
}
