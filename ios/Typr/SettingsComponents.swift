import SwiftUI

/// Routes are also used by explicit simulator screenshot scenes; no settings are mutated.
enum SettingsDestination: String, CaseIterable, Hashable {
    case keyboard, writing, history, speechEngine = "speech-engine"

    var title: String {
        switch self {
        case .keyboard: "Keyboard"
        case .writing: "Writing"
        case .history: "History & feedback"
        case .speechEngine: "Speech engine"
        }
    }

    var subtitle: String {
        switch self {
        case .keyboard: "Choose your layout and typing assistance."
        case .writing: "Your words, with the right spelling and polish."
        case .history: "Review dictations and help track what works."
        case .speechEngine: "Recognition runs on this iPhone. Your chosen engine never switches by itself."
        }
    }

    static func snapshotDestination(arguments: [String]) -> Self? {
        guard let index = arguments.firstIndex(of: "--snap-state"), index + 1 < arguments.count else { return nil }
        let scene = arguments[index + 1]
        guard scene.hasPrefix("settings-") else { return nil }
        return Self(rawValue: String(scene.dropFirst("settings-".count)))
    }
}

/// Shared settings surfaces. Keep the keyboard's palette and settings storage unchanged.
struct SettingsSection<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(TyprTheme.textBase)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(TyprTheme.textMuted)
                }
            }
            .padding(.horizontal, 4)
            VStack(spacing: 0) { content }
                .background(TyprTheme.bgBase, in: RoundedRectangle(cornerRadius: TyprTheme.cardRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: TyprTheme.cardRadius)
                        .strokeBorder(TyprTheme.borderWeak, lineWidth: 1)
                        .allowsHitTesting(false)
                }
        }
    }
}

struct SettingsDivider: View {
    var body: some View {
        Divider().overlay(TyprTheme.borderWeak).padding(.leading, 18)
    }
}

struct SettingsToggle: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.body).foregroundStyle(TyprTheme.textBase)
                Text(detail).font(.subheadline).foregroundStyle(TyprTheme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.trailing, 8)
        }
        .tint(TyprTheme.success)
        .padding(18)
        .frame(minHeight: 64)
    }
}

struct SettingsLink: View {
    let title: String
    let detail: String
    let icon: String
    var value: String? = nil

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(TyprTheme.agentBlue)
                .frame(width: 38, height: 38)
                .background(TyprTheme.layer02, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.body.weight(.medium)).foregroundStyle(TyprTheme.textBase)
                Text(detail).font(.subheadline).foregroundStyle(TyprTheme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                if let value {
                    Text(value).font(.caption.weight(.medium)).foregroundStyle(TyprTheme.agentBlue)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(TyprTheme.textFaint)
                .accessibilityHidden(true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
        .contentShape(Rectangle())
    }
}

struct SettingsPage<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(TyprTheme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                content
            }
            .frame(maxWidth: 500)
            .padding(20)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity)
        }
        .background(TyprTheme.bgDeep.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(TyprTheme.bgDeep, for: .navigationBar)
        .scrollDismissesKeyboard(.interactively)
    }
}
