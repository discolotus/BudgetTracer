import BudgetCore
import Foundation
import SwiftUI

struct AccountDetailSummaryView: View {
    var account: FinancialAccount
    var snapshot: BudgetSnapshot
    var transactionCount: Int
    var clear: () -> Void

    private var points: [AccountBalancePoint] {
        snapshot.accountBalanceHistory(for: account.id)
    }

    private var institutionName: String {
        snapshot.institutions.first { $0.id == account.institutionID }?.name ?? "Unknown institution"
    }

    private var balanceIncrease: Money {
        points
            .map(\.dailyNet)
            .filter(\.isIncome)
            .reduce(Money(minorUnits: 0, currencyCode: account.currentBalance.currencyCode), +)
    }

    private var balanceDecrease: Money {
        let minorUnits = points
            .map(\.dailyNet.minorUnits)
            .filter { $0 < 0 }
            .reduce(Int64(0), +)

        return Money(minorUnits: -minorUnits, currencyCode: account.currentBalance.currencyCode)
    }

    private var netActivity: Money {
        points
            .map(\.dailyNet)
            .reduce(Money(minorUnits: 0, currencyCode: account.currentBalance.currencyCode), +)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            accountHeader

            AccountBalancePlot(points: points, account: account)
                .frame(height: 220)
                .padding(18)
                .budgetTracerCard(cornerRadius: 18)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 12)], spacing: 12) {
                AccountMetricTile(title: "Current", value: account.currentBalance.formatted)
                AccountMetricTile(title: "Transactions", value: "\(transactionCount)")
                AccountMetricTile(title: increaseTitle, value: balanceIncrease.formatted)
                AccountMetricTile(title: decreaseTitle, value: balanceDecrease.formatted)
                AccountMetricTile(title: netTitle, value: netActivity.formatted)
                AccountMetricTile(title: "Main plot", value: plotTreatment)
            }

            AccountInfoStrip(
                institutionName: institutionName,
                account: account,
                snapshot: snapshot
            )
        }
    }

    private var accountHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: account.kind.iconName)
                .font(.title3.weight(.semibold))
                .foregroundStyle(BudgetTracerStyle.accent)
                .frame(width: 38, height: 38)
                .background(BudgetTracerStyle.accentSoft, in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(account.name)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(BudgetTracerStyle.ink)
                    .lineLimit(1)

                Text("\(account.kind.displayName) · \(institutionName)")
                    .font(.caption)
                    .foregroundStyle(BudgetTracerStyle.inkMuted)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button(action: clear) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
            }
            .buttonStyle(.plain)
            .foregroundStyle(BudgetTracerStyle.inkMuted)
            .help("Show all accounts")
            .accessibilityLabel("Show all accounts")
        }
        .padding(16)
        .budgetTracerCard(cornerRadius: 18)
    }

    private var increaseTitle: String {
        account.kind == .creditCard ? "Debt up" : "Money in"
    }

    private var decreaseTitle: String {
        account.kind == .creditCard ? "Debt down" : "Money out"
    }

    private var netTitle: String {
        account.kind == .creditCard ? "Net debt" : "Net activity"
    }

    private var plotTreatment: String {
        switch account.kind {
        case .checking, .savings:
            return snapshot.includesInAvailableCash(account) ? "Cash" : "Excluded"
        case .creditCard:
            return "Card debt"
        case .investment, .loan, .other:
            return "Excluded"
        }
    }
}

private struct AccountMetricTile: View {
    var title: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(BudgetTracerStyle.inkMuted)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(BudgetTracerStyle.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .budgetTracerCard(cornerRadius: 16)
    }
}

private struct AccountInfoStrip: View {
    var institutionName: String
    var account: FinancialAccount
    var snapshot: BudgetSnapshot

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                infoItem("Institution", institutionName)
                infoItem("Type", account.plaidType ?? account.kind.displayName)
                infoItem("Subtype", account.plaidSubtype ?? "None")
                infoItem("Cash", snapshot.includesInAvailableCash(account) ? "Included" : "Excluded")
            }

            VStack(alignment: .leading, spacing: 10) {
                infoItem("Institution", institutionName)
                infoItem("Type", account.plaidType ?? account.kind.displayName)
                infoItem("Subtype", account.plaidSubtype ?? "None")
                infoItem("Cash", snapshot.includesInAvailableCash(account) ? "Included" : "Excluded")
            }
        }
        .padding(14)
        .budgetTracerCard(cornerRadius: 18)
    }

    private func infoItem(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(BudgetTracerStyle.inkFaint)
            Text(value)
                .font(.caption.weight(.medium))
                .foregroundStyle(BudgetTracerStyle.ink)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AccountBalancePlot: View {
    var points: [AccountBalancePoint]
    var account: FinancialAccount

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Balance over time")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(BudgetTracerStyle.inkMuted)
                Spacer()
                Text((points.last?.balance ?? account.currentBalance).formatted)
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(BudgetTracerStyle.ink)
                    .contentTransition(.numericText())
            }

            GeometryReader { proxy in
                ZStack(alignment: .bottomLeading) {
                    Rectangle()
                        .fill(BudgetTracerStyle.hairline)
                        .frame(height: 1)
                        .offset(y: proxy.size.height / -2)

                    areaPath(in: proxy.size)
                        .fill(
                            LinearGradient(
                                colors: [lineColor.opacity(0.14), lineColor.opacity(0)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    linePath(in: proxy.size)
                        .stroke(lineColor, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                    ForEach(points) { point in
                        if point.hasTransactions {
                            Circle()
                                .fill(markerColor(for: point))
                                .frame(width: 4, height: 4)
                                .position(plotLocation(for: point, in: proxy.size))
                                .help(markerHelp(for: point))
                        }
                    }

                    if let last = points.last {
                        ChartEndpointDot(color: lineColor)
                            .position(plotLocation(for: last, in: proxy.size))
                    }

                    AccountPlotYAxisLabels(labels: yAxisLabels)
                        .padding(.trailing, 4)
                }
            }

            HStack {
                Text(startLabel)
                Spacer()
                Text(endLabel)
            }
            .font(.caption)
            .foregroundStyle(BudgetTracerStyle.inkFaint)
        }
    }

    private var lineColor: Color {
        account.kind == .creditCard ? BudgetTracerStyle.caution : BudgetTracerStyle.chartBlue
    }

    private var balanceRange: ClosedRange<Int64> {
        AccountMoneyAxis.roundedRange(
            for: points.map(\.balance.minorUnits),
            includeZero: false
        )
    }

    private var yAxisLabels: [String] {
        AccountMoneyAxis.labels(for: balanceRange)
    }

    private var startLabel: String {
        points.first?.date.formatted(.dateTime.month(.abbreviated).day()) ?? "No data"
    }

    private var endLabel: String {
        points.last?.date.formatted(.dateTime.month(.abbreviated).day()) ?? "No data"
    }

    private var dateSpan: TimeInterval {
        guard let first = points.first?.date,
              let last = points.last?.date else {
            return 1
        }

        return max(last.timeIntervalSince(first), 1)
    }

    private func linePath(in size: CGSize) -> Path {
        Path { path in
            for index in points.indices {
                let location = plotLocation(for: points[index], in: size)
                if index == points.startIndex {
                    path.move(to: location)
                } else {
                    path.addLine(to: location)
                }
            }
        }
    }

    private func areaPath(in size: CGSize) -> Path {
        var path = linePath(in: size)
        guard let first = points.first,
              let last = points.last else {
            return path
        }

        path.addLine(to: CGPoint(x: plotLocation(for: last, in: size).x, y: size.height))
        path.addLine(to: CGPoint(x: plotLocation(for: first, in: size).x, y: size.height))
        path.closeSubpath()
        return path
    }

    private func plotLocation(for point: AccountBalancePoint, in size: CGSize) -> CGPoint {
        let firstDate = points.first?.date ?? point.date
        let elapsed = point.date.timeIntervalSince(firstDate)
        let xRatio = min(max(elapsed / dateSpan, 0), 1)
        let range = balanceRange
        let denominator = max(Double(range.upperBound - range.lowerBound), 1)
        let yRatio = Double(point.balance.minorUnits - range.lowerBound) / denominator

        return CGPoint(
            x: size.width * CGFloat(xRatio),
            y: size.height - (size.height * CGFloat(yRatio))
        )
    }

    private func markerHelp(for point: AccountBalancePoint) -> String {
        let countText = point.transactionCount == 1 ? "1 transaction" : "\(point.transactionCount) transactions"
        return "\(point.date.formatted(date: .abbreviated, time: .omitted)): \(countText), \(point.dailyNet.formatted)"
    }

    private func markerColor(for point: AccountBalancePoint) -> Color {
        if account.kind == .creditCard {
            return point.dailyNet.isIncome ? BudgetTracerStyle.caution : BudgetTracerStyle.positive
        }

        return point.dailyNet.isExpense ? BudgetTracerStyle.caution : BudgetTracerStyle.positive
    }
}

private struct AccountPlotYAxisLabels: View {
    var labels: [String]

    var body: some View {
        HStack {
            Spacer()
            VStack(alignment: .trailing) {
                ForEach(labels.indices, id: \.self) { index in
                    Text(labels[index])

                    if index < labels.index(before: labels.endIndex) {
                        Spacer()
                    }
                }
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(BudgetTracerStyle.inkFaint)
        }
        .allowsHitTesting(false)
    }
}

private enum AccountMoneyAxis {
    static func roundedRange(for values: [Int64], includeZero: Bool) -> ClosedRange<Int64> {
        let sourceValues = values.isEmpty ? [Int64(0)] : values
        var minValue = sourceValues.min() ?? 0
        var maxValue = sourceValues.max() ?? 0

        if includeZero {
            minValue = min(minValue, 0)
            maxValue = max(maxValue, 0)
        }

        let minDollars = Double(minValue) / 100
        let maxDollars = Double(maxValue) / 100
        let rawSpan = max(maxDollars - minDollars, 1)
        let step = max(niceStep(for: rawSpan / 6), 10)
        let lowerDollars = floor(minDollars / step) * step
        let upperDollars = ceil(maxDollars / step) * step

        if upperDollars <= lowerDollars {
            return minorUnits(for: lowerDollars - step)...minorUnits(for: upperDollars + step)
        }

        return minorUnits(for: lowerDollars)...minorUnits(for: upperDollars)
    }

    static func labels(for range: ClosedRange<Int64>) -> [String] {
        [
            compactCurrency(for: range.upperBound),
            compactCurrency(for: range.lowerBound)
        ]
    }

    private static func niceStep(for value: Double) -> Double {
        guard value.isFinite, value > 0 else {
            return 1
        }

        let exponent = floor(log10(value))
        let magnitude = pow(10, exponent)
        let normalized = value / magnitude

        switch normalized {
        case ...1:
            return magnitude
        case ...2:
            return 2 * magnitude
        case ...5:
            return 5 * magnitude
        default:
            return 10 * magnitude
        }
    }

    private static func minorUnits(for dollars: Double) -> Int64 {
        Int64((dollars * 100).rounded())
    }

    private static func compactCurrency(for minorUnits: Int64) -> String {
        let sign = minorUnits < 0 ? "-" : ""
        let dollars = abs(minorUnits) / 100

        if dollars >= 1_000_000, dollars % 1_000_000 == 0 {
            return "\(sign)$\(dollars / 1_000_000)M"
        }

        if dollars >= 10_000, dollars % 1_000 == 0 {
            return "\(sign)$\(dollars / 1_000)k"
        }

        return "\(sign)$\(dollars.formatted(.number.grouping(.automatic)))"
    }
}
