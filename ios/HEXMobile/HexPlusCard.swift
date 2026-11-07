import SwiftUI

/// Hex+ switches. They live in the App Group so the keyboard reads them too.
struct HexPlusCard: View {
    @State private var germanAutocorrect = HexPlusSettings().germanAutocorrect
    @State private var keyboardSwitchKey = HexPlusSettings().keyboardSwitchKey

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Hex+")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(HexTheme.textMuted)
                .padding(.leading, 16)

            VStack(spacing: 0) {
                row(
                    "German autocorrect",
                    detail: "Turns ae, oe, ue into ä, ö, ü and fixes German typos (full keyboard)",
                    isOn: $germanAutocorrect
                )
                .onChange(of: germanAutocorrect) { _, enabled in
                    HexPlusSettings().germanAutocorrect = enabled
                }

                Divider()
                    .overlay(HexTheme.borderWeak)
                    .padding(.leading, 16)

                row(
                    "Keyboard switch key",
                    detail: "A key on both keyboards switches between the full keyboard and the dictation bar. On the full keyboard, hold it briefly.",
                    isOn: $keyboardSwitchKey
                )
                .onChange(of: keyboardSwitchKey) { _, enabled in
                    HexPlusSettings().keyboardSwitchKey = enabled
                }
            }
            .background(
                HexTheme.bgBase,
                in: RoundedRectangle(cornerRadius: HexTheme.cardRadius, style: .continuous)
            )
        }
        .onAppear {
            germanAutocorrect = HexPlusSettings().germanAutocorrect
            keyboardSwitchKey = HexPlusSettings().keyboardSwitchKey
        }
    }

    private func row(_ title: String, detail: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(HexTheme.textBase)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(HexTheme.textMuted)
            }
        }
        .tint(HexTheme.success)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
