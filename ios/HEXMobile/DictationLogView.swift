import Foundation
import SwiftUI

extension DictationLogEntry {
    /// The UI and conscious exports use the same facts. No export includes prompts,
    /// audio, device names or error descriptions. Text and vocabulary may be private.
    var aiPathLabel: String {
        switch context.cleanupPath {
        case .hexPlus: "AI: Hex+"
        case .upstream: "AI: Upstream"
        case .none: "AI: None"
        }
    }

    var vocabularyLabel: String {
        switch context.vocabularyEnabled {
        case true?: "Vocabulary: On (\(context.vocabularyCount) terms)"
        case false?: "Vocabulary: Off"
        case nil: "Vocabulary: Not recorded (\(context.vocabularyCount) active terms)"
        }
    }

    var processingResultLabel: String {
        let ai = context.cleanupPath == .upstream
            ? "Upstream: \(upstreamOutcome ?? "pending / not run")"
            : (context.cleanupPath == .hexPlus ? "Hex+: \(cleanupOutcome ?? "pending / not run")" : "No AI pass")
        let spelling: String
        if let first = firstSpellingPass, let second = secondSpellingPass {
            spelling = "Vocabulary: \(first.totalChanges + second.totalChanges) replacements"
        } else {
            spelling = "Vocabulary changes: \(firstSpellingChanged || secondSpellingChanged ? "yes" : "none recorded")"
        }
        return "\(ai) · \(spelling)"
    }

    var settingsLines: [String] {
        func state(_ value: Bool?) -> String { value.map { $0 ? "On" : "Off" } ?? "Not recorded" }
        return [aiPathLabel + " (selected path; not proof of a model call)",
                "Hex+ AI setting: \(state(context.hexPlusCleanupEnabled))",
                "Upstream AI setting: \(state(context.upstreamCleanupEnabled)) (overridden while Hex+ is on)",
                vocabularyLabel, "Style: \(context.style)"]
    }

    func spellingLines(_ pass: DictationLogSpellingPass?) -> [String] {
        guard let pass else { return ["Replacement details not recorded (older entry or pass not reached)."] }
        guard pass.totalChanges > 0 else { return ["No replacements."] }
        var lines = pass.changes.map { change in
            "\(String(reflecting: change.before.text)) → \(String(reflecting: change.after.text)) (term: \(String(reflecting: change.term.text)))\(change.before.truncated || change.after.truncated || change.term.truncated ? " [truncated]" : "")"
        }
        if pass.totalChanges > pass.changes.count {
            lines.append("\(pass.totalChanges - pass.changes.count) more replacements not retained (limit: \(DictationLogSpellingPass.maximumReplacements) per pass).")
        }
        return lines
    }

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
            settingsLines.joined(separator: "\n"),
            processingResultLabel,
            "First spelling pass changed text: \(flag(firstSpellingChanged))",
            "Second spelling pass changed text: \(flag(secondSpellingChanged))"
        ]
    }

    var plainText: String {
        var sections = ["Hex+ dictation log", detailLines.joined(separator: "\n")]
        for (title, field) in [("Recognized", recognized), ("AI input (after spelling)", aiInput),
                               ("AI answer — \(answerLabel)", aiAnswer),
                               ("Cleanup output actually used", cleanupOutput),
                               ("After style formatting", formattedText), ("Final text provided", finalText),
                               ("Desired final text (human reference)", expectedText), ("Human feedback", feedbackNote),
                               ("Active vocabulary", context.vocabularySnapshot)] {
            guard let field else { continue }
            sections.append("\(title) (\(field.wordCount) words; \(field.originalUTF8Bytes) original UTF-8 bytes\(field.truncated ? "; truncated" : "")):\n\(field.text)")
        }
        if aiInput == nil, recognized != nil {
            sections.append("AI input is the recognized text (first spelling pass unchanged).")
        }
        if let upstreamReason { sections.append("Upstream detail: \(upstreamReason)") }
        sections.append("Vocabulary replacements before AI:\n" + spellingLines(firstSpellingPass).joined(separator: "\n"))
        sections.append("Vocabulary replacements after formatting:\n" + spellingLines(secondSpellingPass).joined(separator: "\n"))
        sections.append("Vocabulary hints during speech recognition are best effort; individual word changes cannot be attributed to them. Replacement counts are not quality scores.")
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
                    Text("Private text history on this iPhone only. No time-based expiry. Turning off Dictation log deletes it. Exports can include dictated text, model answers, active vocabulary and human feedback.")
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
                            Text(entry.aiPathLabel + " · " + entry.context.style)
                                .font(.subheadline.weight(.semibold))
                            Text(entry.vocabularyLabel).font(.caption)
                            Text(entry.processingResultLabel).font(.caption).foregroundStyle(HexTheme.textMuted)
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
                    DictationLogExportMenu(entries: store.entries)
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
    @State private var editingFeedback = false

    private var entry: DictationLogEntry? { store.entries.first { $0.id == entryID } }

    var body: some View {
        Group {
            if let entry {
                List {
                    Section("Recognition & cleanup") {
                        ForEach(entry.improvementLines, id: \.self) { Text($0).font(.subheadline).textSelection(.enabled) }
                    }
                    textSection("Recognized (raw speech recognition)", field: entry.recognized)
                    textSection("Cleanup input (after vocabulary)", field: entry.aiInput ?? entry.recognized,
                        comparedTo: entry.recognized)
                    textSection("AI answer — \(entry.answerLabel)", field: entry.aiAnswer,
                        comparedTo: entry.aiInput ?? entry.recognized)
                    textSection("Cleanup output actually used", field: entry.cleanupOutput,
                        comparedTo: entry.aiAnswer ?? entry.aiInput ?? entry.recognized)
                    textSection("After style formatting", field: entry.formattedText, comparedTo: entry.cleanupOutput)
                    textSection("Final text provided", field: entry.finalText, comparedTo: entry.formattedText)
                    Section("Human reference") {
                        Text(entry.expectedText?.text ?? "No desired text supplied yet. Without a reference, this is diagnostic evidence, not a labelled training example.")
                            .textSelection(.enabled)
                        if let note = entry.feedbackNote { Text(note.text).textSelection(.enabled) }
                        if entry.expectedText?.truncated == true || entry.feedbackNote?.truncated == true {
                            Text("Human reference or feedback is TRUNCATED. Do not use as a complete training label.")
                                .font(.footnote).foregroundStyle(.red)
                        }
                        Button("Edit desired text & feedback") { editingFeedback = true }
                        Text("Enter the intended final text, including intended names and self-corrections. Optional note: what was wrong? Saving does not train or change a model.")
                            .font(.footnote).foregroundStyle(HexTheme.textMuted)
                    }
                    vocabularySection("Vocabulary before cleanup", entry: entry, pass: entry.firstSpellingPass)
                    vocabularySection("Vocabulary after formatting", entry: entry, pass: entry.secondSpellingPass)
                    if let input = entry.aiInput ?? entry.recognized, let answer = entry.aiAnswer {
                        DictationLogDiff(title: "AI input → AI answer", before: input, after: answer)
                    }
                    if let input = entry.recognized, let final = entry.finalText {
                        DictationLogDiff(title: "Recognized → Final", before: input, after: final)
                    }
                    Section {
                        DisclosureGroup("Technical diagnostics") {
                            ForEach(Array(entry.detailLines.enumerated()), id: \.offset) { _, line in
                                Text(line).font(.footnote).textSelection(.enabled)
                            }
                        }
                    }
                    Section {
                        Text(DictationLogExport.limitations).font(.footnote)
                    }
                }
                .toolbar { DictationLogExportMenu(entries: [entry]) }
                .sheet(isPresented: $editingFeedback) {
                    DictationLogFeedbackEditor(store: store, entry: entry)
                }
            } else {
                ContentUnavailableView("Entry no longer available", systemImage: "text.badge.minus",
                    description: Text("It was cleared, logging was turned off, or newer dictations replaced it."))
            }
        }
        .navigationTitle("Dictation details")
    }

    @ViewBuilder
    private func vocabularySection(_ title: String, entry: DictationLogEntry, pass: DictationLogSpellingPass?) -> some View {
        if pass?.totalChanges != 0 {
            Section(title) {
                ForEach(Array(entry.spellingLines(pass).enumerated()), id: \.offset) { _, line in
                    Text(line).textSelection(.enabled)
                }
            }
        }
    }

    private func textSection(_ title: String, field: DictationLogText?, comparedTo previous: DictationLogText? = nil) -> some View {
        Section(title) {
            if let field {
                if let previous, !field.truncated, !previous.truncated, field.text == previous.text {
                    DisclosureGroup("Unchanged (show text)") {
                        Text(field.text.isEmpty ? "(empty)" : field.text).textSelection(.enabled)
                    }
                } else {
                    Text(field.text.isEmpty ? "(empty)" : field.text).textSelection(.enabled)
                }
                if field.truncated {
                    Text("TRUNCATED · original \(field.originalUTF8Bytes) UTF-8 bytes")
                        .font(.caption).foregroundStyle(HexTheme.textMuted)
                }
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
