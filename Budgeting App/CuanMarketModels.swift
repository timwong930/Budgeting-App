import Foundation

enum CuanMarketDirection: Equatable {
    case gain
    case loss
    case flat
}

struct CuanMarketChangeDisplay: Equatable {
    let change: Double
    let percentChange: Double

    var direction: CuanMarketDirection {
        if percentChange > 0 { return .gain }
        if percentChange < 0 { return .loss }
        return .flat
    }

    var priceChangeText: String {
        signedCurrency(change)
    }

    var percentChangeText: String {
        "\(signedNumber(percentChange))%"
    }

    private func signedCurrency(_ value: Double) -> String {
        let absolute = abs(value).formatted(.currency(code: "USD").precision(.fractionLength(2)))
        if value > 0 { return "+\(absolute)" }
        if value < 0 { return "-\(absolute)" }
        return absolute
    }

    private func signedNumber(_ value: Double) -> String {
        let formatted = abs(value).formatted(.number.precision(.fractionLength(2)))
        if value > 0 { return "+\(formatted)" }
        if value < 0 { return "-\(formatted)" }
        return formatted
    }
}

struct CuanSparklineSeries: Equatable {
    let values: [Double]

    var normalized: [Double] {
        guard let minValue = values.min(), let maxValue = values.max() else { return [] }
        let spread = maxValue - minValue
        guard spread > 0 else { return values.map { _ in 0.5 } }
        return values.map { ($0 - minValue) / spread }
    }
}
