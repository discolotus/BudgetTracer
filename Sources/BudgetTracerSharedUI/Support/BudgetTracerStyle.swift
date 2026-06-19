import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Semantic design tokens for the BudgetTracer design language: crisp workspace
/// surfaces, strong typography, compact controls, and a focused red accent.
enum BudgetTracerStyle {
    // MARK: Ink

    static let ink = adaptive(
        light: Color(red: 0.105, green: 0.101, blue: 0.142),
        dark: Color(red: 0.956, green: 0.950, blue: 0.974)
    )

    static var inkMuted: Color { ink.opacity(0.55) }
    static var inkFaint: Color { ink.opacity(0.35) }

    // MARK: Surfaces

    static let canvas = adaptive(
        light: Color(red: 0.963, green: 0.961, blue: 0.976),
        dark: Color(red: 0.091, green: 0.087, blue: 0.128)
    )

    static let surface = adaptive(
        light: Color(red: 0.995, green: 0.994, blue: 1.000),
        dark: Color(red: 0.135, green: 0.129, blue: 0.188)
    )

    static let surfaceSunken = adaptive(
        light: Color(red: 0.107, green: 0.101, blue: 0.145).opacity(0.055),
        dark: Color.white.opacity(0.075)
    )

    static let sidebar = adaptive(
        light: Color(red: 0.938, green: 0.936, blue: 0.956),
        dark: Color(red: 0.108, green: 0.103, blue: 0.153)
    )

    static let surfaceRaised = adaptive(
        light: Color.white,
        dark: Color(red: 0.164, green: 0.157, blue: 0.224)
    )

    static let hairline = adaptive(
        light: Color(red: 0.105, green: 0.101, blue: 0.142).opacity(0.075),
        dark: Color.white.opacity(0.105)
    )

    // MARK: Brand & semantic color

    static let accent = adaptive(
        light: Color(red: 0.965, green: 0.222, blue: 0.178),
        dark: Color(red: 1.000, green: 0.353, blue: 0.302)
    )

    static let accentSoft = adaptive(
        light: Color(red: 1.000, green: 0.895, blue: 0.880),
        dark: Color(red: 1.000, green: 0.353, blue: 0.302).opacity(0.18)
    )

    static let positive = adaptive(
        light: Color(red: 0.000, green: 0.466, blue: 0.330),
        dark: Color(red: 0.341, green: 0.760, blue: 0.588)
    )

    static let caution = adaptive(
        light: Color(red: 0.906, green: 0.288, blue: 0.135),
        dark: Color(red: 1.000, green: 0.505, blue: 0.349)
    )

    static let chartBlue = adaptive(
        light: Color(red: 0.147, green: 0.448, blue: 0.933),
        dark: Color(red: 0.337, green: 0.624, blue: 1.000)
    )

    static let chartPurple = adaptive(
        light: Color(red: 0.468, green: 0.343, blue: 0.899),
        dark: Color(red: 0.722, green: 0.608, blue: 1.000)
    )

    // MARK: Legacy aliases

    static var screenBackground: Color { canvas }
    static var cardFill: Color { surface }
    static var cardBorder: Color { hairline }
    static var subduedText: Color { inkMuted }

    // MARK: Motion

    /// The one spring used across the app, so every surface moves with the same character.
    static let spring = Animation.spring(response: 0.42, dampingFraction: 0.85)

    // MARK: Helpers

    private static func adaptive(light: Color, dark: Color) -> Color {
        #if os(iOS)
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
        #elseif os(macOS)
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark ? NSColor(dark) : NSColor(light)
        })
        #else
        light
        #endif
    }
}

// MARK: - Card surface

private struct BudgetTracerCardModifier: ViewModifier {
    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        #if os(macOS)
        content
            .background(.regularMaterial, in: shape)
            .overlay(shape.strokeBorder(BudgetTracerStyle.hairline, lineWidth: 1))
            .shadow(color: Color.black.opacity(0.08), radius: 18, x: 0, y: 10)
        #else
        content
            .background(BudgetTracerStyle.surface, in: shape)
            .overlay(shape.strokeBorder(BudgetTracerStyle.hairline, lineWidth: 0.5))
            .shadow(color: Color.black.opacity(0.07), radius: 22, x: 0, y: 12)
            .shadow(color: Color.black.opacity(0.03), radius: 2, x: 0, y: 1)
        #endif
    }
}

extension View {
    func budgetTracerCard(cornerRadius: CGFloat = 14) -> some View {
        modifier(BudgetTracerCardModifier(cornerRadius: cornerRadius))
    }

    func budgetTracerWorkspaceBackground() -> some View {
        modifier(BudgetTracerWorkspaceBackgroundModifier())
    }
}

private struct BudgetTracerWorkspaceBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        #if os(macOS)
        content.background(.background)
        #else
        content.background(BudgetTracerStyle.canvas)
        #endif
    }
}
