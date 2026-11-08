import Foundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

extension DictationLogEntry {
    /// The UI and conscious exports use the same facts. No export includes prompts, vocabulary
    /// lists, audio, device names or error descriptions. Text fields may contain private speech.
    var detailLines: [String] {
        func ms(_ value: Int64?) -> String { value.map { "\($0) ms" } ?? "not recorded" }
        func flag(_ value: Bool?) -> String { value.map { $0 ? "yes" : "no" } ?? "not recorded" }
        return [
            "ID: \(id.uuidString)", "Schema: \(schemaVersion)",
            "Created: \(context.createdAt.formatted(date: .numeric, time: .standard))",
            "Status: \(status.label)",
            "ASR error: \(asrFailure?.rawValue ?? "none")\(asrErrorType.map { " (\($0))" } ?? "")",
            "App: \(context.appVersion) (\(context.appBuild)); iOS \(context.systemVersion)",
            "Source: \(sourceLabel); keyboard job: \(flag(context.keyboardJob))",
            "Copy requested: \(flag(context.copyToPasteboard))",
            "Outputs: \(status == .finished ? outputLabel : "no final text provided")",
            "Style: \(context.style)", "Speech engine: \(context.speechEngine)",
            "Speech language: \(context.speechLanguage)",
            String(format: "Recording duration: %.2f s", context.recordingDuration),
            "Audio input port types: \(context.inputPortTypes.joined(separator: ", "))",
            "Bluetooth input: \(flag(context.bluetoothInput))",
            "Loudest average level, dBFS: \(context.loudestAverageDBFS.map { String(format: "%.1f", $0) } ?? "not sampled")",
            "ASR: \(ms(asrMilliseconds))", "Cleanup resolution: \(ms(cleanupMilliseconds))",
            "Model: \(ms(modelMilliseconds))", "Stop → final text provided: \(ms(stopToFinalMilliseconds))",
            "Cleanup path: \(context.cleanupPath.rawValue)",
            "Hex+ outcome: \(cleanupOutcome ?? "not recorded")",
            "\(cleanupSummary ?? "No Hex+ cleanup outcome")",
            "Cleanup changed: \(flag(cleanupChanged)); pipeline changed: \(flag(pipelineChanged))",
            "Model answer: \(answerLabel)", "Upstream cleanup: \(upstreamOutcome ?? "not used")",
            "Hex+ prompt revision: \(promptRevision); Hex+ guard revision: \(guardRevision)",
            "Active vocabulary terms: \(context.vocabularyCount)",
            "First spelling pass changed text: \(flag(firstSpellingChanged))",
            "Second spelling pass changed text: \(flag(secondSpellingChanged))"
        ]
    }

    var plainText: String {
        var sections = ["Hex+ dictation log", detailLines.joined(separator: "\n")]
        for (title, field) in [("Recognized", recognized), ("AI input (after spelling)", aiInput),
                               ("AI answer — \(answerLabel)", aiAnswer), ("Final text provided", finalText)] {
            guard let field else { continue }
            sections.append("\(title) (\(field.wordCount) words; \(field.originalUTF8Bytes) original UTF-8 bytes\(field.truncated ? "; truncated" : "")):\n\(field.text)")
        }
        if aiInput == nil, recognized != nil {
            sections.append("AI input is the recognized text (first spelling pass unchanged).")
        }
        sections.append("Provided to keyboard does not prove insertion. The keyboard may adjust spacing.")
        return sections.joined(separator: "\n\n")
    }
}

struct DictationLogView: View {
    let store: DictationLogStore
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingClear = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Private text history on this iPhone only. No time-based expiry. Turning off Dictation log deletes it. Sharing exports dictated and model text.")
                        .font(.footnote)
                    Text("Provided to keyboard is not proof of insertion; the keyboard may adjust spacing.")
                        .font(.footnote)
                    if let problem = store.storageProblem { Text(problem).foregroundStyle(HexTheme.textMuted) }
                }
                if store.entries.isEmpty { Text("No dictations logged yet") }
                ForEach(store.entries) { entry in
                    NavigationLink(value: entry.id) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(entry.context.createdAt.formatted(date: .omitted, time: .shortened)) · \(String(format: "%.1f s", entry.context.recordingDuration)) · \(entry.sourceLabel)")
                                .font(.subheadline)
                            Text(entry.status.label)
                                .font(.caption)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(HexTheme.bgBase, in: Capsule())
                            if let outcome = entry.cleanupSummary { Text(outcome).font(.caption).foregroundStyle(HexTheme.textMuted) }
                            Text(entry.finalText?.text.components(separatedBy: .newlines).first ?? entry.status.label)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .navigationTitle("Dictation log")
            .navigationDestination(for: UUID.self) { id in
                DictationLogDetail(store: store, entryID: id)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItemGroup(placement: .primaryAction) {
                    ShareLink(item: store.entries.map(\.plainText).joined(separator: "\n\n────────\n\n")) {
                        Label("Share all \(store.entries.count) dictations", systemImage: "square.and.arrow.up")
                    }
                    .disabled(store.entries.isEmpty)
                    Button("Clear", role: .destructive) { confirmingClear = true }
                        .disabled(store.entries.isEmpty && store.storageProblem == nil)
                }
            }
            .confirmationDialog("Delete all dictation log text?", isPresented: $confirmingClear, titleVisibility: .visible) {
                Button("Delete log", role: .destructive) { store.clear() }
            }
        }
    }
}

private struct DictationLogDetail: View {
    let store: DictationLogStore
    let entryID: UUID

    private var entry: DictationLogEntry? { store.entries.first { $0.id == entryID } }

    var body: some View {
        Group {
            if let entry {
                List {
                    textSection("Recognized (raw speech recognition)", field: entry.recognized)
                    textSection("AI input (after spelling)", field: entry.aiInput ?? entry.recognized)
                    textSection("AI answer — \(entry.answerLabel)", field: entry.aiAnswer)
                    textSection("Final text provided", field: entry.finalText)
                    if let input = entry.aiInput ?? entry.recognized, let answer = entry.aiAnswer {
                        DictationLogDiff(title: "AI input → AI answer", before: input, after: answer)
                    }
                    if let input = entry.recognized, let final = entry.finalText {
                        DictationLogDiff(title: "Recognized → Final", before: input, after: final)
                    }
                    Section("Details") {
                        ForEach(Array(entry.detailLines.enumerated()), id: \.offset) { _, line in
                            Text(line).font(.footnote).textSelection(.enabled)
                        }
                    }
                    Section {
                        Text("Provided to keyboard is not proof of insertion. The keyboard may adjust spacing. A late or rejected answer was not used.")
                            .font(.footnote)
                    }
                }
                .toolbar {
                    Button("Copy", systemImage: "doc.on.doc") {
                        // A conscious export; Universal Clipboard is intentionally allowed.
                        UIPasteboard.general.setItems([[UTType.utf8PlainText.identifier: entry.plainText]],
                            options: [.expirationDate: Date().addingTimeInterval(5 * 60)])
                    }
                }
            } else {
                ContentUnavailableView("Entry no longer available", systemImage: "text.badge.minus",
                    description: Text("It was cleared, logging was turned off, or newer dictations replaced it."))
            }
        }
        .navigationTitle("Dictation details")
    }

    private func textSection(_ title: String, field: DictationLogText?) -> some View {
        Section(title) {
            if let field {
                Text(field.text.isEmpty ? "(empty)" : field.text).textSelection(.enabled)
                Text("\(field.wordCount) words · \(field.originalUTF8Bytes) original UTF-8 bytes\(field.truncated ? " · truncated" : "")")
                    .font(.caption).foregroundStyle(HexTheme.textMuted)
            } else {
                Text("Not recorded").foregroundStyle(HexTheme.textMuted)
            }
        }
    }
}

private struct DictationLogDiff: View {
    let title: String
    let before: DictationLogText
    let after: DictationLogText
    @State private var expanded = false

    var body: some View {
        Section {
            DisclosureGroup(title, isExpanded: $expanded) {
                if expanded {
                    if before.truncated || after.truncated { Text("Comparison uses truncated text.").font(.caption) }
                    switch WordDiff.compute(before.text, after.text) {
                    case .tooLong:
                        Text("Too long to compare (limit: 400 tokens per side). Both texts are shown above.")
                    case .compared(let parts):
                        parts.reduce(Text("")) { result, part in
                            let visible = part.text.replacingOccurrences(of: "\n", with: "↵\n")
                            switch part.kind {
                            case .unchanged: return result + Text(visible)
                            case .removed: return result + Text(visible).strikethrough()
                            case .added: return result + Text(visible).bold().underline()
                            }
                        }
                        .textSelection(.enabled)
                        Text("Removed: strikethrough · Added: bold and underlined · ↵: line break")
                            .font(.caption).foregroundStyle(HexTheme.textMuted)
                    }
                }
            }
        }
    }
}
