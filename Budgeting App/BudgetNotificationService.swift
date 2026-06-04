import BackgroundTasks
import Foundation
import UIKit
import UserNotifications

final class BudgetAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        BudgetBackgroundRefreshCoordinator.shared.register()
        return true
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        BudgetBackgroundRefreshCoordinator.shared.scheduleAppRefresh()
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
        guard abs(difference) >= 10 else { return }

        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

        let direction = difference >= 0 ? "up" : "down"
        let content = UNMutableNotificationContent()
        content.title = "Portfolio update"
        content.body = "Net worth is \(direction) \(Self.currency(abs(difference))) today. Total net worth: \(Self.currency(updatedNetWorth))."
        content.sound = .default

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

        let symbols = budget.watchlistTickers
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
            .filter { !$0.isEmpty }
        guard !symbols.isEmpty else { return }

        for symbol in symbols {
            guard let quote = try? await marketDataService.fetchQuoteSnapshot(
                ticker: symbol,
                settings: budget.marketDataSettings
            ) else { continue }
            let alertSettings = budget.watchlistAlertSettings(for: symbol)
            guard alertSettings.isEnabled else { continue }

            let cachedPrice = budget.cachedQuotes[symbol]?.price
            budget.cachedQuotes[symbol] = CachedQuote(ticker: symbol, price: quote.price, updatedAt: Date())

            let intradayMove = quote.percentChange
            let cachedMove: Double
            if let cachedPrice, cachedPrice > 0 {
                cachedMove = ((quote.price - cachedPrice) / cachedPrice) * 100
            } else {
                cachedMove = 0
            }

            let alertMove = abs(intradayMove) >= abs(cachedMove) ? intradayMove : cachedMove
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
            content.body = watchlistAlertBody(symbol: symbol, quote: quote, move: alertMove)
            content.sound = .default

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
        let upcoming = upcomingItems(for: budget, withinDays: 14)
        let totalUpcoming = upcoming.reduce(0) { $0 + $1.amount }
        let itemSummary = upcoming.first.map { "\($0.name) on \(Self.shortDate($0.date))" } ?? "no payments due soon"

        let content = UNMutableNotificationContent()
        content.title = label == "morning" ? "Money snapshot" : "Evening budget check"
        content.body = "Net worth: \(Self.currency(Self.netWorth(for: budget))). Upcoming: \(itemSummary). Total due soon: \(Self.currency(totalUpcoming))."
        content.sound = .default

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
        upcomingItems(for: budget, withinDays: 30).prefix(24).compactMap { item in
            guard let triggerDate = reminderDate(for: item.date) else { return nil }

            let content = UNMutableNotificationContent()
            content.title = item.isIncome ? "Incoming payment soon" : "Payment coming up"
            content.body = "\(item.name) is \(Self.currency(item.amount)) on \(Self.shortDate(item.date)). Net worth: \(Self.currency(Self.netWorth(for: budget)))."
            content.sound = .default

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
            content.body = "Net worth: \(Self.currency(Self.netWorth(for: budget))). Portfolio: \(Self.currency(Self.grossPortfolioValue(for: budget)))."
            content.sound = .default

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

    private func watchlistAlertBody(symbol: String, quote: MarketQuoteSnapshot, move: Double) -> String {
        let direction = move >= 0 ? "gained" : "fell"
        let price = Self.currency(quote.price)
        let dayChange = Self.currency(abs(quote.change))
        let range: String
        if let low = quote.low, let high = quote.high {
            range = " Range: \(Self.currency(low))-\(Self.currency(high))."
        } else {
            range = ""
        }
        return "\(symbol) \(direction) \(Self.percent(abs(move))) and is trading at \(price). Day change: \(dayChange).\(range)"
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
        let net = netWorth(for: budget)
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
