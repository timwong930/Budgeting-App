const { plaidClient } = require("../../lib/config");
const { decryptToken } = require("../../lib/crypto");
const { listItems, logSync, markItemError, updateCursor, upsertAccounts } = require("../../lib/db");
const { handleApiError, requireAppKey, requireMethod, sendJson } = require("../../lib/http");
const { refreshInstitutionName, refreshMissingInstitutionNames } = require("../../lib/institutions");
const {
  normalizeAccount,
  normalizeConnection,
  normalizeCreditLiability,
  normalizeHolding,
  normalizeInvestmentTransaction,
  normalizeRemovedTransaction,
  normalizeTransaction,
  securitiesById
} = require("../../lib/normalize");

module.exports = async function handler(req, res) {
  if (!requireMethod(req, res, "POST") || !requireAppKey(req, res)) return;
  const client = plaidClient();
  const payload = {
    accounts: [],
    transactions: [],
    creditLiabilities: [],
    holdings: [],
    investmentTransactions: [],
    connectionStatuses: []
  };

  try {
    const results = await Promise.all((await listItems()).map((item) => syncItem(client, item)));
    for (const result of results) {
      payload.accounts.push(...result.accounts);
      payload.transactions.push(...result.transactions);
      payload.creditLiabilities.push(...result.creditLiabilities);
      payload.holdings.push(...result.holdings);
      payload.investmentTransactions.push(...result.investmentTransactions);
    }
    payload.connectionStatuses = (await refreshMissingInstitutionNames(client, await listItems())).map(normalizeConnection);
    sendJson(res, 200, payload);
  } catch (error) {
    handleApiError(res, error);
  }
};

async function syncItem(client, item) {
  const empty = { accounts: [], transactions: [], creditLiabilities: [], holdings: [], investmentTransactions: [] };
  try {
    const accessToken = decryptToken(item.access_token_cipher);
    const institutionName = await refreshInstitutionName(client, item, accessToken);
    const [accounts, transactionResult, creditLiabilities, investments] = await Promise.all([
      fetchAccounts(client, item, accessToken, institutionName),
      syncTransactions(client, item, accessToken),
      fetchLiabilities(client, item, accessToken),
      fetchInvestments(client, item, accessToken)
    ]);
    await logSync(item.item_id, "sync", "Plaid sync completed");
    return {
      accounts,
      transactions: transactionResult.transactions,
      creditLiabilities,
      holdings: investments.holdings,
      investmentTransactions: investments.transactions
    };
  } catch (error) {
    await markItemError(item.item_id, error.message);
    await logSync(item.item_id, "error", error.message);
    return empty;
  }
}

async function fetchAccounts(client, item, accessToken, institutionName) {
  const response = await client.accountsBalanceGet({ access_token: accessToken });
  const accounts = response.data.accounts || [];
  await upsertAccounts(item.item_id, accounts);
  return accounts.map((account) => normalizeAccount(account, item.item_id, institutionName));
}

async function syncTransactions(client, item, accessToken) {
  try {
    let cursor = item.transaction_cursor || undefined;
    let hasMore = true;
    const transactions = [];

    while (hasMore) {
      const response = await client.transactionsSync({
        access_token: accessToken,
        cursor,
        count: 500
      });
      const data = response.data;
      transactions.push(...(data.added || []).map((tx) => normalizeTransaction(tx, item.item_id)));
      transactions.push(...(data.modified || []).map((tx) => normalizeTransaction(tx, item.item_id)));
      transactions.push(...(data.removed || []).map((tx) =>
        normalizeRemovedTransaction(tx.transaction_id, tx.account_id, item.item_id)
      ));
      cursor = data.next_cursor;
      hasMore = Boolean(data.has_more);
    }

    if (cursor) {
      await updateCursor(item.item_id, cursor);
    }
    return { transactions };
  } catch (error) {
    if (isProductUnavailable(error)) {
      await logSync(item.item_id, "transactions-unavailable", error.message);
      return { transactions: [] };
    }
    throw error;
  }
}
async function fetchLiabilities(client, item, accessToken) {
  try {
    const response = await client.liabilitiesGet({ access_token: accessToken });
    return (response.data.liabilities?.credit || []).map((credit) =>
      normalizeCreditLiability(credit.account_id, item.item_id, credit)
    );
  } catch (error) {
    if (isProductUnavailable(error)) return [];
    throw error;
  }
}

async function fetchInvestments(client, item, accessToken) {
  const [holdings, transactions] = await Promise.all([
    fetchInvestmentHoldings(client, item, accessToken),
    fetchAllInvestmentTransactions(client, item, accessToken)
  ]);
  return { holdings, transactions };
}

async function fetchInvestmentHoldings(client, item, accessToken) {
  try {
    const holdings = await client.investmentsHoldingsGet({ access_token: accessToken });
    const securities = securitiesById(holdings.data.securities);
    return (holdings.data.holdings || []).map((holding) =>
      normalizeHolding(holding, securities.get(holding.security_id), item.item_id)
    );
  } catch (error) {
    if (isProductUnavailable(error)) return [];
    throw error;
  }
}

async function fetchAllInvestmentTransactions(client, item, accessToken) {
  const transactions = [];
  try {
    const endDate = new Date();
    const startDate = new Date(endDate);
    startDate.setFullYear(endDate.getFullYear() - 2);
    const pageSize = 500;
    let offset = 0;
    let total = Infinity;
    while (offset < total) {
      const response = await client.investmentsTransactionsGet({
        access_token: accessToken,
        start_date: isoDate(startDate),
        end_date: isoDate(endDate),
        options: { count: pageSize, offset }
      });
      const page = response.data.investment_transactions || [];
      const securities = securitiesById(response.data.securities);
      transactions.push(...page.map((tx) =>
        normalizeInvestmentTransaction(tx, securities.get(tx.security_id), item.item_id)
      ));
      total = response.data.total_investment_transactions ?? page.length;
      if (page.length === 0) break;
      offset += page.length;
    }
    return transactions;
  } catch (error) {
    if (isProductUnavailable(error)) return [];
    throw error;
  }
}

function isProductUnavailable(error) {
  const code = error?.response?.data?.error_code;
  if ([
    "PRODUCT_NOT_READY",
    "PRODUCT_NOT_ENABLED",
    "PRODUCTS_NOT_SUPPORTED",
    "NO_INVESTMENT_ACCOUNTS",
    "NO_LIABILITY_ACCOUNTS",
    "ACCESS_NOT_GRANTED"
  ].includes(code)) {
    return true;
  }
  const message = String(error?.response?.data?.error_message || error?.message || "").toLowerCase();
  return message.includes("products are not supported") || message.includes("product is not supported");
}
function isoDate(date) {
  return date.toISOString().slice(0, 10);
}
