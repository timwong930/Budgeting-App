const { plaidClient, plaidCountryCodes, requiredEnv } = require("../../lib/config");
const { handleApiError, requireAppKey, requireMethod, sendJson } = require("../../lib/http");

module.exports = async function handler(req, res) {
  if (!requireMethod(req, res, "POST") || !requireAppKey(req, res)) return;
  try {
    const client = plaidClient();
    const productScope = req.body?.productScope || "banking";
    const productConfig = linkProductConfig(productScope);
    const response = await client.linkTokenCreate({
      user: { client_user_id: "momos-money-personal-user" },
      client_name: "Momo's Money!",
      products: productConfig.products,
      required_if_supported_products: productConfig.requiredIfSupportedProducts,
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

function linkProductConfig(productScope) {
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
