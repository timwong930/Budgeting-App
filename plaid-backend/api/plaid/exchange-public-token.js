const { plaidClient } = require("../../lib/config");
const { encryptToken } = require("../../lib/crypto");
const { listItems, upsertAccounts, upsertItem } = require("../../lib/db");
const { handleApiError, requireAppKey, requireMethod, sendJson } = require("../../lib/http");
const { normalizeConnection } = require("../../lib/normalize");
const { isPlaidInstitutionId, resolveInstitutionName } = require("../../lib/institutions");

module.exports = async function handler(req, res) {
  if (!requireMethod(req, res, "POST") || !requireAppKey(req, res)) return;
  try {
    const publicToken = req.body?.publicToken;
    if (!publicToken) {
      sendJson(res, 400, { error: "Missing publicToken" });
      return;
    }

    const client = plaidClient();
    const exchange = await client.itemPublicTokenExchange({ public_token: publicToken });
    const accessToken = exchange.data.access_token;
    const itemId = exchange.data.item_id;

    const linkInstitutionName = req.body?.institutionName;
    const institutionName = linkInstitutionName && !isPlaidInstitutionId(linkInstitutionName)
      ? linkInstitutionName
      : await resolveInstitutionName(client, accessToken, linkInstitutionName || "Plaid Institution");

    await upsertItem({
      itemId,
      accessTokenCipher: encryptToken(accessToken),
      institutionName
    });

    const accounts = await client.accountsBalanceGet({ access_token: accessToken });
    await upsertAccounts(itemId, accounts.data.accounts || []);

    const items = await listItems();
    sendJson(res, 200, { connections: items.map(normalizeConnection) });
  } catch (error) {
    handleApiError(res, error);
  }
};
