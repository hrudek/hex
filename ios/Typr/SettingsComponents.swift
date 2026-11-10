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
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(TyprTheme.textMuted)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(TyprTheme.textMuted)
                }
            }
            .padding(.horizontal, 16)
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
    var leading: CGFloat = 18

    var body: some View {
        Divider().overlay(TyprTheme.borderWeak).padding(.leading, leading)
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

/// Compact entry point, not a feature card. Explanations belong on the destination.
/// Normal text sizes use one line; accessibility sizes may wrap without clipping.
struct SettingsLink: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: String
    let detail: String
    let icon: String
    var value: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .regular))
                .foregroundStyle(TyprTheme.textBase)
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    titleLabel
                    if let value { valueLabel(value) }
                }
                Spacer(minLength: 0)
            } else {
                titleLabel.lineLimit(1).layoutPriority(1)
                Spacer(minLength: 8)
                if let value { valueLabel(value).lineLimit(1) }
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(TyprTheme.textFaint)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(detail)
    }

    private var titleLabel: some View {
        Text(title).font(.body).foregroundStyle(TyprTheme.textBase)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func valueLabel(_ value: String) -> some View {
        Text(value).font(.subheadline).foregroundStyle(TyprTheme.textMuted)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Buttons intentionally allow tapping the selected duration again: this restarts an
/// ended warm session or refreshes its timer, unlike a selection-change-only Picker.
struct SettingsWarmDurationControl: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let selected: WarmSessionDuration
    let onSelect: (WarmSessionDuration) -> Void

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4),
                                 count: dynamicTypeSize.isAccessibilitySize ? 2 : 4), spacing: 4) {
            ForEach(WarmSessionDuration.allCases, id: \.self) { duration in
                Button { onSelect(duration) } label: {
                    Text(duration.shortLabel)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(duration == selected ? TyprTheme.textBase : TyprTheme.textMuted)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(duration == selected ? TyprTheme.layer02 : .clear,
                                    in: RoundedRectangle(cornerRadius: 10))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(duration == .off ? "Microphone off" : "Keep microphone warm for \(duration.title)")
                .accessibilityAddTraits(duration == selected ? .isSelected : [])
            }
        }
        .padding(4)
        .background(TyprTheme.layer01, in: RoundedRectangle(cornerRadius: 14))
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
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(TyprTheme.bgDeep, for: .navigationBar)
        .scrollDismissesKeyboard(.interactively)
    }
}
