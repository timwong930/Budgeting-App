function sendJson(res, status, body) {
  res.setHeader("Content-Type", "application/json");
  res.status(status).json(body);
}

function sendError(res, status, error) {
  sendJson(res, status, { error: error instanceof Error ? error.message : String(error) });
}

function requireMethod(req, res, method) {
  if (req.method !== method) {
    res.setHeader("Allow", method);
    sendError(res, 405, "Method not allowed");
    return false;
  }
  return true;
}

function requireAppKey(_req, res) {
  sendError(
    res,
    410,
    "The legacy Vercel Plaid backend is retired. Use the authenticated Supabase Plaid backend."
  );
  return false;
}

function handleApiError(res, error) {
  const plaidError = error?.response?.data;
  if (plaidError?.error_message) {
    sendError(res, error.response.status || 500, plaidError.error_message);
    return;
  }
  sendError(res, 500, error);
}

module.exports = {
  handleApiError,
  requireAppKey,
  requireMethod,
  sendError,
  sendJson
};
