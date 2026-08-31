from pathlib import Path

path = Path("Budgeting App/ContentView.swift")
text = path.read_text()


def replace_once(old: str, new: str, label: str) -> None:
    global text
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected 1 match, found {count}")
    text = text.replace(old, new, 1)

replace_once(
'''            .onChange(of: calendarViewMode) { _, _ in\n                scheduleCalendarEventCacheRebuild()\n            }\n            .onChange(of: budget.watchlistTickers) { _, _ in\n''',
'''            .onChange(of: calendarViewMode) { _, _ in\n                scheduleCalendarEventCacheRebuild()\n            }\n            .onChange(of: calendarShowPortfolio) { _, _ in\n                scheduleCalendarEventCacheRebuild()\n            }\n            .onChange(of: budget.watchlistTickers) { _, _ in\n''',
"portfolio cache trigger",
)

replace_once(
'''    private var calendarVisibleIncome: Double {\n        let oneTimeIncome = budget.incomes\n            .filter { isInVisibleCalendarMonth($0.date) }\n            .reduce(0) { $0 + $1.amount }\n        let recurringIncome = visibleCalendarMonthDays\n            .flatMap(recurringOccurrences)\n            .filter { $0.payment.kind == .income && !isRecurringOccurrencePaid($0.payment, on: $0.date) }\n            .reduce(0) { $0 + $1.payment.amount }\n        let investmentIncome = budget.portfolioTransactions\n            .filter { isInVisibleCalendarMonth($0.date) && ($0.type == .sell || $0.type == .dividend) }\n            .reduce(0) { $0 + $1.amount }\n        return oneTimeIncome + recurringIncome + investmentIncome\n    }\n''',
'''    private var calendarVisibleIncome: Double {\n        let oneTimeIncome = calendarShowIncome\n            ? budget.incomes\n                .filter { isInVisibleCalendarMonth($0.date) }\n                .reduce(0) { $0 + $1.amount }\n            : 0\n        let recurringIncome = calendarShowIncome\n            ? visibleCalendarMonthDays\n                .flatMap(recurringOccurrences)\n                .filter { $0.payment.kind == .income && !isRecurringOccurrencePaid($0.payment, on: $0.date) }\n                .reduce(0) { $0 + $1.payment.amount }\n            : 0\n        let investmentIncome = calendarShowPortfolio\n            ? budget.portfolioTransactions\n                .filter { isInVisibleCalendarMonth($0.date) && ($0.type == .sell || $0.type == .dividend) }\n                .reduce(0) { $0 + $1.amount }\n            : 0\n        return oneTimeIncome + recurringIncome + investmentIncome\n    }\n''',
"filtered month income",
)

replace_once(
'''    private var calendarVisibleOutflow: Double {\n        let oneTimeExpenses = budget.expenses\n            .filter { isInVisibleCalendarMonth($0.date) && !budget.isCreditCardPayment($0) }\n            .reduce(0) { $0 + $1.amount }\n        let recurringExpenses = visibleCalendarMonthDays\n            .flatMap(recurringOccurrences)\n            .filter { $0.payment.kind == .expense && !isRecurringOccurrencePaid($0.payment, on: $0.date) }\n            .reduce(0) { $0 + $1.payment.amount }\n        return oneTimeExpenses + recurringExpenses\n    }\n''',
'''    private var calendarVisibleOutflow: Double {\n        guard calendarShowExpenses else { return 0 }\n        let oneTimeExpenses = budget.expenses\n            .filter { isInVisibleCalendarMonth($0.date) && !budget.isCreditCardPayment($0) }\n            .reduce(0) { $0 + $1.amount }\n        let recurringExpenses = visibleCalendarMonthDays\n            .flatMap(recurringOccurrences)\n            .filter { $0.payment.kind == .expense && !isRecurringOccurrencePaid($0.payment, on: $0.date) }\n            .reduce(0) { $0 + $1.payment.amount }\n        return oneTimeExpenses + recurringExpenses\n    }\n''',
"filtered month outflow",
)

replace_once(
'''    private var calendarVisibleCreditDue: Double {\n        budget.creditAccounts\n            .filter { account in\n''',
'''    private var calendarVisibleCreditDue: Double {\n        guard calendarShowCreditDue else { return 0 }\n        return budget.creditAccounts\n            .filter { account in\n''',
"filtered credit due",
)

old_portfolio = '''        let portfolioItems = budget.portfolioTransactions\n            .filter { calendar.isDate($0.date, inSameDayAs: date) }\n            .map { transaction in\n                CalendarEventItem(\n                    id: transaction.id,\n                    name: portfolioEventName(transaction),\n                    amount: transaction.amount,\n                    isIncome: transaction.type == .sell || transaction.type == .dividend,\n                    date: transaction.date,\n                    recurringPayment: nil,\n                    expense: nil,\n                    income: nil,\n                    cashTransfer: nil,\n                    isPaid: true,\n                    isTransfer: transaction.type == .contribution,\n                    tint: portfolioEventColor(transaction),\n                    isCreditDue: false,\n                    paymentAccount: transaction.fundingBankAccount ?? "Investment Account",\n                    iconName: portfolioEventIcon(transaction),\n                    creditAccount: nil,\n                    portfolioTransaction: transaction\n                )\n            }\n'''
new_portfolio = '''        let portfolioItems: [CalendarEventItem]\n        if calendarShowPortfolio {\n            portfolioItems = budget.portfolioTransactions\n                .filter { calendar.isDate($0.date, inSameDayAs: date) }\n                .map { transaction in\n                    CalendarEventItem(\n                        id: transaction.id,\n                        name: portfolioEventName(transaction),\n                        amount: transaction.amount,\n                        isIncome: transaction.type == .sell || transaction.type == .dividend,\n                        date: transaction.date,\n                        recurringPayment: nil,\n                        expense: nil,\n                        income: nil,\n                        cashTransfer: nil,\n                        isPaid: true,\n                        isTransfer: transaction.type == .contribution,\n                        tint: portfolioEventColor(transaction),\n                        isCreditDue: false,\n                        paymentAccount: transaction.fundingBankAccount ?? "Investment Account",\n                        iconName: portfolioEventIcon(transaction),\n                        creditAccount: nil,\n                        portfolioTransaction: transaction\n                    )\n                }\n        } else {\n            portfolioItems = []\n        }\n'''
replace_once(old_portfolio, new_portfolio, "skip hidden portfolio events")

path.write_text(text)
print("TIM-95 month filter/performance patch applied")
