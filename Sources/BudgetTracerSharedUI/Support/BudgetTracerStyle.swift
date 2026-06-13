import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Semantic design tokens for the BudgetTracer design language: warm paper canvas,
/// typography-led hierarchy, quiet surfaces, restrained color, soft motion.
enum BudgetTracerStyle {
    // MARK: Ink

    static let ink = adaptive(
        light: Color(red: 0.110, green: 0.118, blue: 0.106),
        dark: Color(red: 0.945, green: 0.941, blue: 0.918)
    )

    static var inkMuted: Color { ink.opacity(0.55) }
    static var inkFaint: Color { ink.opacity(0.35) }

    // MARK: Surfaces

    static let canvas = adaptive(
        light: Color(red: 0.965, green: 0.957, blue: 0.937),
        dark: Color(red: 0.075, green: 0.082, blue: 0.078)
    )

    static let surface = adaptive(
        light: Color.white,
        dark: Color(red: 0.118, green: 0.125, blue: 0.122)
    )

    static let surfaceSunken = adaptive(
        light: Color(red: 0.110, green: 0.118, blue: 0.106).opacity(0.045),
        dark: Color.white.opacity(0.06)
    )

    static let hairline = adaptive(
        light: Color(red: 0.110, green: 0.118, blue: 0.106).opacity(0.08),
        dark: Color.white.opacity(0.10)
    )

    // MARK: Brand & semantic color

    static let accent = adaptive(
        light: Color(red: 0.118, green: 0.361, blue: 0.294),
        dark: Color(red: 0.357, green: 0.710, blue: 0.588)
    )

    static let accentSoft = adaptive(
        light: Color(red: 0.890, green: 0.933, blue: 0.906),
        dark: Color(red: 0.357, green: 0.710, blue: 0.588).opacity(0.16)
    )

    static let positive = adaptive(
        light: Color(red: 0.180, green: 0.482, blue: 0.322),
        dark: Color(red: 0.384, green: 0.718, blue: 0.533)
    )

    static let caution = adaptive(
        light: Color(red: 0.745, green: 0.329, blue: 0.188),
        dark: Color(red: 0.847, green: 0.494, blue: 0.357)
    )

    static let chartBlue = adaptive(
        light: Color(red: 0.208, green: 0.404, blue: 0.808),
        dark: Color(red: 0.482, green: 0.608, blue: 0.910)
    )

    static let chartPurple = adaptive(
        light: Color(red: 0.404, green: 0.341, blue: 0.784),
        dark: Color(red: 0.635, green: 0.588, blue: 0.890)
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
            .background(BudgetTracerStyle.surface, in: shape)
            .overlay(shape.strokeBorder(BudgetTracerStyle.hairline, lineWidth: 1))
            .shadow(color: Color.black.opacity(0.03), radius: 10, x: 0, y: 4)
        #else
        content
            .background(BudgetTracerStyle.surface, in: shape)
            .overlay(shape.strokeBorder(BudgetTracerStyle.hairline, lineWidth: 0.5))
            .shadow(color: Color.black.opacity(0.04), radius: 20, x: 0, y: 10)
            .shadow(color: Color.black.opacity(0.03), radius: 2, x: 0, y: 1)
        #endif
    }
}

extension View {
    func budgetTracerCard(cornerRadius: CGFloat = 22) -> some View {
        modifier(BudgetTracerCardModifier(cornerRadius: cornerRadius))
    }
}
