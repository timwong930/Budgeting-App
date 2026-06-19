import UIKit
import UserNotifications
import UserNotificationsUI
import os

@objc(NotificationViewController)
final class NotificationViewController: UIViewController, UNNotificationContentExtension {
    private let logger = Logger(subsystem: "Timothy-Wong.Budgeting-App.NotificationContent", category: "NotificationViewController")
    private let containerView = UIView()
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let chartTitleLabel = UILabel()
    private let chartView = SnapshotChartView()
    private let rowsStack = UIStackView()
    private let contentPillsStack = UIStackView()
    private var didInstallLayout = false

    override func loadView() {
        logger.info("loadView")
        let root = UIView()
        root.backgroundColor = .systemBackground
        view = root
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        logger.info("viewDidLoad")
        installLayoutIfNeeded()
        render(
            kind: "budget_snapshot",
            title: "Money Snapshot",
            subtitle: "Budget snapshot",
            lines: ["Net worth and upcoming budget details will appear here."],
            chartTitle: "Budget Snapshot",
            chartLabels: ["Income", "Spent", "Upcoming"],
            chartValues: [100, 45, 20],
            chartStyle: "bars"
        )
    }

    func didReceive(_ notification: UNNotification) {
        logger.info("didReceive category=\(notification.request.content.categoryIdentifier, privacy: .public)")
        installLayoutIfNeeded()
        let content = notification.request.content
        let userInfo = content.userInfo
        let kind = (userInfo["previewKind"] as? String) ?? content.categoryIdentifier
        let lines = (userInfo["previewLines"] as? [String]) ?? lines(from: content.body)
        let chartTitle = (userInfo["chartTitle"] as? String) ?? fallbackChartTitle(for: kind)
        let chartLabels = (userInfo["chartLabels"] as? [String]) ?? []
        let chartValues = (userInfo["chartValues"] as? [Double]) ?? []
        let chartStyle = (userInfo["chartStyle"] as? String) ?? "bars"

        render(
            kind: kind,
            title: (userInfo["previewTitle"] as? String) ?? content.title,
            subtitle: (userInfo["previewSubtitle"] as? String) ?? content.subtitle,
            lines: lines.isEmpty ? ["Snapshot details unavailable. Open Momo's Money for the latest view."] : lines,
            chartTitle: chartTitle,
            chartLabels: chartLabels,
            chartValues: chartValues,
            chartStyle: chartStyle
        )

        let hasPills = setupKindSpecificContent(kind: kind, userInfo: userInfo)
        rowsStack.isHidden = hasPills
    }

    private func installLayoutIfNeeded() {
        guard !didInstallLayout else { return }
        didInstallLayout = true
        logger.info("installLayout")
        view.backgroundColor = .systemBackground
        buildLayout(in: view)
    }

    private func buildLayout(in root: UIView) {
        containerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.backgroundColor = .secondarySystemBackground
        containerView.layer.cornerRadius = 18
        containerView.layer.masksToBounds = true
        root.addSubview(containerView)

        let contentStack = UIStackView()
        contentStack.axis = .vertical
        contentStack.spacing = 12
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(contentStack)

        let header = UIStackView()
        header.axis = .horizontal
        header.alignment = .center
        header.spacing = 12

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentMode = .scaleAspectFit
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 24, weight: .bold)
        iconView.tintColor = .systemPurple
        iconView.backgroundColor = .systemBackground
        iconView.layer.cornerRadius = 20
        iconView.layer.masksToBounds = true
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 40),
            iconView.heightAnchor.constraint(equalToConstant: 40)
        ])

        let titleStack = UIStackView()
        titleStack.axis = .vertical
        titleStack.spacing = 2

        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 2
        titleLabel.adjustsFontForContentSizeCategory = true

        subtitleLabel.font = .preferredFont(forTextStyle: .subheadline)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.numberOfLines = 2
        subtitleLabel.adjustsFontForContentSizeCategory = true

        titleStack.addArrangedSubview(titleLabel)
        titleStack.addArrangedSubview(subtitleLabel)
        header.addArrangedSubview(iconView)
        header.addArrangedSubview(titleStack)

        rowsStack.axis = .vertical
        rowsStack.spacing = 8

        contentPillsStack.axis = .vertical
        contentPillsStack.spacing = 10
        contentPillsStack.isHidden = true

        contentStack.addArrangedSubview(header)
        chartTitleLabel.font = .preferredFont(forTextStyle: .caption1)
        chartTitleLabel.textColor = .secondaryLabel
        chartTitleLabel.adjustsFontForContentSizeCategory = true
        chartTitleLabel.numberOfLines = 1
        chartTitleLabel.text = "Snapshot"
        contentStack.addArrangedSubview(chartTitleLabel)

        chartView.translatesAutoresizingMaskIntoConstraints = false
        chartView.backgroundColor = .systemBackground
        chartView.layer.cornerRadius = 12
        chartView.layer.masksToBounds = true
        contentStack.addArrangedSubview(chartView)
        chartView.heightAnchor.constraint(equalToConstant: 130).isActive = true

        contentStack.addArrangedSubview(contentPillsStack)
        contentStack.addArrangedSubview(rowsStack)

        NSLayoutConstraint.activate([
            containerView.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            containerView.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            containerView.topAnchor.constraint(equalTo: root.topAnchor, constant: 12),
            containerView.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -12),

            contentStack.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 14),
            contentStack.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -14),
            contentStack.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 14),
            contentStack.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -14)
        ])
    }

    private func render(
        kind: String,
        title: String,
        subtitle: String,
        lines: [String],
        chartTitle: String,
        chartLabels: [String],
        chartValues: [Double],
        chartStyle: String
    ) {
        iconView.image = UIImage(systemName: iconName(for: kind))
        iconView.tintColor = tintColor(for: kind)
        titleLabel.text = title.isEmpty ? fallbackTitle(for: kind) : title
        subtitleLabel.text = subtitle.isEmpty ? "Budget snapshot" : subtitle
        chartTitleLabel.text = chartTitle.isEmpty ? fallbackChartTitle(for: kind) : chartTitle
        chartView.configure(
            labels: chartLabels,
            values: chartValues,
            style: chartStyle == "sparkline" ? .sparkline : .bars,
            tintColor: tintColor(for: kind)
        )

        rowsStack.arrangedSubviews.forEach { view in
            rowsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        let cleanLines = lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(3)

        if cleanLines.isEmpty {
            rowsStack.addArrangedSubview(rowView(text: "Snapshot details unavailable."))
        } else {
            for line in cleanLines {
                rowsStack.addArrangedSubview(rowView(text: String(line)))
            }
        }

        let rowCount = max(cleanLines.count, 1)
        preferredContentSize = CGSize(width: 360, height: min(430, 280 + CGFloat(rowCount * 42)))
        view.setNeedsLayout()
        view.layoutIfNeeded()
    }

    // MARK: - Kind-specific content (pills / cards)

    private func setupKindSpecificContent(kind: String, userInfo: [AnyHashable: Any]) -> Bool {
        contentPillsStack.arrangedSubviews.forEach { view in
            contentPillsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        switch kind {
        case "ticker_alert":
            return setupTickerPills(userInfo: userInfo)
        case "budget_snapshot":
            return setupBudgetCards(userInfo: userInfo)
        case "portfolio_snapshot", "portfolio_update":
            return setupPortfolioCards(userInfo: userInfo, kind: kind)
        case "payment_reminder":
            return setupPaymentCard(userInfo: userInfo)
        default:
            contentPillsStack.isHidden = true
            return false
        }
    }

    private func setupTickerPills(userInfo: [AnyHashable: Any]) -> Bool {
        guard userInfo["tickerPrice"] != nil else { return false }
        let open = userInfo["tickerOpen"] as? Double
        let prevClose = userInfo["tickerPrevClose"] as? Double
        let low = userInfo["tickerLow"] as? Double
        let high = userInfo["tickerHigh"] as? Double
        let price = userInfo["tickerPrice"] as? Double ?? 0
        let change = userInfo["tickerChange"] as? Double ?? 0
        let percentChange = userInfo["tickerPercentChange"] as? Double ?? 0

        let grid = createTickerPills(open: open, prevClose: prevClose, low: low, high: high)
        contentPillsStack.addArrangedSubview(grid)

        let changePill = tickerChangePill(price: price, change: change, percentChange: percentChange)
        contentPillsStack.addArrangedSubview(changePill)

        contentPillsStack.isHidden = false
        preferredContentSize = CGSize(width: 360, height: 460)
        view.setNeedsLayout()
        view.layoutIfNeeded()
        return true
    }

    private func setupBudgetCards(userInfo: [AnyHashable: Any]) -> Bool {
        guard userInfo["budgetIncome"] != nil else { return false }
        let income = userInfo["budgetIncome"] as? Double ?? 0
        let spent = userInfo["budgetSpent"] as? Double ?? 0
        let upcoming = userInfo["budgetUpcoming"] as? Double ?? 0
        let netWorth = userInfo["netWorth"] as? Double ?? 0
        let remaining = income - spent

        contentPillsStack.addArrangedSubview(metricRow(label: "Income", value: currencyString(income), icon: "dollarsign.circle", tint: .systemGreen))
        contentPillsStack.addArrangedSubview(metricRow(label: "Spent", value: currencyString(spent), icon: "cart", tint: .systemOrange))
        contentPillsStack.addArrangedSubview(metricRow(label: "Upcoming", value: currencyString(upcoming), icon: "calendar.badge.clock", tint: .systemBlue))
        contentPillsStack.addArrangedSubview(metricRow(label: "Remaining", value: currencyString(remaining), icon: "wallet.pass", tint: remaining >= 0 ? .systemGreen : .systemRed))
        contentPillsStack.addArrangedSubview(metricRow(label: "Net Worth", value: currencyString(netWorth), icon: "building.columns", tint: .systemPurple))

        contentPillsStack.isHidden = false
        preferredContentSize = CGSize(width: 360, height: 520)
        view.setNeedsLayout()
        view.layoutIfNeeded()
        return true
    }

    private func setupPortfolioCards(userInfo: [AnyHashable: Any], kind: String) -> Bool {
        guard userInfo["portfolioHoldings"] != nil else { return false }
        let holdings = userInfo["portfolioHoldings"] as? Double ?? 0
        let cash = userInfo["portfolioCash"] as? Double ?? 0
        let margin = userInfo["portfolioMargin"] as? Double ?? 0
        let netWorth = userInfo["netWorth"] as? Double ?? 0

        if kind == "portfolio_update" {
            let change = userInfo["netWorthChange"] as? Double ?? 0
            let direction = change >= 0 ? "↑" : "↓"
            let changeTint: UIColor = change >= 0 ? .systemGreen : .systemRed
            let changeLabel = "\(direction) \(currencyString(abs(change)))"
            contentPillsStack.addArrangedSubview(metricRow(label: "Change", value: changeLabel, icon: change >= 0 ? "arrow.up.right" : "arrow.down.forward", tint: changeTint))
            contentPillsStack.addArrangedSubview(metricRow(label: "Holdings", value: currencyString(holdings), icon: "chart.bar.fill", tint: .systemBlue))
            contentPillsStack.addArrangedSubview(metricRow(label: "Cash", value: currencyString(cash), icon: "dollarsign.circle", tint: .systemGreen))
        } else {
            contentPillsStack.addArrangedSubview(metricRow(label: "Holdings", value: currencyString(holdings), icon: "chart.bar.fill", tint: .systemBlue))
            contentPillsStack.addArrangedSubview(metricRow(label: "Cash", value: currencyString(cash), icon: "dollarsign.circle", tint: .systemGreen))
            contentPillsStack.addArrangedSubview(metricRow(label: "Margin Used", value: currencyString(margin), icon: "minus.circle", tint: .systemRed))
        }
        contentPillsStack.addArrangedSubview(metricRow(label: "Net Worth", value: currencyString(netWorth), icon: "building.columns", tint: .systemPurple))

        contentPillsStack.isHidden = false
        preferredContentSize = CGSize(width: 360, height: 460)
        view.setNeedsLayout()
        view.layoutIfNeeded()
        return true
    }

    private func setupPaymentCard(userInfo: [AnyHashable: Any]) -> Bool {
        guard userInfo["paymentAmount"] != nil else { return false }
        let amount = userInfo["paymentAmount"] as? Double ?? 0
        let date = userInfo["paymentDate"] as? String ?? "—"
        let totalUpcoming = userInfo["totalUpcoming"] as? Double ?? 0
        let netWorth = userInfo["netWorth"] as? Double ?? 0

        contentPillsStack.addArrangedSubview(metricRow(label: "Amount", value: currencyString(amount), icon: "dollarsign.circle", tint: .systemOrange))
        contentPillsStack.addArrangedSubview(metricRow(label: "Due", value: date, icon: "calendar", tint: .systemOrange))
        contentPillsStack.addArrangedSubview(metricRow(label: "30-Day Total", value: currencyString(totalUpcoming), icon: "tray.full", tint: .systemPurple))
        contentPillsStack.addArrangedSubview(metricRow(label: "Net Worth", value: currencyString(netWorth), icon: "building.columns", tint: .systemPurple))

        contentPillsStack.isHidden = false
        preferredContentSize = CGSize(width: 360, height: 460)
        view.setNeedsLayout()
        view.layoutIfNeeded()
        return true
    }

    // MARK: - Ticker pill views

    private func createTickerPills(open: Double?, prevClose: Double?, low: Double?, high: Double?) -> UIView {
        let container = UIStackView()
        container.axis = .vertical
        container.spacing = 8

        let row1 = UIStackView()
        row1.axis = .horizontal
        row1.spacing = 8
        row1.distribution = .fillEqually
        row1.addArrangedSubview(tickerPill(label: "Open", value: open, tint: .systemBlue, icon: "arrow.up.right"))
        row1.addArrangedSubview(tickerPill(label: "Prev", value: prevClose, tint: .systemPurple, icon: "clock.fill"))

        let row2 = UIStackView()
        row2.axis = .horizontal
        row2.spacing = 8
        row2.distribution = .fillEqually
        row2.addArrangedSubview(tickerPill(label: "Low", value: low, tint: .systemPink, icon: "arrow.down"))
        row2.addArrangedSubview(tickerPill(label: "High", value: high, tint: .systemGreen, icon: "arrow.up"))

        container.addArrangedSubview(row1)
        container.addArrangedSubview(row2)

        return container
    }

    private func tickerPill(label: String, value: Double?, tint: UIColor, icon: String) -> UIView {
        let view = UIView()
        view.backgroundColor = tint.withAlphaComponent(0.08)
        view.layer.cornerRadius = 12
        view.clipsToBounds = true

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 6
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        let iconImg = UIImageView(image: UIImage(systemName: icon))
        iconImg.contentMode = .scaleAspectFit
        iconImg.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 11, weight: .bold)
        iconImg.tintColor = tint
        iconImg.backgroundColor = tint.withAlphaComponent(0.14)
        iconImg.layer.cornerRadius = 12
        iconImg.clipsToBounds = true
        iconImg.translatesAutoresizingMaskIntoConstraints = false
        iconImg.widthAnchor.constraint(equalToConstant: 24).isActive = true
        iconImg.heightAnchor.constraint(equalToConstant: 24).isActive = true

        let textStack = UIStackView()
        textStack.axis = .vertical
        textStack.spacing = 1

        let labelLbl = UILabel()
        labelLbl.text = label
        labelLbl.font = .systemFont(ofSize: 11, weight: .semibold)
        labelLbl.textColor = .secondaryLabel

        let valueLbl = UILabel()
        if let v = value {
            valueLbl.text = currencyString(v)
        } else {
            valueLbl.text = "N/A"
            valueLbl.textColor = .secondaryLabel
        }
        valueLbl.font = .systemFont(ofSize: 13, weight: .bold)
        valueLbl.textColor = .label
        valueLbl.adjustsFontSizeToFitWidth = true
        valueLbl.minimumScaleFactor = 0.7

        textStack.addArrangedSubview(labelLbl)
        textStack.addArrangedSubview(valueLbl)

        stack.addArrangedSubview(iconImg)
        stack.addArrangedSubview(textStack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8),
        ])

        return view
    }

    private func tickerChangePill(price: Double, change: Double, percentChange: Double) -> UIView {
        let view = UIView()
        view.backgroundColor = .secondarySystemBackground
        view.layer.cornerRadius = 10
        view.clipsToBounds = true

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        let isPositive = change >= 0
        let tint: UIColor = isPositive ? .systemGreen : .systemRed
        let directionIcon = isPositive ? "arrow.up" : "arrow.down"

        let arrow = UIImageView(image: UIImage(systemName: directionIcon))
        arrow.contentMode = .scaleAspectFit
        arrow.tintColor = tint
        arrow.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 14, weight: .bold)
        arrow.setContentHuggingPriority(.required, for: .horizontal)

        let priceLbl = UILabel()
        priceLbl.text = currencyString(price)
        priceLbl.font = .systemFont(ofSize: 16, weight: .bold)
        priceLbl.textColor = .label

        let changeLbl = UILabel()
        let changeStr = "\(isPositive ? "+" : "")\(currencyString(abs(change))) (\(String(format: "%.2f", percentChange))%)"
        changeLbl.text = changeStr
        changeLbl.font = .systemFont(ofSize: 12, weight: .semibold)
        changeLbl.textColor = tint

        let changeBg = UIView()
        changeBg.backgroundColor = tint.withAlphaComponent(0.12)
        changeBg.layer.cornerRadius = 8
        changeBg.clipsToBounds = true
        changeLbl.translatesAutoresizingMaskIntoConstraints = false
        changeBg.addSubview(changeLbl)
        NSLayoutConstraint.activate([
            changeLbl.leadingAnchor.constraint(equalTo: changeBg.leadingAnchor, constant: 8),
            changeLbl.trailingAnchor.constraint(equalTo: changeBg.trailingAnchor, constant: -8),
            changeLbl.topAnchor.constraint(equalTo: changeBg.topAnchor, constant: 4),
            changeLbl.bottomAnchor.constraint(equalTo: changeBg.bottomAnchor, constant: -4),
        ])

        stack.addArrangedSubview(arrow)
        stack.addArrangedSubview(priceLbl)
        stack.addArrangedSubview(UIView())
        stack.addArrangedSubview(changeBg)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -10),
        ])

        return view
    }

    // MARK: - Metric card row

    private func metricRow(label: String, value: String, icon: String, tint: UIColor) -> UIView {
        let view = UIView()
        view.backgroundColor = .systemBackground
        view.layer.cornerRadius = 10
        view.clipsToBounds = true

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        let iconImg = UIImageView(image: UIImage(systemName: icon))
        iconImg.contentMode = .scaleAspectFit
        iconImg.tintColor = tint
        iconImg.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        iconImg.setContentHuggingPriority(.required, for: .horizontal)

        let labelLbl = UILabel()
        labelLbl.text = label
        labelLbl.font = .preferredFont(forTextStyle: .subheadline)
        labelLbl.textColor = .secondaryLabel

        let valueLbl = UILabel()
        valueLbl.text = value
        valueLbl.font = .systemFont(ofSize: UIFont.preferredFont(forTextStyle: .subheadline).pointSize, weight: .semibold)
        valueLbl.textColor = .label
        valueLbl.setContentHuggingPriority(.required, for: .horizontal)
        valueLbl.setContentCompressionResistancePriority(.required, for: .horizontal)
        valueLbl.adjustsFontSizeToFitWidth = true
        valueLbl.minimumScaleFactor = 0.8

        stack.addArrangedSubview(iconImg)
        stack.addArrangedSubview(labelLbl)
        stack.addArrangedSubview(UIView())
        stack.addArrangedSubview(valueLbl)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -10),
            view.heightAnchor.constraint(greaterThanOrEqualToConstant: 36),
        ])

        return view
    }

    // MARK: - Helpers

    private func currencyString(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: NSNumber(value: value)) ?? "$0"
    }

    private func rowView(text: String) -> UIView {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = text
        label.textColor = .label
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.numberOfLines = 2
        label.adjustsFontForContentSizeCategory = true

        let row = UIView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.backgroundColor = .systemBackground
        row.layer.cornerRadius = 10
        row.layer.masksToBounds = true
        row.addSubview(label)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -10),
            label.topAnchor.constraint(equalTo: row.topAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -8),
            row.heightAnchor.constraint(greaterThanOrEqualToConstant: 38)
        ])

        return row
    }

    private func lines(from body: String) -> [String] {
        body
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func fallbackTitle(for kind: String) -> String {
        switch kind {
        case "portfolio_snapshot", "portfolio_update":
            return "Portfolio Snapshot"
        case "ticker_alert":
            return "Ticker Alert"
        case "payment_reminder":
            return "Payment Reminder"
        default:
            return "Money Snapshot"
        }
    }

    private func fallbackChartTitle(for kind: String) -> String {
        switch kind {
        case "portfolio_snapshot", "portfolio_update":
            return "Portfolio Chart"
        case "ticker_alert":
            return "Price Chart"
        case "payment_reminder":
            return "Payment Chart"
        default:
            return "Budget Chart"
        }
    }

    private func iconName(for kind: String) -> String {
        switch kind {
        case "portfolio_snapshot", "portfolio_update":
            return "chart.pie.fill"
        case "ticker_alert":
            return "chart.line.uptrend.xyaxis"
        case "payment_reminder":
            return "calendar.badge.clock"
        default:
            return "dollarsign.circle.fill"
        }
    }

    private func tintColor(for kind: String) -> UIColor {
        switch kind {
        case "portfolio_snapshot", "portfolio_update":
            return .systemGreen
        case "ticker_alert":
            return .systemBlue
        case "payment_reminder":
            return .systemOrange
        default:
            return .systemPurple
        }
    }
}

private final class SnapshotChartView: UIView {
    enum ChartStyle {
        case bars
        case sparkline
    }

    private var labels: [String] = []
    private var values: [Double] = []
    private var style: ChartStyle = .bars
    private var tint: UIColor = .systemPurple

    func configure(labels: [String], values: [Double], style: ChartStyle, tintColor: UIColor) {
        self.labels = labels
        self.values = values.map { max($0, 0) }
        self.style = style
        self.tint = tintColor
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.clear(rect)

        let inset = UIEdgeInsets(top: 14, left: 14, bottom: 28, right: 14)
        let plot = rect.inset(by: inset)
        UIColor.tertiarySystemFill.setFill()
        UIBezierPath(roundedRect: plot, cornerRadius: 10).fill()

        switch style {
        case .bars:
            drawBars(in: plot)
        case .sparkline:
            drawSparkline(in: plot)
        }
    }

    private func drawBars(in plot: CGRect) {
        guard !values.isEmpty else {
            drawEmpty(in: plot)
            return
        }

        let maxValue = max(values.max() ?? 1, 1)
        let count = min(values.count, labels.count)
        let gap: CGFloat = 10
        let barWidth = max((plot.width - CGFloat(max(count - 1, 0)) * gap) / CGFloat(max(count, 1)), 10)

        for index in 0..<count {
            let value = values[index]
            let ratio = CGFloat(value / maxValue)
            let height = max(plot.height * ratio, 4)
            let x = plot.minX + CGFloat(index) * (barWidth + gap)
            let barRect = CGRect(x: x, y: plot.maxY - height, width: barWidth, height: height)

            tint.withAlphaComponent(index == 0 ? 0.95 : 0.68).setFill()
            UIBezierPath(roundedRect: barRect, cornerRadius: min(7, barWidth / 2)).fill()

            drawText(
                abbreviatedCurrency(value),
                in: CGRect(x: x - 4, y: max(plot.minY + 4, barRect.minY - 20), width: barWidth + 8, height: 14),
                font: .systemFont(ofSize: 10, weight: .semibold),
                color: .label,
                alignment: .center
            )
            drawText(
                labels[index],
                in: CGRect(x: x - 4, y: plot.maxY + 6, width: barWidth + 8, height: 14),
                font: .systemFont(ofSize: 9, weight: .medium),
                color: .secondaryLabel,
                alignment: .center
            )
        }
    }

    private func drawSparkline(in plot: CGRect) {
        guard values.count >= 2 else {
            drawBars(in: plot)
            return
        }

        let minValue = values.min() ?? 0
        let maxValue = max(values.max() ?? 1, minValue + 1)
        let range = max(maxValue - minValue, 0.0001)
        let step = plot.width / CGFloat(values.count - 1)
        let path = UIBezierPath()

        for (index, value) in values.enumerated() {
            let x = plot.minX + CGFloat(index) * step
            let y = plot.maxY - CGFloat((value - minValue) / range) * plot.height
            let point = CGPoint(x: x, y: y)
            index == 0 ? path.move(to: point) : path.addLine(to: point)
        }

        tint.setStroke()
        path.lineWidth = 3
        path.lineJoinStyle = .round
        path.lineCapStyle = .round
        path.stroke()

        for (index, value) in values.enumerated() {
            let x = plot.minX + CGFloat(index) * step
            let y = plot.maxY - CGFloat((value - minValue) / range) * plot.height
            tint.setFill()
            UIBezierPath(ovalIn: CGRect(x: x - 4, y: y - 4, width: 8, height: 8)).fill()

            if index < labels.count {
                drawText(
                    labels[index],
                    in: CGRect(x: x - 24, y: plot.maxY + 6, width: 48, height: 14),
                    font: .systemFont(ofSize: 9, weight: .medium),
                    color: .secondaryLabel,
                    alignment: .center
                )
            }
        }

        drawText(
            "\(abbreviatedCurrency(minValue)) - \(abbreviatedCurrency(maxValue))",
            in: CGRect(x: plot.minX + 8, y: plot.minY + 6, width: plot.width - 16, height: 16),
            font: .systemFont(ofSize: 10, weight: .semibold),
            color: .secondaryLabel,
            alignment: .left
        )
    }

    private func drawEmpty(in plot: CGRect) {
        drawText(
            "No chart data",
            in: plot,
            font: .systemFont(ofSize: 13, weight: .semibold),
            color: .secondaryLabel,
            alignment: .center
        )
    }

    private func drawText(_ text: String, in rect: CGRect, font: UIFont, color: UIColor, alignment: NSTextAlignment) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        NSString(string: text).draw(in: rect, withAttributes: attributes)
    }

    private func abbreviatedCurrency(_ value: Double) -> String {
        let absValue = abs(value)
        if absValue >= 1_000_000 {
            return "$\(String(format: "%.1f", value / 1_000_000))M"
        }
        if absValue >= 1_000 {
            return "$\(String(format: "%.1f", value / 1_000))K"
        }
        return "$\(String(format: "%.0f", value))"
    }
}
