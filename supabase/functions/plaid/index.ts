import { createClient } from "npm:@supabase/supabase-js@2";

type JsonRecord = Record<string, unknown>;

type PlaidItem = {
  item_id: string;
  access_token_cipher: string;
  institution_name: string;
  transaction_cursor: string | null;
  health: string;
  error_message: string | null;
  updated_at: string | null;
};

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-app-sync-key",
  "Access-Control-Allow-Methods": "GET, POST, DELETE, OPTIONS"
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
  }

  try {
    const path = routePath(req.url);
    if (path === "/plaid/oauth" && req.method === "GET") return oauthPage(req.url);
    if (path === "/.well-known/apple-app-site-association" && req.method === "GET") {
      return jsonResponse(appleAppSiteAssociation());
    }
    if (path === "/api/plaid/link-token" && req.method === "POST") {
      requireAppSyncKey(req);
      return await createLinkToken(await requestJson(req));
    }
    if (path === "/api/plaid/exchange-public-token" && req.method === "POST") {
      requireAppSyncKey(req);
      return await exchangePublicToken(await requestJson(req));
    }
    if (path === "/api/plaid/connections" && req.method === "GET") {
      requireAppSyncKey(req);
      return await connections();
    }
    if (path === "/api/plaid/sync" && req.method === "POST") {
      requireAppSyncKey(req);
      return await sync();
    }
    if (path.startsWith("/api/plaid/items/") && req.method === "DELETE") {
      requireAppSyncKey(req);
      return await deleteItem(decodeURIComponent(path.slice("/api/plaid/items/".length)));
    }
    if (path === "/api/plaid/webhook" && req.method === "POST") {
      return await webhook(await requestJson(req));
    }
    return jsonResponse({ error: "Not found" }, 404);
  } catch (error) {
    const status = error instanceof HttpError ? error.status : 500;
    const message = error instanceof Error ? error.message : "Unknown Plaid backend error";
    return jsonResponse({ error: message }, status);
  }
});

function routePath(url: string): string {
  const pathname = new URL(url).pathname;
  const functionMarker = "/plaid/";
  const markerIndex = pathname.indexOf(functionMarker);
  if (markerIndex >= 0) return pathname.slice(markerIndex + "/plaid".length);
  if (pathname.endsWith("/plaid")) return "/";
  return pathname;
}

async function createLinkToken(requestBody: JsonRecord): Promise<Response> {
  const productScope = stringValue(requestBody.productScope) || "banking";
  const productConfig = linkProductConfig(productScope);
  const response = await plaidFetch("/link/token/create", {
    user: { client_user_id: "momos-money-personal-user" },
    client_name: "Momo's Money!",
    products: productConfig.products,
    required_if_supported_products: productConfig.requiredIfSupportedProducts,
    country_codes: envList("PLAID_COUNTRY_CODES", "US"),
    language: "en",
    redirect_uri: requiredEnv("PLAID_REDIRECT_URI"),
    webhook: Deno.env.get("PLAID_WEBHOOK_URL") || undefined,
    transactions: { days_requested: 730 }
  });

  return jsonResponse({
    linkToken: response.link_token,
    expiration: response.expiration
  });
}

function linkProductConfig(productScope: string): {
  products: string[];
  requiredIfSupportedProducts: string[];
} {
  if (productScope === "investments") {
    return {
      products: ["investments"],
      requiredIfSupportedProducts: ["transactions"]
    };
  }

  return {
    products: ["transactions"],
    requiredIfSupportedProducts: ["liabilities"]
  };
}

async function exchangePublicToken(body: JsonRecord): Promise<Response> {
  const publicToken = stringValue(body.publicToken);
  if (!publicToken) throw new HttpError(400, "Missing publicToken");

  const exchange = await plaidFetch("/item/public_token/exchange", {
    public_token: publicToken
  });

  const accessToken = stringValue(exchange.access_token);
  const itemId = stringValue(exchange.item_id);
  if (!accessToken || !itemId) throw new HttpError(502, "Plaid did not return an access token.");

  const linkInstitutionName = stringValue(body.institutionName);
  const institutionName = linkInstitutionName && !isPlaidInstitutionId(linkInstitutionName)
    ? linkInstitutionName
    : await resolveInstitutionName(accessToken, linkInstitutionName || "Plaid Institution");

  await upsertItem(itemId, await encryptToken(accessToken), institutionName);
  const accounts = await plaidFetch("/accounts/balance/get", { access_token: accessToken });
  await upsertAccounts(itemId, arrayValue(accounts.accounts));

  return connections();
}

async function connections(): Promise<Response> {
  const items = await refreshMissingInstitutionNames(await listItems());
  return jsonResponse({ connections: items.map(normalizeConnection) });
}

async function deleteItem(itemId: string): Promise<Response> {
  const item = await getItem(itemId);
  if (item) {
    try {
      await plaidFetch("/item/remove", { access_token: await decryptToken(item.access_token_cipher) });
    } catch {
      // If Plaid has already removed the Item, local cleanup should still finish.
    }
    await supabase().from("plaid_items").delete().eq("item_id", itemId);
  }
  return connections();
}

async function sync(): Promise<Response> {
  const payload = {
    accounts: [] as JsonRecord[],
    transactions: [] as JsonRecord[],
    creditLiabilities: [] as JsonRecord[],
    holdings: [] as JsonRecord[],
    investmentTransactions: [] as JsonRecord[],
    connectionStatuses: [] as JsonRecord[]
  };

  const itemResults = await Promise.all((await listItems()).map(syncItem));
  for (const result of itemResults) {
    payload.accounts.push(...result.accounts);
    payload.transactions.push(...result.transactions);
    payload.creditLiabilities.push(...result.creditLiabilities);
    payload.holdings.push(...result.holdings);
    payload.investmentTransactions.push(...result.investmentTransactions);
  }

  payload.connectionStatuses = (await refreshMissingInstitutionNames(await listItems())).map(normalizeConnection);
  return jsonResponse(payload);
}

async function syncItem(item: PlaidItem): Promise<{
  accounts: JsonRecord[];
  transactions: JsonRecord[];
  creditLiabilities: JsonRecord[];
  holdings: JsonRecord[];
  investmentTransactions: JsonRecord[];
}> {
  const empty = { accounts: [], transactions: [], creditLiabilities: [], holdings: [], investmentTransactions: [] };
  try {
    const accessToken = await decryptToken(item.access_token_cipher);
    const institutionName = await refreshInstitutionName(item, accessToken);
    const [accounts, transactions, creditLiabilities, investments] = await Promise.all([
      fetchAccounts(item, accessToken, institutionName),
      syncTransactions(item, accessToken),
      fetchLiabilities(item, accessToken),
      fetchInvestments(item, accessToken)
    ]);
    await logSync(item.item_id, "sync", "Plaid sync completed");
    return {
      accounts,
      transactions,
      creditLiabilities,
      holdings: investments.holdings,
      investmentTransactions: investments.transactions
    };
  } catch (error) {
    const message = error instanceof Error ? error.message : "Plaid sync failed";
    await markItemError(item.item_id, message);
    await logSync(item.item_id, "error", message);
    return empty;
  }
}

async function fetchAccounts(item: PlaidItem, accessToken: string, institutionName: string): Promise<JsonRecord[]> {
  const data = await plaidFetch("/accounts/balance/get", { access_token: accessToken });
  const accounts = arrayValue(data.accounts);
  await upsertAccounts(item.item_id, accounts);
  return accounts.map((account) => normalizeAccount(account, item.item_id, institutionName));
}

async function syncTransactions(item: PlaidItem, accessToken: string): Promise<JsonRecord[]> {
  let cursor = item.transaction_cursor || undefined;
  let hasMore = true;
  const transactions: JsonRecord[] = [];

  while (hasMore) {
    const data = await plaidFetch("/transactions/sync", {
      access_token: accessToken,
      cursor,
      count: 500
    });

    transactions.push(...arrayValue(data.added).map((tx) => normalizeTransaction(tx, item.item_id)));
    transactions.push(...arrayValue(data.modified).map((tx) => normalizeTransaction(tx, item.item_id)));
    transactions.push(...arrayValue(data.removed).map((tx) => normalizeRemovedTransaction(tx, item.item_id)));
    cursor = stringValue(data.next_cursor) || undefined;
    hasMore = Boolean(data.has_more);
  }

  if (cursor) await updateCursor(item.item_id, cursor);
  return transactions;
}

async function fetchLiabilities(item: PlaidItem, accessToken: string): Promise<JsonRecord[]> {
  try {
    const data = await plaidFetch("/liabilities/get", { access_token: accessToken });
    const liabilities = data.liabilities as JsonRecord | undefined;
    return arrayValue(liabilities?.credit).map((credit) => normalizeCreditLiability(credit, item.item_id));
  } catch (error) {
    if (isProductUnavailable(error, "PRODUCT_LIABILITIES")) return [];
    throw error;
  }
}

async function fetchInvestments(item: PlaidItem, accessToken: string): Promise<{
  holdings: JsonRecord[];
  transactions: JsonRecord[];
}> {
  const result = { holdings: [] as JsonRecord[], transactions: [] as JsonRecord[] };

  const [holdings, transactions] = await Promise.all([
    fetchInvestmentHoldings(item, accessToken),
    fetchAllInvestmentTransactions(item, accessToken)
  ]);
  result.holdings = holdings;
  result.transactions = transactions;

  return result;
}

async function fetchInvestmentHoldings(item: PlaidItem, accessToken: string): Promise<JsonRecord[]> {
  try {
    const data = await plaidFetch("/investments/holdings/get", { access_token: accessToken });
    const securities = securitiesById(arrayValue(data.securities));
    return arrayValue(data.holdings).map((holding) =>
      normalizeHolding(holding, securities.get(stringValue(holding.security_id) || ""), item.item_id)
    );
  } catch (error) {
    if (isProductUnavailable(error, "PRODUCT_INVESTMENTS")) return [];
    throw error;
  }
}

async function fetchAllInvestmentTransactions(item: PlaidItem, accessToken: string): Promise<JsonRecord[]> {
  const endDate = new Date();
  const startDate = new Date(endDate);
  startDate.setFullYear(endDate.getFullYear() - 2);
  const pageSize = 500;
  let offset = 0;
  let total = Number.POSITIVE_INFINITY;
  const transactions: JsonRecord[] = [];
  try {
    while (offset < total) {
      const data = await plaidFetch("/investments/transactions/get", {
        access_token: accessToken,
        start_date: isoDate(startDate),
        end_date: isoDate(endDate),
        options: { count: pageSize, offset }
      });
      const page = arrayValue(data.investment_transactions);
      const securities = securitiesById(arrayValue(data.securities));
      transactions.push(...page.map((tx) =>
        normalizeInvestmentTransaction(tx, securities.get(stringValue(tx.security_id) || ""), item.item_id)
      ));
      total = numberOrNull(data.total_investment_transactions) ?? page.length;
      if (page.length === 0) break;
      offset += page.length;
    }
    return transactions;
  } catch (error) {
    if (isProductUnavailable(error, "PRODUCT_INVESTMENTS")) return [];
    throw error;
  }
}

async function webhook(body: JsonRecord): Promise<Response> {
  const itemId = stringValue(body.item_id);
  const webhookType = stringValue(body.webhook_type) || "UNKNOWN";
  const webhookCode = stringValue(body.webhook_code) || "UNKNOWN";

  await logSync(itemId, `webhook:${webhookType}`, webhookCode);
  if (itemId && webhookCode === "ITEM_LOGIN_REQUIRED") {
    await markItemError(itemId, "Plaid item requires account re-authentication.");
  }

  return jsonResponse({ ok: true });
}

async function plaidFetch(path: string, body: JsonRecord): Promise<JsonRecord> {
  const response = await fetch(`${plaidBaseURL()}${path}`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "PLAID-CLIENT-ID": requiredEnv("PLAID_CLIENT_ID"),
      "PLAID-SECRET": requiredEnv("PLAID_SECRET")
    },
    body: JSON.stringify(body)
  });
  const data = await response.json().catch(() => ({}));
  if (!response.ok) {
    const message = stringValue(data.error_message) || stringValue(data.error_code) || `Plaid request failed: ${path}`;
    throw new PlaidApiError(response.status, message, stringValue(data.error_code));
  }
  return data as JsonRecord;
}

function plaidBaseURL(): string {
  const env = Deno.env.get("PLAID_ENV") || "production";
  switch (env) {
    case "sandbox": return "https://sandbox.plaid.com";
    case "development": return "https://development.plaid.com";
    case "production": return "https://production.plaid.com";
    default: throw new Error(`Unsupported PLAID_ENV: ${env}`);
  }
}

function supabase() {
  const url = requiredEnv("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || requiredEnv("SUPABASE_SECRET_KEY");
  return createClient(url, key, { auth: { persistSession: false } });
}

async function upsertItem(itemId: string, accessTokenCipher: string, institutionName: string): Promise<void> {
  const { error } = await supabase()
    .from("plaid_items")
    .upsert({
      item_id: itemId,
      access_token_cipher: accessTokenCipher,
      institution_name: institutionName || "Plaid Institution",
      health: "connected",
      error_message: null,
      updated_at: new Date().toISOString()
    }, { onConflict: "item_id" });
  if (error) throw error;
}

async function listItems(): Promise<PlaidItem[]> {
  const { data, error } = await supabase()
    .from("plaid_items")
    .select("*")
    .order("institution_name");
  if (error) throw error;
  return (data || []) as PlaidItem[];
}

async function getItem(itemId: string): Promise<PlaidItem | null> {
  const { data, error } = await supabase()
    .from("plaid_items")
    .select("*")
    .eq("item_id", itemId)
    .maybeSingle();
  if (error) throw error;
  return data as PlaidItem | null;
}

async function refreshMissingInstitutionNames(items: PlaidItem[]): Promise<PlaidItem[]> {
  return await Promise.all(items.map(async (item) => {
    if (!needsInstitutionNameRefresh(item.institution_name)) return item;
    try {
      const accessToken = await decryptToken(item.access_token_cipher);
      const institutionName = await refreshInstitutionName(item, accessToken);
      return { ...item, institution_name: institutionName };
    } catch {
      return item;
    }
  }));
}

async function refreshInstitutionName(item: PlaidItem, accessToken: string): Promise<string> {
  if (!needsInstitutionNameRefresh(item.institution_name)) return item.institution_name;
  const institutionName = await resolveInstitutionName(accessToken, item.institution_name);
  if (institutionName !== item.institution_name) {
    const { error } = await supabase()
      .from("plaid_items")
      .update({ institution_name: institutionName, updated_at: new Date().toISOString() })
      .eq("item_id", item.item_id);
    if (error) throw error;
  }
  return institutionName;
}

async function resolveInstitutionName(accessToken: string, fallback: string): Promise<string> {
  try {
    const itemData = await plaidFetch("/item/get", { access_token: accessToken });
    const institutionId = stringValue((itemData.item as JsonRecord | undefined)?.institution_id);
    if (!institutionId) return fallback;
    const institutionData = await plaidFetch("/institutions/get_by_id", {
      institution_id: institutionId,
      country_codes: envList("PLAID_COUNTRY_CODES", "US")
    });
    return stringValue((institutionData.institution as JsonRecord | undefined)?.name) || fallback;
  } catch {
    return fallback;
  }
}

function needsInstitutionNameRefresh(value: string): boolean {
  return !value || value === "Plaid Institution" || isPlaidInstitutionId(value);
}

function isPlaidInstitutionId(value: string): boolean {
  return /^ins_[A-Za-z0-9]+$/.test(value);
}

async function updateCursor(itemId: string, cursor: string): Promise<void> {
  const { error } = await supabase()
    .from("plaid_items")
    .update({
      transaction_cursor: cursor,
      health: "connected",
      error_message: null,
      updated_at: new Date().toISOString()
    })
    .eq("item_id", itemId);
  if (error) throw error;
}

async function markItemError(itemId: string, message: string): Promise<void> {
  const { error } = await supabase()
    .from("plaid_items")
    .update({ health: "error", error_message: message, updated_at: new Date().toISOString() })
    .eq("item_id", itemId);
  if (error) throw error;
}

async function upsertAccounts(itemId: string, accounts: JsonRecord[]): Promise<void> {
  if (accounts.length === 0) return;
  const rows = accounts.map((account) => {
    const balances = (account.balances as JsonRecord | undefined) || {};
    return {
      account_id: stringValue(account.account_id),
      item_id: itemId,
      name: stringValue(account.name) || stringValue(account.official_name) || "Plaid Account",
      type: stringValue(account.type),
      subtype: stringValue(account.subtype),
      current_balance: numberOrNull(balances.current),
      available_balance: numberOrNull(balances.available),
      credit_limit: numberOrNull(balances.limit),
      updated_at: new Date().toISOString()
    };
  }).filter((row) => row.account_id);

  const { error } = await supabase().from("plaid_accounts").upsert(rows, { onConflict: "account_id" });
  if (error) throw error;
}

async function logSync(itemId: string | null | undefined, eventType: string, message: string): Promise<void> {
  const { error } = await supabase().from("plaid_sync_logs").insert({
    item_id: itemId || null,
    event_type: eventType,
    message
  });
  if (error) throw error;
}

async function encryptToken(value: string): Promise<string> {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const key = await encryptionKey();
  const encrypted = new Uint8Array(
    await crypto.subtle.encrypt({ name: "AES-GCM", iv: iv as BufferSource }, key, encode(value) as BufferSource)
  );
  return `${base64Encode(iv)}.${base64Encode(encrypted)}`;
}

async function decryptToken(value: string): Promise<string> {
  const [ivRaw, encryptedRaw] = value.split(".");
  if (!ivRaw || !encryptedRaw) throw new Error("Encrypted Plaid token is malformed");
  const key = await encryptionKey();
  const decrypted = await crypto.subtle.decrypt(
    { name: "AES-GCM", iv: base64Decode(ivRaw) as BufferSource },
    key,
    base64Decode(encryptedRaw) as BufferSource
  );
  return new TextDecoder().decode(decrypted);
}

async function encryptionKey(): Promise<CryptoKey> {
  const hash = await crypto.subtle.digest(
    "SHA-256",
    encode(requiredEnv("PLAID_TOKEN_ENCRYPTION_KEY")) as BufferSource
  );
  return crypto.subtle.importKey("raw", hash, "AES-GCM", false, ["encrypt", "decrypt"]);
}

function normalizeAccount(account: JsonRecord, itemId: string, institutionName: string): JsonRecord {
  const balances = (account.balances as JsonRecord | undefined) || {};
  return {
    id: stringValue(account.account_id),
    itemId,
    name: stringValue(account.name) || stringValue(account.official_name) || "Plaid Account",
    type: stringValue(account.type) || "other",
    subtype: stringValue(account.subtype),
    currentBalance: numberOrNull(balances.current),
    availableBalance: numberOrNull(balances.available),
    creditLimit: numberOrNull(balances.limit),
    institutionName
  };
}

function normalizeTransaction(transaction: JsonRecord, itemId: string): JsonRecord {
  const pfc = transaction.personal_finance_category as JsonRecord | undefined;
  const category = arrayValue(transaction.category)[0];
  return {
    id: stringValue(transaction.transaction_id),
    accountId: stringValue(transaction.account_id),
    itemId,
    name: stringValue(transaction.name) || "Plaid Transaction",
    merchantName: stringValue(transaction.merchant_name),
    amount: numberOrZero(transaction.amount),
    date: stringValue(transaction.date),
    pending: Boolean(transaction.pending),
    category: stringValue(pfc?.primary) || stringValue(category),
    removed: false
  };
}

function normalizeRemovedTransaction(transaction: JsonRecord, itemId: string): JsonRecord {
  return {
    id: stringValue(transaction.transaction_id),
    accountId: stringValue(transaction.account_id),
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

function normalizeCreditLiability(credit: JsonRecord, itemId: string): JsonRecord {
  const aprs = arrayValue(credit.aprs);
  return {
    accountId: stringValue(credit.account_id),
    itemId,
    minimumPaymentAmount: numberOrNull(credit.minimum_payment_amount),
    nextPaymentDueDate: stringValue(credit.next_payment_due_date),
    lastStatementBalance: numberOrNull(credit.last_statement_balance),
    lastStatementIssueDate: stringValue(credit.last_statement_issue_date),
    aprPercentage: numberOrNull(aprs[0]?.apr_percentage)
  };
}

function normalizeHolding(holding: JsonRecord, security: JsonRecord | undefined, itemId: string): JsonRecord {
  return {
    accountId: stringValue(holding.account_id),
    itemId,
    securityId: stringValue(holding.security_id),
    ticker: stringValue(security?.ticker_symbol),
    name: stringValue(security?.name),
    quantity: numberOrZero(holding.quantity),
    costBasis: numberOrNull(holding.cost_basis),
    institutionPrice: numberOrNull(holding.institution_price),
    institutionValue: numberOrNull(holding.institution_value),
    priceAsOf: stringValue(holding.institution_price_as_of),
    securityType: stringValue(security?.type)
  };
}

function normalizeInvestmentTransaction(tx: JsonRecord, security: JsonRecord | undefined, itemId: string): JsonRecord {
  return {
    id: stringValue(tx.investment_transaction_id),
    accountId: stringValue(tx.account_id),
    itemId,
    securityId: stringValue(tx.security_id),
    ticker: stringValue(security?.ticker_symbol),
    name: stringValue(tx.name) || "Investment Transaction",
    type: stringValue(tx.type) || "",
    subtype: stringValue(tx.subtype),
    amount: numberOrZero(tx.amount),
    quantity: numberOrNull(tx.quantity),
    price: numberOrNull(tx.price),
    date: stringValue(tx.date)
  };
}

function normalizeConnection(item: PlaidItem): JsonRecord {
  return {
    itemId: item.item_id,
    institutionName: item.institution_name,
    health: item.health || "connected",
    lastSyncedAt: item.updated_at ? new Date(item.updated_at).toISOString() : null,
    errorMessage: item.error_message
  };
}

function securitiesById(securities: JsonRecord[]): Map<string, JsonRecord> {
  return new Map(securities.map((security) => [stringValue(security.security_id) || "", security]));
}

function appleAppSiteAssociation(): JsonRecord {
  const teamId = requiredEnv("APPLE_TEAM_ID");
  const bundleId = Deno.env.get("APP_BUNDLE_ID") || "Timothy-Wong.Budgeting-App";
  return {
    applinks: {
      apps: [],
      details: [
        {
          appID: `${teamId}.${bundleId}`,
          paths: ["/plaid/oauth", "/plaid/oauth/*", "/functions/v1/plaid/plaid/oauth", "/functions/v1/plaid/plaid/oauth/*"]
        }
      ]
    }
  };
}

function oauthPage(requestURL: string): Response {
  const configuredRedirectURL = new URL(requiredEnv("PLAID_REDIRECT_URI"));
  configuredRedirectURL.search = new URL(requestURL).search;
  const appReturnURL = new URL("momosmoney://plaid/oauth");
  appReturnURL.searchParams.set("redirect_uri", configuredRedirectURL.toString());
  return new Response(null, {
    status: 302,
    headers: { ...corsHeaders, Location: appReturnURL.toString() }
  });
}

async function requestJson(req: Request): Promise<JsonRecord> {
  if (!req.body) return {};
  return await req.json().catch(() => ({}));
}

function requireAppSyncKey(req: Request): void {
  const expected = requiredEnv("APP_SYNC_KEY");
  const actual = req.headers.get("X-App-Sync-Key") || "";
  if (actual !== expected) throw new HttpError(401, "Unauthorized");
}

function requiredEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value || !value.trim()) throw new Error(`Missing required environment variable ${name}`);
  return value.trim();
}

function envList(name: string, fallback: string): string[] {
  return (Deno.env.get(name) || fallback).split(",").map((item) => item.trim()).filter(Boolean);
}

function jsonResponse(body: JsonRecord, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" }
  });
}

function stringValue(value: unknown): string | null {
  return typeof value === "string" && value.length > 0 ? value : null;
}

function numberOrNull(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function numberOrZero(value: unknown): number {
  return numberOrNull(value) ?? 0;
}

function arrayValue(value: unknown): JsonRecord[] {
  return Array.isArray(value) ? value.filter((item): item is JsonRecord => Boolean(item) && typeof item === "object") : [];
}

function isoDate(date: Date): string {
  return date.toISOString().slice(0, 10);
}

function isProductUnavailable(error: unknown, productName: string): boolean {
  if (!(error instanceof PlaidApiError)) return false;
  if ([
    "PRODUCT_NOT_READY",
    "PRODUCT_NOT_ENABLED",
    "NO_INVESTMENT_ACCOUNTS",
    "NO_LIABILITY_ACCOUNTS",
    "ACCESS_NOT_GRANTED",
    "ITEM_LOGIN_REQUIRED"
  ].includes(error.errorCode || "")) {
    return true;
  }
  const message = error.message.toLowerCase();
  return message.includes("does not have user consent") && message.includes(productName.toLowerCase());
}

function encode(value: string): Uint8Array {
  return new TextEncoder().encode(value);
}

function base64Encode(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary);
}

function base64Decode(value: string): Uint8Array {
  const binary = atob(value);
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index += 1) bytes[index] = binary.charCodeAt(index);
  return bytes;
}

class HttpError extends Error {
  constructor(public status: number, message: string) {
    super(message);
  }
}

class PlaidApiError extends Error {
  constructor(public status: number, message: string, public errorCode: string | null) {
    super(message);
  }
}
