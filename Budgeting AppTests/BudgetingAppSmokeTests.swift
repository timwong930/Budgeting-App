import XCTest
@testable import Momo_s_Money

final class BudgetingAppSmokeTests: XCTestCase {
    func testMarketChangeFormatting() {
        let gain = CuanMarketChangeDisplay(change: 2.4, percentChange: 1.25)
        XCTAssertEqual(gain.priceChangeText, "+$2.40")
        XCTAssertEqual(gain.percentChangeText, "+1.25%")
        XCTAssertEqual(gain.direction, .gain)

        let loss = CuanMarketChangeDisplay(change: -1.27, percentChange: -0.31)
        XCTAssertEqual(loss.priceChangeText, "-$1.27")
        XCTAssertEqual(loss.percentChangeText, "-0.31%")
        XCTAssertEqual(loss.direction, .loss)
    }

    func testSparklineNormalization() {
        XCTAssertEqual(CuanSparklineSeries(values: [10, 15, 20]).normalized, [0.0, 0.5, 1.0])
        XCTAssertEqual(CuanSparklineSeries(values: [7, 7, 7]).normalized, [0.5, 0.5, 0.5])
    }
}
