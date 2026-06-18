import SwiftUI

// MARK: - Eyebrow label

/// Small label used above hero values and section groups.
struct EyebrowText: View {
    var text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(BudgetTracerStyle.inkMuted)
    }
}

// MARK: - Section header

struct SectionHeader: View {
    var title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.title2.weight(.bold))
            .foregroundStyle(BudgetTracerStyle.ink)
    }
}

// MARK: - Pill segmented picker

/// Compact segmented control with a soft track and a raised selected segment.
struct ThemePillPicker<Option: Hashable>: View {
    var options: [Option]
    @Binding var selection: Option
    var label: (Option) -> String

    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                segment(for: option)
            }
        }
        .padding(3)
        .background(BudgetTracerStyle.surfaceSunken, in: Capsule(style: .continuous))
    }

    private func segment(for option: Option) -> some View {
        let isSelected = option == selection

        return Button {
            withAnimation(BudgetTracerStyle.spring) {
                selection = option
            }
        } label: {
            Text(label(option))
                .font(.footnote.weight(isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? BudgetTracerStyle.ink : BudgetTracerStyle.inkMuted)
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity)
                .background {
                    if isSelected {
                        Capsule(style: .continuous)
                            .fill(BudgetTracerStyle.surfaceRaised)
                            .overlay(
                                Capsule(style: .continuous)
                                    .strokeBorder(BudgetTracerStyle.hairline, lineWidth: 1)
                            )
                            .shadow(color: Color.black.opacity(0.10), radius: 10, x: 0, y: 4)
                            .matchedGeometryEffect(id: "selection", in: namespace)
                    }
                }
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Legend chip

/// A chart legend entry that doubles as the series visibility toggle.
struct LegendChip: View {
    var color: Color
    var title: String
    var isOn: Bool
    var isEnabled: Bool = true
    var toggle: (() -> Void)?

    var body: some View {
        Group {
            if let toggle {
                Button(action: { withAnimation(BudgetTracerStyle.spring) { toggle() } }) {
                    chipLabel
                }
                .buttonStyle(.plain)
                .disabled(!isEnabled)
            } else {
                chipLabel
            }
        }
    }

    private var chipLabel: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isOn ? color : BudgetTracerStyle.inkFaint)
                .frame(width: 7, height: 7)
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(isOn ? BudgetTracerStyle.ink : BudgetTracerStyle.inkMuted)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            isOn ? BudgetTracerStyle.surfaceSunken : Color.clear,
            in: Capsule(style: .continuous)
        )
        .overlay {
            if !isOn {
                Capsule(style: .continuous)
                    .strokeBorder(BudgetTracerStyle.hairline, lineWidth: 1)
            }
        }
        .opacity(isEnabled ? 1 : 0.45)
        .contentShape(Capsule(style: .continuous))
    }
}

// MARK: - Chip rows

/// Lays legend chips out in one line when they fit, wrapping to an adaptive grid otherwise.
struct ChipFlowRow<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                content
                Spacer(minLength: 0)
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 150), alignment: .leading)],
                alignment: .leading,
                spacing: 8
            ) {
                content
            }
        }
    }
}

// MARK: - Buttons

/// Primary action: white text on the focused red accent capsule.
struct ThemeProminentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(BudgetTracerStyle.accent, in: Capsule(style: .continuous))
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(BudgetTracerStyle.spring, value: configuration.isPressed)
    }
}

/// Secondary action: tonal capsule.
struct ThemeTonalButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.medium))
            .foregroundStyle(BudgetTracerStyle.accent)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(BudgetTracerStyle.accentSoft, in: Capsule(style: .continuous))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(BudgetTracerStyle.spring, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == ThemeProminentButtonStyle {
    static var themeProminent: ThemeProminentButtonStyle { ThemeProminentButtonStyle() }
}

extension ButtonStyle where Self == ThemeTonalButtonStyle {
    static var themeTonal: ThemeTonalButtonStyle { ThemeTonalButtonStyle() }
}

// MARK: - Chart endpoint

/// The "you are here" dot at the end of a chart line: solid core with a soft halo.
struct ChartEndpointDot: View {
    var color: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.18))
                .frame(width: 16, height: 16)
            Circle()
                .fill(BudgetTracerStyle.surface)
                .frame(width: 9, height: 9)
            Circle()
                .fill(color)
                .frame(width: 6.5, height: 6.5)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Rows

/// Hairline separator used between custom card rows.
struct ThemeRowDivider: View {
    var body: some View {
        Rectangle()
            .fill(BudgetTracerStyle.hairline)
            .frame(height: 1)
    }
}
