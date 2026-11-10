import SwiftUI

/// Preferred spellings and sounds-like forms, under AI & vocabulary settings.
struct CustomVocabularyEditor: View {
    private let settings = CustomVocabularySettings()

    @State private var terms: [String] = []
    @State private var draft = ""
    @State private var notice: String?
    @State private var soundsLike: [String: [String]] = [:]
    @State private var editingTerm: String?
    @State private var soundsLikeDraft = ""

    private var isAtLimit: Bool {
        terms.count >= CustomVocabularySettings.maxTermCount
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(terms, id: \.self) { term in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        Text(term)
                            .font(.body)
                            .foregroundStyle(TyprTheme.textBase)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: 8)

                        Button {
                            toggleSoundsLike(for: term)
                        } label: {
                            Image(systemName: editingTerm == term ? "checkmark" : "waveform")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(editingTerm == term ? TyprTheme.textBase : TyprTheme.textMuted)
                                .frame(width: 32, height: 32)
                                .background(TyprTheme.layer02, in: Circle())
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(editingTerm == term ? "Save sounds-like forms for \(term)" : "Edit sounds-like forms for \(term)")

                        Button {
                            remove(term)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(TyprTheme.textMuted)
                                .frame(width: 32, height: 32)
                                .background(TyprTheme.layer02, in: Circle())
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove \(term)")
                    }

                    if editingTerm == term {
                        TextField("Sounds like, e.g. Herder, Herda", text: $soundsLikeDraft)
                            .font(.system(size: 13))
                            .foregroundStyle(TyprTheme.textBase)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                            .onSubmit { saveSoundsLike(for: term) }
                            .accessibilityLabel("Sounds like for \(term), separated by commas")
                    } else if let forms = soundsLike[VocabularySpelling.normalizedKey(term)], !forms.isEmpty {
                        Text("Sounds like: \(forms.joined(separator: ", "))")
                            .font(.system(size: 12))
                            .foregroundStyle(TyprTheme.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 5)
                .padding(.leading, 12)
                .padding(.trailing, 6)
                .frame(minHeight: 36)
                .background(
                    TyprTheme.layer01,
                    in: RoundedRectangle(
                        cornerRadius: TyprTheme.controlRadius,
                        style: .continuous
                    )
                )
            }

            TextField("Add a word or phrase", text: $draft)
                .font(.body)
                .foregroundStyle(TyprTheme.textBase)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit(add)
                .onChange(of: draft) { _, _ in
                    notice = nil
                }
                .disabled(isAtLimit)
                .padding(.horizontal, 12)
                .frame(minHeight: 48)
                .background(
                    TyprTheme.layer01,
                    in: RoundedRectangle(
                        cornerRadius: TyprTheme.controlRadius,
                        style: .continuous
                    )
                )
                .opacity(isAtLimit ? 0.5 : 1)

            if isAtLimit {
                Text("Up to 100 terms")
                    .font(.system(size: 12))
                    .foregroundStyle(TyprTheme.textMuted)
            }

            if let notice {
                Text(notice)
                    .font(.system(size: 12))
                    .foregroundStyle(TyprTheme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("Your spellings take priority over built-in tech terms. Tap the waveform to add what the engine writes instead, e.g. Herder for herdr.")
            .font(.subheadline)
            .foregroundStyle(TyprTheme.textMuted)
            .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear {
            terms = settings.terms
            soundsLike = settings.soundsLike
        }
    }

    private func add() {
        guard !isAtLimit else { return }
        let candidate = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return }

        guard candidate.count <= CustomVocabularySettings.maxTermLength else {
            notice = "Too long"
            return
        }
        let key = VocabularySpelling.normalizedKey(candidate)
        guard key.count >= 2 else {
            notice = "Needs at least two letters or digits"
            return
        }
        let isDuplicate = terms.contains {
            VocabularySpelling.normalizedKey($0) == key
        }
        guard !isDuplicate else {
            notice = "Already in the list"
            return
        }

        let updated = CustomVocabularySettings.sanitize(terms + [candidate])
        terms = updated
        settings.terms = updated
        draft = ""
        notice = nil
    }

    private func remove(_ term: String) {
        settings.setSoundsLike([], for: term)
        terms.removeAll { $0 == term }
        settings.terms = terms
        soundsLike = settings.soundsLike
        if editingTerm == term { editingTerm = nil }
        notice = nil
    }

    private func toggleSoundsLike(for term: String) {
        if editingTerm == term {
            saveSoundsLike(for: term)
        } else {
            editingTerm = term
            soundsLikeDraft = settings.soundsLike(for: term).joined(separator: ", ")
            notice = nil
        }
    }

    private func saveSoundsLike(for term: String) {
        let entered = CustomVocabularySettings.parseSoundsLike(soundsLikeDraft)
        settings.setSoundsLike(entered, for: term)
        let saved = settings.soundsLike(for: term)
        soundsLike = settings.soundsLike
        editingTerm = nil
        notice = saved.count < entered.count
            ? "Some sounds-like entries were skipped: too short, too long, a listed term, or already used"
            : nil
    }
}
