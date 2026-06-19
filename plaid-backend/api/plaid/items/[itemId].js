const { plaidClient } = require("../../../lib/config");
const { decryptToken } = require("../../../lib/crypto");
const { deleteItem, getItem, listItems } = require("../../../lib/db");
const { handleApiError, requireAppKey, requireMethod, sendJson } = require("../../../lib/http");
const { normalizeConnection } = require("../../../lib/normalize");

module.exports = async function handler(req, res) {
  if (!requireMethod(req, res, "DELETE") || !requireAppKey(req, res)) return;
  try {
    const itemId = req.query.itemId;
    const item = await getItem(itemId);
    if (item) {
      const client = plaidClient();
      try {
        await client.itemRemove({ access_token: decryptToken(item.access_token_cipher) });
      } catch {
        // If Plaid already removed the Item, still remove local state.
      }
      await deleteItem(itemId);
    }
    const items = await listItems();
    sendJson(res, 200, { connections: items.map(normalizeConnection) });
  } catch (error) {
    handleApiError(res, error);
  }
};
