import SwiftUI

/// Sensitive saved words are loaded only on this explicitly opened page.
@MainActor
struct KeyboardLearnedWordsView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var state: PersonalTypingModel.State?
    @State private var error: String?
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
        return state
    }

    var body: some View {
        List {
            Section {
                Text("Only saved words and correction pairs are shown. No typed-text history, context or per-word dates. Swipe to delete an entry.")
                    .font(.footnote).foregroundStyle(.secondary)
                if let error { Text(error).foregroundStyle(.red) }
            }
            if let state {
                let kept = state.kept.keys.sorted()
                let pairs = state.rejected.sorted { ($0.typed, $0.replacement) < ($1.typed, $1.replacement) }
                let counts = state.counts.keys.sorted()
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
                if kept.isEmpty && pairs.isEmpty && counts.isEmpty {
                    Text("No saved words or corrections.").foregroundStyle(.secondary)
                }
            } else {
                Text("No saved learning available. Without Full Access, learning stays in the keyboard session and cannot be shown here. Full Access may be off, or nothing has been saved yet.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Manage learned words")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
        .refreshable { reload() }
        .onAppear {
            reload()
            if !fixture { observer = KeyboardLearningObserver { reload() } }
        }
        .onDisappear { observer?.invalidate(); observer = nil }
        .onChange(of: scenePhase) { _, phase in if phase == .active { reload() } }
    }

    private func reload() {
        state = fixture ? (state ?? Self.fixtureState()) : KeyboardLearningStore().learnedWords()
    }

    private func delete(_ entries: [KeyboardLearningStore.LearnedEntry]) {
        error = nil
        for entry in entries {
            if fixture {
                switch entry {
                case .kept(let word): state?.kept.removeValue(forKey: word)
                case .count(let word): state?.counts.removeValue(forKey: word)
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
