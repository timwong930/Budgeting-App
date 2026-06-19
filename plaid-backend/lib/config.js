const { Configuration, PlaidApi, PlaidEnvironments } = require("@plaid/client");

function requiredEnv(name) {
  const value = process.env[name];
  if (!value || !value.trim()) {
    throw new Error(`Missing required environment variable ${name}`);
  }
  return value.trim();
}

function optionalList(name, fallback) {
  const value = process.env[name];
  return (value && value.trim() ? value : fallback)
    .split(",")
    .map((item) => item.trim())
    .filter(Boolean);
}

function plaidClient() {
  const env = process.env.PLAID_ENV || "production";
  const configuration = new Configuration({
    basePath: PlaidEnvironments[env],
    baseOptions: {
      headers: {
        "PLAID-CLIENT-ID": requiredEnv("PLAID_CLIENT_ID"),
        "PLAID-SECRET": requiredEnv("PLAID_SECRET")
      }
    }
  });
  return new PlaidApi(configuration);
}

function plaidProducts() {
  return optionalList("PLAID_PRODUCTS", "transactions,investments,liabilities");
}

function plaidCountryCodes() {
  return optionalList("PLAID_COUNTRY_CODES", "US");
}

function appSyncKey() {
  return requiredEnv("APP_SYNC_KEY");
}

function tokenEncryptionKey() {
  return requiredEnv("PLAID_TOKEN_ENCRYPTION_KEY");
}

module.exports = {
  appSyncKey,
  plaidClient,
  plaidCountryCodes,
  plaidProducts,
  requiredEnv,
  tokenEncryptionKey
};
