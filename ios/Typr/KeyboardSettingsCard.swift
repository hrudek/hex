import SwiftUI
import UIKit

/// Keyboard preferences, grouped by purpose rather than feature maturity.
struct KeyboardSettingsCard: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var fullKeyboard = FullKeyboardSettings().isEnabled
    @State private var autocorrect = FullKeyboardSettings().autocorrect
    @State private var autocorrectGerman = TyprSettings().autocorrectGerman
    @State private var autocorrectEnglish = TyprSettings().autocorrectEnglish
    @State private var hideSuggestionBar = TyprSettings().hideSuggestionBar

    var body: some View {
        VStack(spacing: 24) {
            SettingsSection(title: "Keyboard layout") {
                SettingsToggle(title: "Full keyboard", detail: "Type with Typr. Hold the Typr key to dictate.", isOn: $fullKeyboard)
                    .onChange(of: fullKeyboard) { _, enabled in
                        FullKeyboardSettings().isEnabled = enabled
                    }
                SettingsDivider()
                SettingsToggle(title: "Hide suggestion bar", detail: "More room for your text. Autocorrect still works on space.", isOn: $hideSuggestionBar)
                    .onChange(of: hideSuggestionBar) { _, enabled in
                        TyprSettings().hideSuggestionBar = enabled
                    }
            }
            if fullKeyboard {
                SettingsSection(title: "Typing assistance") {
                    SettingsToggle(title: "Autocorrect", detail: "Correct contractions, shortcuts and small typos on space.", isOn: $autocorrect)
                        .onChange(of: autocorrect) { _, enabled in
                            FullKeyboardSettings().autocorrect = enabled
                        }
                    if autocorrect {
                        SettingsDivider()
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Autocorrect languages")
                                .font(.subheadline).foregroundStyle(TyprTheme.textMuted)
                            Toggle("Deutsch", isOn: $autocorrectGerman)
                                .onChange(of: autocorrectGerman) { _, enabled in TyprSettings().autocorrectGerman = enabled }
                            Divider().overlay(TyprTheme.borderWeak)
                            Toggle("English", isOn: $autocorrectEnglish)
                                .onChange(of: autocorrectEnglish) { _, enabled in TyprSettings().autocorrectEnglish = enabled }
                        }
                        .font(.body)
                        .foregroundStyle(TyprTheme.textBase)
                        .tint(TyprTheme.success)
                        .padding(18)
                    }
                }
            }
            SettingsSection(title: "iPhone setup") {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                } label: {
                    SettingsLink(title: "iOS keyboard settings", detail: "Enable Typr and Full Access", icon: "arrow.up.right.square")
                }
                .buttonStyle(.plain)
            }
        }
        .onAppear(perform: refresh)
        .onChange(of: scenePhase) { _, phase in if phase == .active { refresh() } }
    }

    private func refresh() {
        fullKeyboard = FullKeyboardSettings().isEnabled
        autocorrect = FullKeyboardSettings().autocorrect
        autocorrectGerman = TyprSettings().autocorrectGerman
        autocorrectEnglish = TyprSettings().autocorrectEnglish
        hideSuggestionBar = TyprSettings().hideSuggestionBar
    }
}

struct VocabularySettingsCard: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var enabled = CustomVocabularySettings().isEnabled

    var body: some View {
        SettingsSection(title: "Your vocabulary") {
            SettingsToggle(title: "Custom vocabulary", detail: "Preferred spellings for names and terms, with optional sounds-like forms.", isOn: $enabled)
                .onChange(of: enabled) { _, value in CustomVocabularySettings().isEnabled = value }
            if enabled {
                SettingsDivider()
                CustomVocabularyEditor().padding(18)
            }
        }
        .onAppear { enabled = CustomVocabularySettings().isEnabled }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { enabled = CustomVocabularySettings().isEnabled }
        }
    }
}
