const { logSync, markItemError } = require("../../lib/db");
const { handleApiError, requireMethod, sendJson } = require("../../lib/http");

module.exports = async function handler(req, res) {
  if (!requireMethod(req, res, "POST")) return;
  try {
    const itemId = req.body?.item_id || null;
    const webhookType = req.body?.webhook_type || "UNKNOWN";
    const webhookCode = req.body?.webhook_code || "UNKNOWN";
    await logSync(itemId, `webhook:${webhookType}`, webhookCode);
    if (itemId && webhookCode === "ITEM_LOGIN_REQUIRED") {
      await markItemError(itemId, "Plaid item requires account re-authentication.");
    }
    sendJson(res, 200, { ok: true });
  } catch (error) {
    handleApiError(res, error);
  }
};
