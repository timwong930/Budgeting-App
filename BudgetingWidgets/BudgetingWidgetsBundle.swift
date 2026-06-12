import WidgetKit
import SwiftUI

@main
struct BudgetingWidgetsBundle: WidgetBundle {
    var body: some Widget {
        BudgetingWidgets()
        PortfolioWidget()
        WatchlistWidget()
    }
}
