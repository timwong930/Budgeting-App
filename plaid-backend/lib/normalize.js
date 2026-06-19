function normalizeAccount(account, itemId, institutionName) {
  return {
    id: account.account_id,
    itemId,
    name: account.name || account.official_name || "Plaid Account",
    type: account.type || "other",
    subtype: account.subtype || null,
    currentBalance: numberOrNull(account.balances?.current),
    availableBalance: numberOrNull(account.balances?.available),
    creditLimit: numberOrNull(account.balances?.limit),
    institutionName
  };
}

function normalizeTransaction(transaction, itemId, removed = false) {
  return {
    id: transaction.transaction_id,
    accountId: transaction.account_id,
    itemId,
    name: transaction.name || "Plaid Transaction",
    merchantName: transaction.merchant_name || null,
    amount: numberOrZero(transaction.amount),
    date: transaction.date,
    pending: Boolean(transaction.pending),
    category: transaction.personal_finance_category?.primary || transaction.category?.[0] || null,
    removed
  };
}

function normalizeRemovedTransaction(transactionId, accountId, itemId) {
  return {
    id: transactionId,
    accountId,
    itemId,
    name: "Removed Plaid Transaction",
    merchantName: null,
    amount: 0,
    date: new Date().toISOString(),
    pending: false,
    category: null,
    removed: true
  };
}

function normalizeCreditLiability(accountId, itemId, credit) {
  return {
    accountId,
    itemId,
    minimumPaymentAmount: numberOrNull(credit.minimum_payment_amount),
    nextPaymentDueDate: credit.next_payment_due_date || null,
    lastStatementBalance: numberOrNull(credit.last_statement_balance),
    lastStatementIssueDate: credit.last_statement_issue_date || null,
    aprPercentage: numberOrNull(credit.aprs?.[0]?.apr_percentage)
  };
}

function normalizeHolding(holding, security, itemId) {
  return {
    accountId: holding.account_id,
    itemId,
    securityId: holding.security_id,
    ticker: security?.ticker_symbol || security?.proxy_security_id || null,
    name: security?.name || null,
    quantity: numberOrZero(holding.quantity),
    costBasis: numberOrNull(holding.cost_basis),
    institutionPrice: numberOrNull(holding.institution_price),
    institutionValue: numberOrNull(holding.institution_value),
    priceAsOf: holding.institution_price_as_of || null
  };
}

function normalizeInvestmentTransaction(transaction, security, itemId) {
  return {
    id: transaction.investment_transaction_id,
    accountId: transaction.account_id,
    itemId,
    securityId: transaction.security_id || null,
    ticker: security?.ticker_symbol || null,
    name: transaction.name || "Investment Transaction",
    type: transaction.type || "",
    subtype: transaction.subtype || null,
    amount: numberOrZero(transaction.amount),
    quantity: numberOrNull(transaction.quantity),
    price: numberOrNull(transaction.price),
    date: transaction.date
  };
}

function normalizeConnection(item) {
  return {
    itemId: item.item_id,
    institutionName: item.institution_name,
    health: item.health || "connected",
    lastSyncedAt: item.updated_at ? new Date(item.updated_at).toISOString() : null,
    errorMessage: item.error_message || null
  };
}

function securitiesById(securities) {
  return new Map((securities || []).map((security) => [security.security_id, security]));
}

function numberOrNull(value) {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function numberOrZero(value) {
  return numberOrNull(value) ?? 0;
}

module.exports = {
  normalizeAccount,
  normalizeConnection,
  normalizeCreditLiability,
  normalizeHolding,
  normalizeInvestmentTransaction,
  normalizeRemovedTransaction,
  normalizeTransaction,
  securitiesById
};
