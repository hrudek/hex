import SwiftUI

extension DictationStyle {
    var settingsDescription: String {
        switch self {
        case .polished: "Sentence case, clean punctuation and fewer fillers. For messages and longer text."
        case .casual: "Lowercase chat text. Drops the final period in a single sentence; keeps question and exclamation marks."
        case .notes: "Turns spoken “bullet”, “new line” and “new paragraph” into bullets and line breaks. For lists and quick notes."
        case .verbatim: "Skips AI cleanup and style formatting. Vocabulary corrections, spaces instead of hyphens between words and basic spacing still apply."
        }
    }
}

/// A full-row selection target with enough room for decision copy and larger text.
struct SettingsChoiceRow: View {
    let title: String
    var detail: String? = nil
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: detail == nil ? .center : .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.body.weight(.medium)).foregroundStyle(TyprTheme.textBase)
                    if let detail {
                        Text(detail).font(.subheadline).foregroundStyle(TyprTheme.textMuted)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(TyprTheme.success)
                    .opacity(isSelected ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

@MainActor
struct DictationStyleSettingsCard: View {
    @Bindable var dictation: DictationController

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsSection {
                ForEach(DictationStyle.allCases, id: \.self) { style in
                    if style != DictationStyle.allCases.first { SettingsDivider() }
                    SettingsChoiceRow(title: style.label, detail: style.settingsDescription,
                                      isSelected: dictation.style == style) {
                        dictation.setStyle(style)
                    }
                }
            }
            Text("AI cleanup, when enabled and available, runs before formatting in every style except Verbatim.")
                .font(.footnote).foregroundStyle(TyprTheme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
        }
    }
}

@MainActor
struct DictationLanguageSettingsCard: View {
    @Bindable var dictation: DictationController

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsSection {
                ForEach(DictationLanguage.allCases, id: \.self) { language in
                    if language != DictationLanguage.allCases.first { SettingsDivider() }
                    SettingsChoiceRow(title: language.label,
                                      isSelected: dictation.dictationLanguage == language) {
                        dictation.setDictationLanguage(language)
                    }
                }
            }
            if let warning = SpeechEngineRowState.languageWarning(
                engine: dictation.preferredEngine ?? dictation.currentEngine,
                language: dictation.dictationLanguage
            ) {
                Label("Parakeet V2 is English only. \(warning)", systemImage: "exclamationmark.circle")
                    .font(.subheadline).foregroundStyle(TyprTheme.warmMic)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
            }
            Text("Changes apply to your next dictation. Apple Speech may need to prepare the selected language on this iPhone.")
                .font(.footnote).foregroundStyle(TyprTheme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
        }
    }
}
