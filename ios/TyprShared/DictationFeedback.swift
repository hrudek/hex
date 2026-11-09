import Foundation

/// Feedback fields are strings so a newer client's codes survive older clients.
struct DictationFeedbackOrder: Codable, Equatable, Comparable, Sendable {
    var modifiedAt: Date
    var origin: String
    var eventID: String
    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.modifiedAt != rhs.modifiedAt { return lhs.modifiedAt < rhs.modifiedAt }
        if lhs.origin != rhs.origin { return lhs.origin < rhs.origin }
        return lhs.eventID < rhs.eventID
    }
    static func app() -> Self { Self(modifiedAt: Date(), origin: "app", eventID: UUID().uuidString) }
}

enum DictationIssue {
    static let choices: [(String, String)] = [
        ("misheard", "Misheard"), ("missing_or_shortened", "Missing or shortened"),
        ("unwanted_rewrite", "Unwanted rewrite"), ("punctuation_formatting", "Punctuation / formatting"),
        ("vocabulary_name", "Vocabulary / name"), ("too_slow", "Too slow"), ("other", "Other")
    ]
}

struct DictationFeedbackPermission: Codable, Equatable, Sendable {
    let archiveID: UUID
    let generation: UUID
    let enabled: Bool
}

struct DictationFeedbackOffer: Codable, Equatable, Sendable {
    let resultID: String
    let jobID: String
    let entryID: UUID
    let archiveID: UUID
    let generation: UUID
    let expiresAt: Date
}

struct DictationFeedbackEvent: Codable, Equatable, Sendable {
    var schemaVersion = 1
    let eventID: UUID
    let offer: DictationFeedbackOffer
    let rating: String
    /// nil preserves categories; a category event carries the entire selected set.
    let issues: [String]?
    let createdAt: Date
    var order: DictationFeedbackOrder {
        .init(modifiedAt: createdAt, origin: "keyboard", eventID: eventID.uuidString)
    }
    func isValid(at now: Date) -> Bool {
        schemaVersion == 1 && ["good", "bad"].contains(rating)
            && UUID(uuidString: offer.jobID) != nil && UUID(uuidString: offer.resultID) != nil
            && createdAt <= offer.expiresAt && createdAt <= now.addingTimeInterval(60)
            && now.timeIntervalSince(createdAt) <= 30 * 24 * 60 * 60
            && (issues ?? []).count <= DictationIssue.choices.count
            && (issues ?? []).allSatisfy { code in DictationIssue.choices.contains { $0.0 == code } }
    }
}

struct DictationFeedbackPresentation: Equatable, Sendable {
    let offer: DictationFeedbackOffer
    var rating: String?
    var issues: [String] = []
    var message: String?
    var retryRating: String? = nil
    var retryIssues: [String]? = nil
    static func inserted(offer: DictationFeedbackOffer?, resultID: String, ownedJobs: Set<String>,
                         permission: DictationFeedbackPermission?, now: Date) -> Self? {
        guard let offer, let permission, permission.enabled,
              offer.resultID == resultID, ownedJobs.contains(offer.jobID),
              offer.archiveID == permission.archiveID, offer.generation == permission.generation,
              now <= offer.expiresAt else { return nil }
        return Self(offer: offer)
    }
}
