const { requireMethod, sendError } = require("../../lib/http");

module.exports = async function handler(req, res) {
  if (!requireMethod(req, res, "POST")) return;
  sendError(
    res,
    410,
    "The legacy Vercel Plaid webhook endpoint is retired. Plaid webhooks must use the verified Supabase endpoint."
  );
};
