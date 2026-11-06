import SwiftUI

/// Hex+ switches. They live in the App Group so the keyboard reads them too.
struct HexPlusCard: View {
    @State private var germanAutocorrect = HexPlusSettings().germanAutocorrect

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Hex+")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(HexTheme.textMuted)
                .padding(.leading, 16)

            VStack(spacing: 0) {
                Toggle(isOn: $germanAutocorrect) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("German autocorrect")
                            .font(.system(size: 15, weight: .regular))
                            .foregroundStyle(HexTheme.textBase)
                        Text("Turns ae, oe, ue into ä, ö, ü and fixes German typos (full keyboard)")
                            .font(.system(size: 12))
                            .foregroundStyle(HexTheme.textMuted)
                    }
                }
                .tint(HexTheme.success)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .onChange(of: germanAutocorrect) { _, enabled in
                    HexPlusSettings().germanAutocorrect = enabled
                }
            }
            .background(
                HexTheme.bgBase,
                in: RoundedRectangle(cornerRadius: HexTheme.cardRadius, style: .continuous)
            )
        }
        .onAppear {
            germanAutocorrect = HexPlusSettings().germanAutocorrect
        }
    }
}
