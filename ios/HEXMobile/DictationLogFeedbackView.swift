import SwiftUI
import UIKit

struct DictationRatingButtons: View {
    let store: DictationLogStore
    let entry: DictationLogEntry
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Button { store.rate(entry.id, rating: "good") } label: {
                    Label(entry.rating == "good" ? "Good ✓" : "Good", systemImage: "hand.thumbsup")
                }
                Button { store.rate(entry.id, rating: "bad") } label: {
                    Label(entry.rating == "bad" ? "Problem ✓" : "Problem", systemImage: "hand.thumbsdown")
                }
            }.buttonStyle(.bordered).frame(minHeight: 44)
            Text("Rating: \(entry.rating ?? "unrated")").font(.caption)
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
        }.buttonStyle(.borderless)
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
            if let url = store.exportURL {
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
