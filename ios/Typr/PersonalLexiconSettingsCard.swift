import SwiftUI

/// Source consent, not a switch for ordinary correction behavior.
struct PersonalLexiconSettingsCard: View {
    @State private var importer = PersonalLexiconImporter.shared
    @State private var contacts = PersonalLexiconImporter.shared.contactsEnabled
    @State private var vocabulary = PersonalLexiconImporter.shared.vocabularyEnabled
    @State private var requesting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsSection(title: "Personal names and terms") {
                SettingsToggle(title: "Import contacts", detail: "Use given names, family names, nicknames and companies. Typr asks for Contacts access; limited access imports only selected contacts.", isOn: $contacts)
                    .disabled(requesting)
                    .onChange(of: contacts) { _, enabled in
                        guard enabled != importer.contactsEnabled else { return }
                        requesting = true
                        Task {
                            await importer.setContacts(enabled)
                            contacts = importer.contactsEnabled
                            requesting = false
                        }
                    }
                SettingsDivider()
                SettingsToggle(title: "Import dictation words", detail: "Use active custom vocabulary and words from recent finished dictations. Not rejected speech or model answers.", isOn: $vocabulary)
                    .onChange(of: vocabulary) { _, enabled in importer.setVocabulary(enabled) }
                SettingsDivider()
                Button {
                    importer.clear()
                    contacts = importer.contactsEnabled
                    vocabulary = importer.vocabularyEnabled
                } label: {
                    SettingsLink(title: "Delete imported words", detail: "Clears the shared list and turns off both imports")
                }
                .buttonStyle(.plain)
            }
            Text("Only words are shared with the keyboard on this iPhone, with Full Access. No phone numbers, addresses, sentences or audio are shared. Imported spellings stay literal and can appear as completions, independently of Learn from my typing. Reset learning also deletes this list and turns off imports. This does not delete contacts, custom vocabulary or the Dictation log.")
                .font(.footnote).foregroundStyle(TyprTheme.textMuted)
                .padding(.horizontal, 16)
            if let problem = importer.problem {
                Text(problem).font(.footnote).foregroundStyle(TyprTheme.textMuted)
                    .padding(.horizontal, 16)
            }
        }
        .onAppear {
            contacts = importer.contactsEnabled
            vocabulary = importer.vocabularyEnabled
        }
    }
}
