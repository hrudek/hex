import SwiftUI

/// Unfinished features, off until turned on here. They live in the App Group so the
/// keyboard reads them too.
struct ExperimentsCard: View {
    @State private var fullKeyboard = FullKeyboardSettings().isEnabled
    @State private var autocorrect = FullKeyboardSettings().autocorrect
    @State private var autocorrectGerman = TyprSettings().autocorrectGerman
    @State private var autocorrectEnglish = TyprSettings().autocorrectEnglish
    @State private var appleIntelligenceCleanup = AppleIntelligenceCleanupSettings().isEnabled
    @State private var customVocabulary = CustomVocabularySettings().isEnabled
    @State private var cleanupAvailability = AppleIntelligenceCleanupAvailability.current

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Experiments")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(TyprTheme.textMuted)
                .padding(.leading, 16)

            VStack(spacing: 0) {
                Toggle(isOn: $fullKeyboard) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Full keyboard")
                            .font(.system(size: 15, weight: .regular))
                            .foregroundStyle(TyprTheme.textBase)
                        Text("Type with Typr, with a Typr key to dictate")
                            .font(.system(size: 12))
                            .foregroundStyle(TyprTheme.textMuted)
                    }
                }
                .tint(TyprTheme.success)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .onChange(of: fullKeyboard) { _, enabled in
                    FullKeyboardSettings().isEnabled = enabled
                }

                if fullKeyboard {
                    Divider()
                        .overlay(TyprTheme.borderWeak)
                        .padding(.leading, 16)

                    Toggle(isOn: $autocorrect) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Autocorrect")
                                .font(.system(size: 15, weight: .regular))
                                .foregroundStyle(TyprTheme.textBase)
                            Text("Fix contractions, shortcuts, and one-edit typos on space")
                                .font(.system(size: 12))
                                .foregroundStyle(TyprTheme.textMuted)
                        }
                    }
                    .tint(TyprTheme.success)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .onChange(of: autocorrect) { _, enabled in
                        FullKeyboardSettings().autocorrect = enabled
                    }

                    if autocorrect {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Autocorrect languages")
                                .font(.system(size: 12))
                                .foregroundStyle(TyprTheme.textMuted)
                            Toggle("Deutsch", isOn: $autocorrectGerman)
                                .onChange(of: autocorrectGerman) { _, enabled in
                                    TyprSettings().autocorrectGerman = enabled
                                }
                            Toggle("English", isOn: $autocorrectEnglish)
                                .onChange(of: autocorrectEnglish) { _, enabled in
                                    TyprSettings().autocorrectEnglish = enabled
                                }
                        }
                        .font(.system(size: 15))
                        .foregroundStyle(TyprTheme.textBase)
                        .tint(TyprTheme.success)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 10)
                    }
                }
            }
            .background(
                TyprTheme.bgBase,
                in: RoundedRectangle(cornerRadius: TyprTheme.cardRadius, style: .continuous)
            )

            Toggle(isOn: $appleIntelligenceCleanup) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Clean up with Apple Intelligence")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(TyprTheme.textBase)
                    Text("Fix misheard words and spoken corrections on device")
                        .font(.system(size: 12))
                        .foregroundStyle(TyprTheme.textMuted)
                    if let reason = cleanupAvailability.reason {
                        Text(reason)
                            .font(.system(size: 12))
                            .foregroundStyle(TyprTheme.textMuted)
                    }
                }
            }
            .tint(TyprTheme.success)
            .disabled(!cleanupAvailability.isAvailable)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                TyprTheme.bgBase,
                in: RoundedRectangle(cornerRadius: TyprTheme.cardRadius, style: .continuous)
            )
            .onChange(of: appleIntelligenceCleanup) { _, enabled in
                AppleIntelligenceCleanupSettings().isEnabled = enabled
            }

            Toggle(isOn: $customVocabulary) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Custom vocabulary")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(TyprTheme.textBase)
                    Text("Spell names and terms your way")
                        .font(.system(size: 12))
                        .foregroundStyle(TyprTheme.textMuted)
                }
            }
            .tint(TyprTheme.success)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                TyprTheme.bgBase,
                in: RoundedRectangle(cornerRadius: TyprTheme.cardRadius, style: .continuous)
            )
            .onChange(of: customVocabulary) { _, enabled in
                CustomVocabularySettings().isEnabled = enabled
            }

            if customVocabulary {
                CustomVocabularyEditor()
                    .padding(12)
                    .background(
                        TyprTheme.bgBase,
                        in: RoundedRectangle(
                            cornerRadius: TyprTheme.cardRadius,
                            style: .continuous
                        )
                    )
            }
        }
        .onAppear {
            let settings = FullKeyboardSettings()
            fullKeyboard = settings.isEnabled
            autocorrect = settings.autocorrect
            autocorrectGerman = TyprSettings().autocorrectGerman
            autocorrectEnglish = TyprSettings().autocorrectEnglish
            appleIntelligenceCleanup = AppleIntelligenceCleanupSettings().isEnabled
            customVocabulary = CustomVocabularySettings().isEnabled
            cleanupAvailability = AppleIntelligenceCleanupAvailability.current
        }
    }
}
