import Foundation

extension DictationFeedbackPresentation {
    /// Synthetic, no bridge writes or production archive access.
    static func snapshotFixture(problem: Bool = false) -> Self {
        let offer = DictationFeedbackOffer(resultID: "11111111-1111-1111-1111-111111111111",
            jobID: "22222222-2222-2222-2222-222222222222",
            entryID: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            archiveID: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
            generation: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,
            expiresAt: Date(timeIntervalSince1970: 10_600))
        return Self(offer: offer, rating: problem ? "bad" : nil,
            issues: problem ? ["misheard"] : [], message: problem ? "Noted on keyboard" : nil)
    }
}
