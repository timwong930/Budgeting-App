const { plaidClient } = require("../../lib/config");
const { listItems } = require("../../lib/db");
const { refreshMissingInstitutionNames } = require("../../lib/institutions");
const { handleApiError, requireAppKey, requireMethod, sendJson } = require("../../lib/http");
const { normalizeConnection } = require("../../lib/normalize");

module.exports = async function handler(req, res) {
  if (!requireMethod(req, res, "GET") || !requireAppKey(req, res)) return;
  try {
    const items = await refreshMissingInstitutionNames(plaidClient(), await listItems());
    sendJson(res, 200, { connections: items.map(normalizeConnection) });
  } catch (error) {
    handleApiError(res, error);
  }
};
