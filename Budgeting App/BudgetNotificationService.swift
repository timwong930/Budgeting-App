import BackgroundTasks
import Foundation
import UIKit
import UserNotifications

final class BudgetAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        BudgetNotificationService.registerNotificationCategories()
        BudgetBackgroundRefreshCoordinator.shared.register()
        return true
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        BudgetBackgroundRefreshCoordinator.shared.scheduleAppRefresh()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        handleNotificationResponse(response)
        completionHandler()
    }

    private func handleNotificationResponse(_ response: UNNotificationResponse) {
        let userInfo = response.notification.request.content.userInfo
        if let ticker = userInfo["ticker"] as? String {
            PendingDeepLink.action = .ticker(ticker)
        } else if let tabRaw = userInfo["tab"] as? String,
                  let mode = BudgetMode(rawValue: tabRaw) {
            PendingDeepLink.action = .tab(mode)
        }
    }
}

@MainActor
final class BudgetBackgroundRefreshCoordinator {
    static let shared = BudgetBackgroundRefreshCoordinator()

    static let taskIdentifier = "Timothy-Wong.Budgeting-App.background-refresh"

    private let marketDataService = MarketDataService()
    private var isRegistered = false
    private var isRefreshing = false

    private init() {}

    func register() {
        guard !isRegistered else { return }
        isRegistered = BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.taskIdentifier,
            using: nil
        ) { task in
            guard let appRefreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }

            Task { @MainActor in
                await self.handle(task: appRefreshTask)
            }
        }
    }

    func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 5 * 60)

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            #if DEBUG
            print("Unable to schedule background refresh: \(error.localizedDescription)")
            #endif
        }
    }

    private func handle(task: BGAppRefreshTask) async {
        scheduleAppRefresh()

        let refreshTask = Task { @MainActor in
            await refreshBudgetInBackground()
        }

        task.expirationHandler = {
            refreshTask.cancel()
        }

        let success = await refreshTask.value
        task.setTaskCompleted(success: success)
    }

    @discardableResult
    func refreshBudgetInBackground() async -> Bool {
        guard !isRefreshing else { return false }
        isRefreshing = true
        defer { isRefreshing = false }

        let budget = BudgetModel()
        let previousNetWorth = BudgetNotificationService.netWorth(for: budget)
        let refreshed = await refreshPortfolioQuotes(for: budget)
        await BudgetNotificationService.shared.sendWatchlistAlertsIfNeeded(
            budget: budget,
            marketDataService: marketDataService
        )

        await BudgetNotificationService.shared.rescheduleNotifications(for: budget)

        if refreshed {
            let updatedNetWorth = BudgetNotificationService.netWorth(for: budget)
            await BudgetNotificationService.shared.sendPortfolioUpdateIfNeeded(
                previousNetWorth: previousNetWorth,
                updatedNetWorth: updatedNetWorth,
                budget: budget
            )
        }

        return true
    }

    private func refreshPortfolioQuotes(for budget: BudgetModel) async -> Bool {
        guard budget.marketDataSettings.canFetchMarketData else { return false }

        let tickers = Array(Set(budget.holdings.map { $0.ticker.uppercased() })).filter { !$0.isEmpty }
        guard !tickers.isEmpty else { return false }

        var didRefresh = false
        for ticker in tickers {
            guard !Task.isCancelled else { return didRefresh }

            do {
                let details = try await marketDataService.fetchQuoteDetails(
                    ticker: ticker,
                    settings: budget.marketDataSettings
                )
                budget.cachedQuotes[ticker] = CachedQuote(ticker: ticker, price: details.price, updatedAt: Date())
                for index in budget.holdings.indices where budget.holdings[index].ticker.uppercased() == ticker {
                    budget.holdings[index].currentPrice = details.price
                    if let annualDividend = details.annualDividendPerShare, annualDividend >= 0 {
                        budget.holdings[index].annualDividendPerShare = annualDividend
                    }
                }
                didRefresh = true
            } catch {
                continue
            }
        }

        budget.synchronizeLegacyMarginStateFromLedger()
        BudgetNotificationService.recordPortfolioValueHistory(for: budget)
        return didRefresh
    }
}

@MainActor
final class BudgetNotificationService {
    static let shared = BudgetNotificationService()

    private let center = UNUserNotificationCenter.current()
    private let calendar = Calendar.current

    private init() {}

    static func registerNotificationCategories() {
        let categories: Set<UNNotificationCategory> = [
            UNNotificationCategory(
                identifier: "budget_snapshot",
                actions: [
                    UNNotificationAction(identifier: "open_home", title: "Open Snapshot", options: [.foreground])
                ],
                intentIdentifiers: [],
                hiddenPreviewsBodyPlaceholder: "Money snapshot",
                options: [.customDismissAction]
            ),
            UNNotificationCategory(
                identifier: "portfolio_snapshot",
                actions: [
                    UNNotificationAction(identifier: "open_margin", title: "Open Portfolio", options: [.foreground])
                ],
                intentIdentifiers: [],
                hiddenPreviewsBodyPlaceholder: "Portfolio snapshot",
                options: [.customDismissAction]
            ),
            UNNotificationCategory(
                identifier: "portfolio_update",
                actions: [
                    UNNotificationAction(identifier: "open_margin", title: "Open Portfolio", options: [.foreground])
                ],
                intentIdentifiers: [],
                hiddenPreviewsBodyPlaceholder: "Portfolio update",
                options: [.customDismissAction]
            ),
            UNNotificationCategory(
                identifier: "ticker_alert",
                actions: [
                    UNNotificationAction(identifier: "open_ticker", title: "Open Ticker", options: [.foreground])
                ],
                intentIdentifiers: [],
                hiddenPreviewsBodyPlaceholder: "Ticker alert",
                options: [.customDismissAction]
            ),
            UNNotificationCategory(
                identifier: "payment_reminder",
                actions: [
                    UNNotificationAction(identifier: "open_budget", title: "Open Budget", options: [.foreground])
                ],
                intentIdentifiers: [],
                hiddenPreviewsBodyPlaceholder: "Payment reminder",
                options: [.customDismissAction]
            )
        ]
        UNUserNotificationCenter.current().setNotificationCategories(categories)
    }

    func requestAuthorizationIfNeeded() async {
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }

        do {
            _ = try await center.requestAuthorization(options: [.alert, .badge, .sound])
        } catch {
            #if DEBUG
            print("Notification authorization failed: \(error.localizedDescription)")
            #endif
        }
    }

    func rescheduleNotifications(for budget: BudgetModel) async {
        await requestAuthorizationIfNeeded()

        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

        let pending = await center.pendingNotificationRequests()
        let identifiers = pending
            .map(\.identifier)
            .filter { $0.hasPrefix("budget.") }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)

        var requests: [UNNotificationRequest] = []
        requests.append(contentsOf: dailySnapshotRequests(for: budget))
        requests.append(contentsOf: upcomingPaymentRequests(for: budget))
        requests.append(contentsOf: portfolioSnapshotRequests(for: budget))

        for request in requests.prefix(48) {
            do {
                try await center.add(request)
            } catch {
                #if DEBUG
                print("Failed to schedule notification \(request.identifier): \(error.localizedDescription)")
                #endif
            }
        }
    }

    func sendPortfolioUpdateIfNeeded(previousNetWorth: Double, updatedNetWorth: Double, budget: BudgetModel) async {
        let difference = updatedNetWorth - previousNetWorth
        guard abs(difference) >= 100 else { return }
        guard canSendPortfolioUpdate() else { return }

        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

        let direction = difference >= 0 ? "up" : "down"
        let content = UNMutableNotificationContent()
        content.title = "Portfolio update"
        content.subtitle = "Net worth moved \(direction)"
        content.body = portfolioUpdateExpandedBody(direction: direction, difference: difference, updatedNetWorth: updatedNetWorth, budget: budget)
        content.sound = .default
        content.categoryIdentifier = "portfolio_update"
        content.threadIdentifier = "budget.portfolio"
        content.targetContentIdentifier = "portfolio_update"
        let portfolioVal = Self.grossPortfolioValue(for: budget)
        let cashVal = budget.bankAccounts.reduce(0) { $0 + $1.balance }
        content.userInfo = previewUserInfo(
            kind: "portfolio_update",
            title: content.title,
            subtitle: content.subtitle,
            lines: previewLines(from: content.body),
            chartTitle: "Net Worth Move",
            chartLabels: ["Previous", "Updated", "Portfolio", "Cash"],
            chartValues: [previousNetWorth, updatedNetWorth, portfolioVal, cashVal],
            chartStyle: "bars",
            base: ["tab": "margin", "action": "tab"]
        )
        content.userInfo["portfolioPrevious"] = previousNetWorth
        content.userInfo["portfolioCurrent"] = updatedNetWorth
        content.userInfo["portfolioHoldings"] = portfolioVal
        content.userInfo["portfolioCash"] = cashVal
        content.userInfo["netWorth"] = updatedNetWorth
        content.userInfo["netWorthChange"] = difference

        if UIApplication.shared.applicationState == .active {
            InAppNotificationService.shared.post(
                title: content.title,
                message: content.subtitle,
                tab: "margin"
            )
        }

        let request = UNNotificationRequest(
            identifier: "budget.portfolio.live.\(Int(Date().timeIntervalSince1970))",
            content: content,
            trigger: nil
        )
        try? await center.add(request)
    }

    func sendWatchlistAlertsIfNeeded(budget: BudgetModel, marketDataService: MarketDataService) async {
        await requestAuthorizationIfNeeded()

        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        guard budget.marketDataSettings.canFetchMarketData else { return }
        guard isMarketHours() else { return }

        let symbols = budget.watchlistTickers
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
            .filter { !$0.isEmpty }
        guard !symbols.isEmpty else { return }

        for (index, symbol) in symbols.enumerated() {
            if index > 0 {
                let delay = UInt64.random(in: 5...10) * 1_000_000_000
                try? await Task.sleep(nanoseconds: delay)
            }
            guard let quote = try? await marketDataService.fetchQuoteSnapshot(
                ticker: symbol,
                settings: budget.marketDataSettings
            ) else { continue }
            let alertSettings = budget.watchlistAlertSettings(for: symbol)
            guard alertSettings.isEnabled else { continue }

            let storedPrice = lastWatchlistPrice(for: symbol)
            budget.cachedQuotes[symbol] = CachedQuote(ticker: symbol, price: quote.price, updatedAt: Date())

            let alertMove: Double
            if let storedPrice, storedPrice > 0 {
                alertMove = ((quote.price - storedPrice) / storedPrice) * 100
            } else {
                alertMove = quote.percentChange
            }
            setLastWatchlistPrice(quote.price, for: symbol)

            var reasons: [String] = []
            if abs(alertMove) >= alertSettings.percentMoveThreshold {
                reasons.append("\(Self.percent(abs(alertMove))) move")
            }
            if let priceAbove = alertSettings.priceAbove, quote.price >= priceAbove {
                reasons.append("above \(Self.currency(priceAbove))")
            }
            if let priceBelow = alertSettings.priceBelow, quote.price <= priceBelow {
                reasons.append("below \(Self.currency(priceBelow))")
            }
            guard !reasons.isEmpty else { continue }
            guard canSendWatchlistAlert(symbol: symbol, triggerKey: reasons.joined(separator: "|")) else { continue }

            let content = UNMutableNotificationContent()
            content.title = "\(symbol) alert: \(reasons.joined(separator: ", "))"
            content.subtitle = "Price \(Self.currency(quote.price))"
            content.body = tickerAlertExpandedBody(symbol: symbol, quote: quote, move: alertMove)
            content.sound = .default
            content.categoryIdentifier = "ticker_alert"
            content.threadIdentifier = "budget.watchlist.\(symbol)"
            content.targetContentIdentifier = "ticker_\(symbol)"
            content.userInfo = previewUserInfo(
                kind: "ticker_alert",
                title: content.title,
                subtitle: content.subtitle,
                lines: previewLines(from: content.body),
                chartTitle: "\(symbol) Session",
                chartLabels: ["Prev", "Open", "Low", "Now", "High"],
                chartValues: [
                    quote.previousClose ?? quote.price,
                    quote.open ?? quote.price,
                    quote.low ?? min(quote.price, quote.previousClose ?? quote.price),
                    quote.price,
                    quote.high ?? max(quote.price, quote.previousClose ?? quote.price)
                ],
                chartStyle: "sparkline",
                base: ["ticker": symbol, "action": "ticker"]
            )
            if let open = quote.open { content.userInfo["tickerOpen"] = open }
            if let prevClose = quote.previousClose { content.userInfo["tickerPrevClose"] = prevClose }
            if let low = quote.low { content.userInfo["tickerLow"] = low }
            if let high = quote.high { content.userInfo["tickerHigh"] = high }
            content.userInfo["tickerPrice"] = quote.price
            content.userInfo["tickerChange"] = quote.change
            content.userInfo["tickerPercentChange"] = quote.percentChange

            if UIApplication.shared.applicationState == .active {
                InAppNotificationService.shared.post(
                    title: "\(symbol) alert",
                    message: reasons.joined(separator: ", "),
                    symbol: symbol
                )
            }

            let request = UNNotificationRequest(
                identifier: "budget.watchlist.\(symbol).\(Int(Date().timeIntervalSince1970))",
                content: content,
                trigger: nil
            )
            try? await center.add(request)
        }
    }

    private func dailySnapshotRequests(for budget: BudgetModel) -> [UNNotificationRequest] {
        [
            dailySnapshotRequest(for: budget, hour: 8, minute: 0, label: "morning"),
            dailySnapshotRequest(for: budget, hour: 18, minute: 0, label: "evening")
        ]
    }

    private func dailySnapshotRequest(for budget: BudgetModel, hour: Int, minute: Int, label: String) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = label == "morning" ? "Money snapshot" : "Evening budget check"
        content.subtitle = Self.currency(Self.netWorth(for: budget))
        content.body = budgetSnapshotExpandedBody(budget: budget, label: label)
        content.sound = .default
        content.categoryIdentifier = "budget_snapshot"
        content.threadIdentifier = "budget.snapshot"
        content.targetContentIdentifier = "budget_snapshot_\(label)"
        let budgetChart = budgetSnapshotChart(for: budget)
        let netWorth = Self.netWorth(for: budget)
        content.userInfo = previewUserInfo(
            kind: "budget_snapshot",
            title: content.title,
            subtitle: content.subtitle,
            lines: previewLines(from: content.body),
            chartTitle: "Budget Snapshot",
            chartLabels: budgetChart.labels,
            chartValues: budgetChart.values,
            chartStyle: "bars",
            base: ["tab": "home", "action": "tab"]
        )
        let chartVals = budgetChart.values
        if chartVals.count >= 3 {
            content.userInfo["budgetIncome"] = chartVals[0]
            content.userInfo["budgetSpent"] = chartVals[1]
            content.userInfo["budgetUpcoming"] = chartVals[2]
        }
        content.userInfo["netWorth"] = netWorth
        if let attachment = snapshotPreviewAttachment(
            identifier: "budget-snapshot-\(label)",
            title: content.title,
            subtitle: content.subtitle,
            lines: previewLines(from: content.body),
            chartLabels: budgetChart.labels,
            chartValues: budgetChart.values,
            tint: .systemPurple
        ) {
            content.attachments = [attachment]
        }

        var dateComponents = DateComponents()
        dateComponents.hour = hour
        dateComponents.minute = minute

        return UNNotificationRequest(
            identifier: "budget.snapshot.\(label)",
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        )
    }

    private func upcomingPaymentRequests(for budget: BudgetModel) -> [UNNotificationRequest] {
        let totalUpcoming = upcomingItems(for: budget, withinDays: 30).reduce(0) { $0 + $1.amount }
        let netWorth = Self.netWorth(for: budget)
        return upcomingItems(for: budget, withinDays: 30).prefix(24).compactMap { item in
            guard let triggerDate = reminderDate(for: item.date) else { return nil }

            let content = UNMutableNotificationContent()
            content.title = item.isIncome ? "Incoming payment soon" : "Payment coming up"
            content.subtitle = "\(Self.currency(item.amount)) on \(Self.shortDate(item.date))"
            content.body = paymentReminderExpandedBody(item: item, budget: budget)
            content.sound = .default
            content.categoryIdentifier = "payment_reminder"
            content.threadIdentifier = "budget.payments"
            content.targetContentIdentifier = "payment_\(item.id)"
            content.userInfo = previewUserInfo(
                kind: "payment_reminder",
                title: content.title,
                subtitle: content.subtitle,
                lines: previewLines(from: content.body),
                chartTitle: "Upcoming Payments",
                chartLabels: ["This", "30-Day Total"],
                chartValues: [item.amount, totalUpcoming],
                chartStyle: "bars",
                base: ["tab": "budget", "action": "tab"]
            )
            content.userInfo["paymentAmount"] = item.amount
            content.userInfo["paymentDate"] = Self.shortDate(item.date)
            content.userInfo["totalUpcoming"] = totalUpcoming
            content.userInfo["netWorth"] = netWorth

            return UNNotificationRequest(
                identifier: "budget.upcoming.\(item.id)",
                content: content,
                trigger: UNCalendarNotificationTrigger(
                    dateMatching: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: triggerDate),
                    repeats: false
                )
            )
        }
    }

    private func portfolioSnapshotRequests(for budget: BudgetModel) -> [UNNotificationRequest] {
        [11, 15].map { hour in
            let content = UNMutableNotificationContent()
            content.title = "Portfolio snapshot"
            content.subtitle = Self.currency(Self.netWorth(for: budget))
            content.body = portfolioSnapshotExpandedBody(budget: budget)
            content.sound = .default
            content.categoryIdentifier = "portfolio_snapshot"
            content.threadIdentifier = "budget.portfolio"
            content.targetContentIdentifier = "portfolio_snapshot_\(hour)"
            let portfolioChart = portfolioSnapshotChart(for: budget)
            content.userInfo = previewUserInfo(
                kind: "portfolio_snapshot",
                title: content.title,
                subtitle: content.subtitle,
                lines: previewLines(from: content.body),
                chartTitle: "Portfolio Mix",
                chartLabels: portfolioChart.labels,
                chartValues: portfolioChart.values,
                chartStyle: "bars",
                base: ["tab": "margin", "action": "tab"]
            )
            let pChartVals = portfolioChart.values
            if pChartVals.count >= 3 {
                content.userInfo["portfolioHoldings"] = pChartVals[0]
                content.userInfo["portfolioCash"] = pChartVals[1]
                content.userInfo["portfolioMargin"] = pChartVals[2]
            }
            content.userInfo["netWorth"] = Self.netWorth(for: budget)

            var dateComponents = DateComponents()
            dateComponents.hour = hour
            dateComponents.minute = 30

            return UNNotificationRequest(
                identifier: "budget.portfolio.snapshot.\(hour)",
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
            )
        }
    }

    private func canSendWatchlistAlert(symbol: String, triggerKey: String) -> Bool {
        let key = "budget.watchlist.alert.\(symbol).\(triggerKey)"
        let now = Date()
        let lastSent = UserDefaults.standard.object(forKey: key) as? Date
        if let lastSent, now.timeIntervalSince(lastSent) < 15 * 60 {
            return false
        }
        UserDefaults.standard.set(now, forKey: key)
        return true
    }

    private func lastWatchlistPrice(for symbol: String) -> Double? {
        UserDefaults.standard.object(forKey: "budget.watchlist.lastPrice.\(symbol)") as? Double
    }

    private func setLastWatchlistPrice(_ price: Double, for symbol: String) {
        UserDefaults.standard.set(price, forKey: "budget.watchlist.lastPrice.\(symbol)")
    }

    private func canSendPortfolioUpdate() -> Bool {
        let key = "budget.portfolio.update.lastSent"
        let now = Date()
        let lastSent = UserDefaults.standard.object(forKey: key) as? Date
        if let lastSent, now.timeIntervalSince(lastSent) < 15 * 60 {
            return false
        }
        UserDefaults.standard.set(now, forKey: key)
        return true
    }

    private func isMarketHours() -> Bool {
        let calendar = Calendar.current
        let ny = TimeZone(identifier: "America/New_York") ?? calendar.timeZone
        var nyCalendar = calendar
        nyCalendar.timeZone = ny

        let now = Date()
        let components = nyCalendar.dateComponents([.hour, .minute, .weekday], from: now)
        guard let hour = components.hour, let minute = components.minute else { return false }

        if let weekday = components.weekday, weekday == 1 || weekday == 7 {
            return false
        }

        if isUSHoliday(now, calendar: nyCalendar) {
            return false
        }

        let timeInMinutes = hour * 60 + minute
        let premarketOpen = 4 * 60
        let marketClose = isEarlyCloseDay(now, calendar: nyCalendar) ? 13 * 60 : 16 * 60

        return timeInMinutes >= premarketOpen && timeInMinutes < marketClose
    }

    private func isUSHoliday(_ date: Date, calendar: Calendar) -> Bool {
        let components = calendar.dateComponents([.month, .day, .weekday, .year], from: date)
        guard let month = components.month, let day = components.day, let weekday = components.weekday else { return false }

        if month == 1 && day == 1 { return true }
        if month == 6 && day == 19 { return true }
        if month == 7 && day == 4 { return true }
        if month == 12 && day == 25 { return true }

        if month == 1 && weekday == 2 {
            let weekOfMonth = (day - 1) / 7 + 1
            if weekOfMonth == 3 { return true }
        }

        if month == 2 && weekday == 2 {
            let weekOfMonth = (day - 1) / 7 + 1
            if weekOfMonth == 3 { return true }
        }

        if month == 5 && weekday == 2 {
            let range = calendar.range(of: .day, in: .month, for: date)?.count ?? 31
            if day > range - 7 { return true }
        }

        if month == 9 && weekday == 2 {
            let weekOfMonth = (day - 1) / 7 + 1
            if weekOfMonth == 1 { return true }
        }

        if month == 11 && weekday == 5 {
            let weekOfMonth = (day - 1) / 7 + 1
            if weekOfMonth == 4 { return true }
        }

        if let year = components.year {
            let easter = easterDate(year: year, calendar: calendar)
            if calendar.isDate(date, equalTo: calendar.date(byAdding: .day, value: -2, to: easter) ?? date, toGranularity: .day) {
                return true
            }
        }

        return false
    }

    private func isEarlyCloseDay(_ date: Date, calendar: Calendar) -> Bool {
        let components = calendar.dateComponents([.month, .day, .weekday, .year], from: date)
        guard let month = components.month, let day = components.day, let weekday = components.weekday else { return false }

        if month == 12 && day == 24 { return true }

        if month == 11 && weekday == 6 {
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: date) else { return false }
            let prevComponents = calendar.dateComponents([.month, .day, .weekday], from: previousDay)
            if prevComponents.month == 11, let prevDay = prevComponents.day, let prevWeekday = prevComponents.weekday {
                let prevWeekOfMonth = (prevDay - 1) / 7 + 1
                if prevWeekOfMonth == 4 && prevWeekday == 5 { return true }
            }
        }

        return false
    }

    private func easterDate(year: Int, calendar: Calendar) -> Date {
        let a = year % 19
        let b = year / 100
        let c = year % 100
        let d = b / 4
        let e = b % 4
        let f = (b + 8) / 25
        let g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4
        let k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let month = (h + l - 7 * m + 114) / 31
        let day = ((h + l - 7 * m + 114) % 31) + 1
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return calendar.date(from: components) ?? Date()
    }

    private func tickerAlertExpandedBody(symbol: String, quote: MarketQuoteSnapshot, move: Double) -> String {
        let direction = move >= 0 ? "gained" : "fell"
        let price = Self.currency(quote.price)
        let dayChange = Self.currency(abs(quote.change))
        let range: String
        if let low = quote.low, let high = quote.high {
            range = " Range: \(Self.currency(low))-\(Self.currency(high))."
        } else {
            range = ""
        }
        return "\(symbol) \(direction) \(Self.percent(abs(move))) and is trading at \(price). Day change: \(dayChange).\(range)\nOpen: \(quote.open.map(Self.currency) ?? "—")  Prev close: \(quote.previousClose.map(Self.currency) ?? "—")"
    }

    private func previewUserInfo(
        kind: String,
        title: String,
        subtitle: String,
        lines: [String],
        chartTitle: String,
        chartLabels: [String],
        chartValues: [Double],
        chartStyle: String,
        base: [String: String]
    ) -> [AnyHashable: Any] {
        var userInfo: [AnyHashable: Any] = base
        userInfo["previewKind"] = kind
        userInfo["previewTitle"] = title
        userInfo["previewSubtitle"] = subtitle
        userInfo["previewLines"] = lines
        userInfo["chartTitle"] = chartTitle
        userInfo["chartLabels"] = chartLabels
        userInfo["chartValues"] = chartValues
        userInfo["chartStyle"] = chartStyle
        return userInfo
    }

    private func cleanupStalePreviews(in directory: URL) {
        let maxAge: TimeInterval = 7 * 24 * 60 * 60
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }
        let now = Date()
        for file in files where file.pathExtension == "png" {
            guard let attrs = try? file.resourceValues(forKeys: [.contentModificationDateKey]),
                  let modDate = attrs.contentModificationDate,
                  now.timeIntervalSince(modDate) > maxAge else { continue }
            try? FileManager.default.removeItem(at: file)
        }
    }

    private func snapshotPreviewAttachment(
        identifier: String,
        title: String,
        subtitle: String,
        lines: [String],
        chartLabels: [String],
        chartValues: [Double],
        tint: UIColor
    ) -> UNNotificationAttachment? {
        let size = CGSize(width: 900, height: 520)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = true

        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            let rect = CGRect(origin: .zero, size: size)
            UIColor.systemBackground.setFill()
            context.fill(rect)

            let card = rect.insetBy(dx: 32, dy: 28)
            UIColor.secondarySystemBackground.setFill()
            UIBezierPath(roundedRect: card, cornerRadius: 34).fill()

            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 44, weight: .bold),
                .foregroundColor: UIColor.label
            ]
            NSString(string: title).draw(
                in: CGRect(x: card.minX + 34, y: card.minY + 28, width: card.width - 68, height: 54),
                withAttributes: titleAttributes
            )

            let subtitleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedDigitSystemFont(ofSize: 38, weight: .semibold),
                .foregroundColor: tint
            ]
            NSString(string: subtitle).draw(
                in: CGRect(x: card.minX + 34, y: card.minY + 88, width: card.width - 68, height: 48),
                withAttributes: subtitleAttributes
            )

            let chartRect = CGRect(x: card.minX + 34, y: card.minY + 158, width: card.width - 68, height: 170)
            UIColor.systemBackground.setFill()
            UIBezierPath(roundedRect: chartRect, cornerRadius: 22).fill()
            drawAttachmentBars(labels: chartLabels, values: chartValues, in: chartRect.insetBy(dx: 24, dy: 22), tint: tint)

            let lineAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 28, weight: .semibold),
                .foregroundColor: UIColor.label
            ]
            for (index, line) in lines.prefix(4).enumerated() {
                NSString(string: line).draw(
                    in: CGRect(x: card.minX + 34, y: chartRect.maxY + 24 + CGFloat(index * 40), width: card.width - 68, height: 36),
                    withAttributes: lineAttributes
                )
            }
        }

        guard let data = image.pngData() else { return nil }
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("NotificationPreviews", isDirectory: true)
        guard let directory else { return nil }

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            cleanupStalePreviews(in: directory)
            let url = directory.appendingPathComponent("\(identifier).png")
            try data.write(to: url, options: [.atomic])
            return try UNNotificationAttachment(identifier: identifier, url: url)
        } catch {
            #if DEBUG
            print("Failed to create notification preview attachment: \(error.localizedDescription)")
            #endif
            return nil
        }
    }

    private func drawAttachmentBars(labels: [String], values: [Double], in rect: CGRect, tint: UIColor) {
        guard !values.isEmpty else { return }
        let count = min(values.count, labels.count)
        guard count > 0 else { return }

        let maxValue = max(values.max() ?? 1, 1)
        let gap: CGFloat = 22
        let barWidth = max((rect.width - CGFloat(count - 1) * gap) / CGFloat(count), 20)
        let labelAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 18, weight: .semibold),
            .foregroundColor: UIColor.secondaryLabel
        ]
        let valueAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedDigitSystemFont(ofSize: 18, weight: .bold),
            .foregroundColor: UIColor.label
        ]

        for index in 0..<count {
            let value = max(values[index], 0)
            let ratio = CGFloat(value / maxValue)
            let x = rect.minX + CGFloat(index) * (barWidth + gap)
            let barHeight = max((rect.height - 38) * ratio, 8)
            let barRect = CGRect(x: x, y: rect.maxY - 34 - barHeight, width: barWidth, height: barHeight)
            tint.withAlphaComponent(index == 0 ? 0.95 : 0.65).setFill()
            UIBezierPath(roundedRect: barRect, cornerRadius: min(12, barWidth / 2)).fill()

            NSString(string: Self.abbreviatedCurrency(value)).draw(
                in: CGRect(x: x - 10, y: max(rect.minY, barRect.minY - 24), width: barWidth + 20, height: 22),
                withAttributes: valueAttributes
            )
            NSString(string: labels[index]).draw(
                in: CGRect(x: x - 10, y: rect.maxY - 24, width: barWidth + 20, height: 22),
                withAttributes: labelAttributes
            )
        }
    }

    private static func abbreviatedCurrency(_ value: Double) -> String {
        let absValue = abs(value)
        if absValue >= 1_000_000 {
            return "$\(String(format: "%.1f", value / 1_000_000))M"
        }
        if absValue >= 1_000 {
            return "$\(String(format: "%.1f", value / 1_000))K"
        }
        return "$\(String(format: "%.0f", value))"
    }

    private func budgetSnapshotChart(for budget: BudgetModel) -> (labels: [String], values: [Double]) {
        let now = Date()
        let monthlyIncome = budget.incomes
            .filter { calendar.isDate($0.date, equalTo: now, toGranularity: .month) }
            .reduce(0) { $0 + $1.amount }
        let monthlySpent = budget.expenses
            .filter { calendar.isDate($0.date, equalTo: now, toGranularity: .month) }
            .reduce(0) { $0 + $1.amount }
        let upcomingDue = upcomingItems(for: budget, withinDays: 14).reduce(0) { $0 + $1.amount }
        return (
            ["Income", "Spent", "Upcoming"],
            [max(monthlyIncome, budget.monthlyIncome), monthlySpent, upcomingDue]
        )
    }

    private func portfolioSnapshotChart(for budget: BudgetModel) -> (labels: [String], values: [Double]) {
        let holdingsValue = budget.holdings.reduce(0) { $0 + ($1.shares * $1.currentPrice) }
        let cash = budget.portfolioSnapshot.cashBalance + budget.bankAccounts.reduce(0) { $0 + $1.balance }
        let margin = budget.portfolioSnapshot.marginUsed
        return (
            ["Holdings", "Cash", "Margin"],
            [holdingsValue, cash, margin]
        )
    }

    private func previewLines(from body: String) -> [String] {
        body
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func portfolioUpdateExpandedBody(direction: String, difference: Double, updatedNetWorth: Double, budget: BudgetModel) -> String {
        let portfolio = Self.grossPortfolioValue(for: budget)
        let cash = budget.bankAccounts.reduce(0) { $0 + $1.balance }
        return """
        Net worth: \(Self.currency(updatedNetWorth))
        Change: \(direction) \(Self.currency(abs(difference)))
        Portfolio: \(Self.currency(portfolio))
        Cash: \(Self.currency(cash))
        """
    }

    private func budgetSnapshotExpandedBody(budget: BudgetModel, label: String) -> String {
        let upcoming = upcomingItems(for: budget, withinDays: 14)
        let totalUpcoming = upcoming.reduce(0) { $0 + $1.amount }
        let lines = upcoming.prefix(5).map { "\($0.name): \(Self.currency($0.amount)) on \(Self.shortDate($0.date))" }
        let more = upcoming.count > 5 ? "\n+ \(upcoming.count - 5) more" : ""
        return """
        Net worth: \(Self.currency(Self.netWorth(for: budget)))
        Upcoming (\(upcoming.count) items):\(lines.isEmpty ? " none" : "")
        \(lines.joined(separator: "\n"))\(more)
        Total due: \(Self.currency(totalUpcoming))
        """
    }

    private func paymentReminderExpandedBody(item: UpcomingMoneyItem, budget: BudgetModel) -> String {
        let allUpcoming = upcomingItems(for: budget, withinDays: 30)
        let totalDue = allUpcoming.reduce(0) { $0 + $1.amount }
        return """
        \(item.name) — \(Self.currency(item.amount))
        Due: \(Self.shortDate(item.date))
        Net worth: \(Self.currency(Self.netWorth(for: budget)))
        Total upcoming: \(Self.currency(totalDue)) (\(allUpcoming.count) items)
        """
    }

    private func portfolioSnapshotExpandedBody(budget: BudgetModel) -> String {
        let portfolio = Self.grossPortfolioValue(for: budget)
        let positions = budget.holdings.prefix(5).map { holding in
            let val = holding.shares * holding.currentPrice
            return "\(holding.ticker.uppercased()): \(Self.currency(val))"
        }
        let more = budget.holdings.count > 5 ? "\n+ \(budget.holdings.count - 5) more positions" : ""
        return """
        Net worth: \(Self.currency(Self.netWorth(for: budget)))
        Portfolio: \(Self.currency(portfolio))
        Holdings:\(positions.isEmpty ? " none" : "")
        \(positions.joined(separator: "\n"))\(more)
        """
    }

    private func reminderDate(for dueDate: Date) -> Date? {
        let today = calendar.startOfDay(for: Date())
        let dueDay = calendar.startOfDay(for: dueDate)
        let baseDay = dueDay <= today ? dueDay : (calendar.date(byAdding: .day, value: -1, to: dueDay) ?? dueDay)
        var components = calendar.dateComponents([.year, .month, .day], from: baseDay)
        components.hour = 9
        components.minute = 0
        return calendar.date(from: components)
    }

    private func upcomingItems(for budget: BudgetModel, withinDays days: Int) -> [UpcomingMoneyItem] {
        let today = calendar.startOfDay(for: Date())
        let endDate = calendar.date(byAdding: .day, value: days, to: today) ?? today

        var items: [UpcomingMoneyItem] = []

        for payment in budget.recurringPayments where payment.isActive {
            guard let date = nextMonthlyDate(day: payment.dayOfMonth, startDate: payment.startDate, from: today),
                  date <= endDate,
                  !payment.paidOccurrenceKeys.contains(Self.occurrenceKey(for: date)) else {
                continue
            }

            items.append(
                UpcomingMoneyItem(
                    id: "recurring.\(payment.id.uuidString).\(Self.occurrenceKey(for: date))",
                    name: payment.name,
                    amount: payment.amount,
                    date: date,
                    isIncome: payment.kind == .income
                )
            )
        }

        for account in budget.creditAccounts where account.isActive {
            guard let date = nextMonthlyDate(day: account.dueDay, startDate: today, from: today),
                  date <= endDate else {
                continue
            }

            let amount = budget.creditAccountActualBalance(account)
            guard amount > 0 else { continue }

            items.append(
                UpcomingMoneyItem(
                    id: "credit.\(account.id.uuidString).\(Self.occurrenceKey(for: date))",
                    name: account.name,
                    amount: amount,
                    date: date,
                    isIncome: false
                )
            )
        }

        if budget.recurringElectricBill.isActive,
           let date = nextMonthlyDate(day: budget.recurringElectricBill.dueDay, startDate: today, from: today),
           date <= endDate,
           budget.recurringElectricBill.expectedAmount > 0 {
            items.append(
                UpcomingMoneyItem(
                    id: "marginBill.\(Self.occurrenceKey(for: date))",
                    name: budget.recurringElectricBill.name,
                    amount: budget.recurringElectricBill.expectedAmount,
                    date: date,
                    isIncome: false
                )
            )
        }

        return items.sorted { lhs, rhs in
            if lhs.date == rhs.date {
                return lhs.name < rhs.name
            }
            return lhs.date < rhs.date
        }
    }

    private func nextMonthlyDate(day: Int, startDate: Date, from date: Date) -> Date? {
        var cursor = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
        for _ in 0..<14 {
            guard let range = calendar.range(of: .day, in: .month, for: cursor) else { return nil }
            let resolvedDay = min(max(day, 1), range.count)
            var components = calendar.dateComponents([.year, .month], from: cursor)
            components.day = resolvedDay
            guard let candidate = calendar.date(from: components) else { return nil }

            if candidate >= calendar.startOfDay(for: startDate), candidate >= calendar.startOfDay(for: date) {
                return candidate
            }
            cursor = calendar.date(byAdding: .month, value: 1, to: cursor) ?? cursor
        }
        return nil
    }

    static func recordPortfolioValueHistory(for budget: BudgetModel) {
        let gross = grossPortfolioValue(for: budget)
        let net = gross - budget.portfolioSnapshot.marginUsed
        guard gross > 0 || net != 0 else { return }

        let now = Date()
        if let last = budget.portfolioValueHistory.last, now.timeIntervalSince(last.date) < 60 {
            budget.portfolioValueHistory[budget.portfolioValueHistory.count - 1] = PortfolioValuePoint(
                id: last.id,
                date: now,
                grossValue: gross,
                netValue: net
            )
        } else {
            budget.portfolioValueHistory.append(PortfolioValuePoint(date: now, grossValue: gross, netValue: net))
            if budget.portfolioValueHistory.count > 500 {
                budget.portfolioValueHistory = Array(budget.portfolioValueHistory.suffix(500))
            }
        }
    }

    static func netWorth(for budget: BudgetModel) -> Double {
        let cash = budget.bankAccounts.reduce(0) { $0 + $1.balance }
        let savings = budget.savingsGoals.reduce(0) { $0 + $1.currentAmount }
        let liabilities = budget.creditAccounts
            .filter(\.isActive)
            .reduce(0) { $0 + max(budget.creditAccountActualBalance($1), 0) }
        return cash + savings + grossPortfolioValue(for: budget) - budget.portfolioSnapshot.marginUsed - liabilities
    }

    static func grossPortfolioValue(for budget: BudgetModel) -> Double {
        let holdingsValue = budget.holdings.reduce(0) { partial, holding in
            let price = budget.cachedQuotes[holding.ticker.uppercased()]?.price ?? holding.currentPrice
            return partial + (holding.shares * price)
        }
        return holdingsValue + budget.portfolioSnapshot.cashBalance
    }

    private static func currency(_ value: Double) -> String {
        value.formatted(.currency(code: "USD"))
    }

    private static func percent(_ value: Double) -> String {
        (value / 100).formatted(.percent.precision(.fractionLength(2)))
    }

    private static func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day())
    }

    private static func occurrenceKey(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}

private struct UpcomingMoneyItem {
    let id: String
    let name: String
    let amount: Double
    let date: Date
    let isIncome: Bool
}
