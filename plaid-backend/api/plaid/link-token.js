const { plaidClient, plaidCountryCodes, plaidProducts, requiredEnv } = require("../../lib/config");
const { handleApiError, requireAppKey, requireMethod, sendJson } = require("../../lib/http");

module.exports = async function handler(req, res) {
  if (!requireMethod(req, res, "POST") || !requireAppKey(req, res)) return;
  try {
    const client = plaidClient();
    const response = await client.linkTokenCreate({
      user: { client_user_id: "momos-money-personal-user" },
      client_name: "Momo's Money!",
      products: plaidProducts(),
      country_codes: plaidCountryCodes(),
      language: "en",
      redirect_uri: requiredEnv("PLAID_REDIRECT_URI"),
      webhook: process.env.PLAID_WEBHOOK_URL || undefined,
      transactions: {
        days_requested: 730
      }
    });
    sendJson(res, 200, {
      linkToken: response.data.link_token,
      expiration: response.data.expiration
    });
  } catch (error) {
    handleApiError(res, error);
  }
};
