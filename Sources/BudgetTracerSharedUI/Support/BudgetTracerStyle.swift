import SwiftUI

enum BudgetTracerStyle {
    static let accent = Color(red: 0.0, green: 0.47, blue: 0.42)
    static let accentSoft = Color(red: 0.86, green: 0.95, blue: 0.93)
    static let positive = Color(red: 0.1, green: 0.55, blue: 0.34)
    static let caution = Color(red: 0.82, green: 0.38, blue: 0.16)
    static let chartBlue = Color(red: 0.03, green: 0.39, blue: 0.78)
    static let chartPurple = Color(red: 0.38, green: 0.28, blue: 0.75)

    static var screenBackground: Color {
        #if os(iOS)
        Color(red: 0.97, green: 0.97, blue: 0.95)
        #else
        Color(nsColor: .windowBackgroundColor)
        #endif
    }

    static var cardFill: Color {
        #if os(iOS)
        Color(uiColor: .secondarySystemGroupedBackground)
        #else
        Color.primary.opacity(0.035)
        #endif
    }

    static var cardBorder: Color {
        Color.primary.opacity(0.08)
    }

    static var subduedText: Color {
        Color.secondary
    }
}

private struct BudgetTracerCardModifier: ViewModifier {
    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        #if os(macOS)
        content
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: min(cornerRadius, 12), style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: min(cornerRadius, 12), style: .continuous)
                    .stroke(BudgetTracerStyle.cardBorder, lineWidth: 1)
            }
        #else
        content
            .background(BudgetTracerStyle.cardFill, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(BudgetTracerStyle.cardBorder, lineWidth: 1)
            }
            .shadow(color: Color.black.opacity(0.035), radius: 18, x: 0, y: 10)
        #endif
    }
}

extension View {
    func budgetTracerCard(cornerRadius: CGFloat = 24) -> some View {
        modifier(BudgetTracerCardModifier(cornerRadius: cornerRadius))
    }
}
