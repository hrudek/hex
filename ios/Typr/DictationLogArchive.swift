import Foundation

struct DictationLogMetadata: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var date: Date
    var status: DictationLogStatus
    var rating: String
    var issues: [String]
    var source: String
    var revision: Int
    var preview: String
    var bytes: Int
    var fileFingerprint: String?
    init(_ entry: DictationLogEntry, bytes: Int = 0) {
        id = entry.id; date = entry.context.createdAt; status = entry.status
        rating = entry.rating ?? "unrated"; issues = entry.issues ?? []
        source = entry.sourceLabel; revision = entry.revision ?? 1
        preview = String((entry.finalText?.text ?? entry.recognized?.text ?? status.label).prefix(120))
        self.bytes = bytes
    }
}

struct DictationArchiveLoad: Sendable {
    var archiveID: UUID
    var metadata: [DictationLogMetadata]
    var problem: Bool
}

struct DictationJSONEnvelope: Encodable {
    let format = "typr.dictation-log"
    let exportVersion = 1
    let exportedAt: Date
    let archiveID: UUID
    let appBuild: String
    let unreadableFiles: Int
    let legacyMigrationPending: Bool
    let dateEncoding = "ISO-8601 UTC"
    let evidenceLimits = "No audio. Final text is not proof of insertion. Human reference is intended final text, not ASR ground truth. Ratings are observational, not model evaluation."
}
