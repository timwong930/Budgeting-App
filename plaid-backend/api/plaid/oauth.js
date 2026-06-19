module.exports = async function handler(req, res) {
  const protocol = req.headers["x-forwarded-proto"] || "https";
  const host = req.headers["x-forwarded-host"] || req.headers.host;
  const redirectURL = `${protocol}://${host}${req.url}`;
  const appReturnURL = new URL("momosmoney://plaid/oauth");
  appReturnURL.searchParams.set("redirect_uri", redirectURL);
  res.redirect(302, appReturnURL.toString());
};
