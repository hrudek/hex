import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct DictationLogExportMenu: View {
    let entries: [DictationLogEntry]

    var body: some View {
        Menu {
            ForEach(DictationLogExport.allCases) { format in
                Menu(format.label) {
                    Button("Copy") {
                        // Conscious export; allow Universal Clipboard, expire after five minutes.
                        UIPasteboard.general.setItems(
                            [[UTType.utf8PlainText.identifier: format.text(for: entries)]],
                            options: [.expirationDate: Date().addingTimeInterval(5 * 60)])
                    }
                    ShareLink(item: format.text(for: entries)) { Label("Share", systemImage: "square.and.arrow.up") }
                }
            }
        } label: {
            Label("Export \(entries.count) dictations", systemImage: "square.and.arrow.up")
        }
    }
}

struct DictationLogFeedbackEditor: View {
    let store: DictationLogStore
    let entry: DictationLogEntry
    @Environment(\.dismiss) private var dismiss
    @State private var desired: String
    @State private var note: String

    init(store: DictationLogStore, entry: DictationLogEntry) {
        self.store = store
        self.entry = entry
        // Never prefill with model output: that would turn an unreviewed answer into a label.
        _desired = State(initialValue: entry.expectedText?.text ?? "")
        _note = State(initialValue: entry.feedbackNote?.text ?? "")
    }

    private var withinLimit: Bool {
        desired.utf8.count <= DictationLogText.maximumBytes && note.utf8.count <= DictationLogText.maximumBytes
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Desired final text") {
                    TextEditor(text: $desired).frame(minHeight: 120)
                        .accessibilityLabel("Desired final text")
                    Text("Your reference for the intended result, not a second AI answer. Leave blank to remove the reference.")
                        .font(.footnote)
                }
                Section("What went wrong? (optional)") {
                    TextEditor(text: $note).frame(minHeight: 80)
                        .accessibilityLabel("Feedback note")
                }
                Section {
                    Text("Stored locally with this dictation; included in both export options. No automatic model training. Each field is limited to 4,000 UTF-8 bytes.")
                        .font(.footnote)
                    if !withinLimit { Text("Shorten the text before saving. The reference will not be silently truncated.").foregroundStyle(.red) }
                    if entry.expectedText?.truncated == true || entry.feedbackNote?.truncated == true {
                        Text("Previously saved feedback was truncated. Restore the complete reference before using it as a training example.")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Human reference")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.saveFeedback(for: entry.id, expectedText: desired, note: note)
                        dismiss()
                    }.disabled(!withinLimit || !store.entries.contains { $0.id == entry.id })
                }
            }
        }
    }
}
