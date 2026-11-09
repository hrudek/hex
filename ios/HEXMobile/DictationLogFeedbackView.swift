import SwiftUI
import UIKit

struct DictationRatingButtons: View {
    enum Mode { case all, rating, categories }
    let store: DictationLogStore
    let entry: DictationLogEntry
    var mode: Mode = .all
    var body: some View {
        VStack(alignment: .leading) {
            if mode != .categories {
                HStack {
                    Button { store.rate(entry.id, rating: "good") } label: {
                        Label(entry.rating == "good" ? "Good ✓" : "Good", systemImage: "hand.thumbsup")
                    }
                    Button { store.rate(entry.id, rating: "bad") } label: {
                        Label(entry.rating == "bad" ? "Problem ✓" : "Problem", systemImage: "hand.thumbsdown")
                    }
                }.buttonStyle(.bordered).frame(minHeight: 44)
                Text("Rating: \(entry.rating ?? "unrated")").font(.caption)
            }
            if mode != .rating {
                if entry.rating == "bad" {
                    ForEach(DictationIssue.choices, id: \.0) { code, title in
                        Button {
                            var issues = entry.issues ?? []
                            if issues.contains(code) { issues.removeAll { $0 == code } } else { issues.append(code) }
                            store.rate(entry.id, rating: "bad", issues: issues)
                        } label: {
                            Label(title, systemImage: entry.issues?.contains(code) == true ? "checkmark.circle.fill" : "circle")
                                .frame(minHeight: 44)
                        }.accessibilityLabel("\(title), \(entry.issues?.contains(code) == true ? "selected" : "not selected")")
                    }
                } else if mode == .categories {
                    Text("Categories are available after rating this dictation Problem.").font(.caption)
                }
                if !(entry.issues ?? []).isEmpty {
                    Text("Issues: \((entry.issues ?? []).joined(separator: ", "))").font(.caption)
                    Button("Clear issue categories") { store.rate(entry.id, rating: entry.rating ?? "unrated", issues: []) }
                        .frame(minHeight: 44)
                }
                if entry.rating != nil && entry.rating != "unrated" {
                    Button("Remove rating (keep reference and note)") { store.rate(entry.id, rating: "unrated") }
                        .frame(minHeight: 44)
                }
            }
        }.buttonStyle(.borderless)
    }
}

/// Hex+: one dictation text with an explicit Copy button, so it can be pasted into
/// "What I said" and corrected instead of retyped. Copying happens only on tap.
struct DictationCopyableTextSection: View {
    let title: String
    let field: DictationLogText?
    let accessibilityName: String
    var footer: String? = nil
    @State private var copied = false

    var body: some View {
        Section {
            if let field {
                Text(field.text.isEmpty ? "(empty)" : field.text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if field.truncated {
                    Text("TRUNCATED · original \(field.originalUTF8Bytes) UTF-8 bytes")
                        .font(.caption).foregroundStyle(HexTheme.textMuted)
                }
            } else {
                Text("Not recorded").foregroundStyle(HexTheme.textMuted)
            }
        } header: {
            HStack {
                Text(title)
                Spacer()
                if let field, !field.text.isEmpty {
                    Button {
                        UIPasteboard.general.string = field.text
                        copied = true
                        Task { try? await Task.sleep(for: .seconds(1.5)); copied = false }
                    } label: {
                        Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                            .font(.caption.weight(.medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .textCase(nil)
                    .accessibilityLabel(copied ? "Copied \(accessibilityName)" : "Copy \(accessibilityName)")
                }
            }
        } footer: {
            if let footer { Text(footer) }
        }
    }
}

/// Hex+: "What I said" — the human reference (`expectedText`), edited inline. Starts empty for a
/// new entry: model output never becomes a label without the owner pasting it on purpose.
/// Saving keeps the separate note untouched.
struct DictationReferenceEditor: View {
    let store: DictationLogStore
    let entry: DictationLogEntry
    var focusesOnAppear = false
    @State private var text: String
    @State private var saved: String
    @State private var didAutoFocus = false
    @FocusState private var focused: Bool

    init(store: DictationLogStore, entry: DictationLogEntry, focusesOnAppear: Bool = false) {
        self.store = store
        self.entry = entry
        self.focusesOnAppear = focusesOnAppear
        let current = entry.expectedText?.text ?? ""
        _text = State(initialValue: current)
        _saved = State(initialValue: current)
    }

    private var dirty: Bool { text != saved }
    private var withinLimit: Bool { text.utf8.count <= DictationLogText.maximumBytes }

    var body: some View {
        Section {
            TextEditor(text: $text)
                .frame(minHeight: 110)
                .focused($focused)
                .accessibilityLabel("What I said")
            HStack {
                Button(dirty ? "Save" : "Saved") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!dirty || !withinLimit)
                if dirty { Text("Not saved yet").font(.caption).foregroundStyle(HexTheme.textMuted) }
                Spacer()
                if focused {
                    Button("Done") { focused = false; if dirty && withinLimit { save() } }
                }
            }
            if !withinLimit {
                Text("Too long: limit is 4,000 UTF-8 bytes. The text will not be truncated silently.")
                    .font(.footnote).foregroundStyle(.red)
            }
            if entry.expectedText?.truncated == true {
                Text("The saved text was truncated. Restore the complete text before using it as a reference.")
                    .font(.footnote).foregroundStyle(.red)
            }
        } header: {
            Text("What I said / expected")
        } footer: {
            Text("Copy a text above, paste it here and correct it to what you actually said or expected. Stored only on this iPhone and included in exports.")
        }
        .onAppear {
            // One-shot: a List re-fires onAppear when the section scrolls back into view.
            guard focusesOnAppear, !didAutoFocus else { return }
            didAutoFocus = true
            Task { try? await Task.sleep(for: .milliseconds(450)); focused = true }
        }
        .onChange(of: entry.expectedText?.text) { _, newValue in
            // Another editor saved: follow it unless there are unsaved edits here.
            let value = newValue ?? ""
            if !dirty { text = value }
            saved = value
        }
        .onDisappear { if dirty && withinLimit { save() } }
    }

    private func save() {
        guard withinLimit else { return }
        store.saveFeedback(for: entry.id, expectedText: text, note: nil)
        saved = text
    }
}

struct DictationJSONExportMenu: View {
    let store: DictationLogStore
    var ids: [UUID]? = nil
    @State private var sharing = false
    @State private var sharedURL: URL?
    var body: some View {
        Menu {
            Text("Private text and vocabulary. Only share with a trusted recipient.")
            Button(ids == nil ? "Prepare JSON — entire archive" : "Prepare JSON — this entry") { store.prepareJSON(ids: ids) }
                .disabled(store.exporting || store.isLoading)
            if store.exporting { Text("Preparing JSON…") }
            if let problem = store.exportProblem { Text(problem) }
            if let url = store.preparedJSON(for: ids) {
                Button { sharedURL = url; sharing = true } label: { Label("Share prepared JSON", systemImage: "square.and.arrow.up") }
            }
        } label: { Label(store.exporting ? "Preparing JSON…" : "JSON", systemImage: "doc") }
        .sheet(isPresented: $sharing, onDismiss: {
            if let sharedURL { store.releaseJSON(sharedURL) }
            sharedURL = nil
        }) {
            if let sharedURL { DictationJSONShareSheet(url: sharedURL, completion: { sharing = false }) }
        }
    }
}

private struct DictationJSONShareSheet: UIViewControllerRepresentable {
    let url: URL
    let completion: @MainActor @Sendable () -> Void
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        let finished = completion
        controller.completionWithItemsHandler = { _, _, _, _ in
            Task { @MainActor in finished() }
        }
        return controller
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
