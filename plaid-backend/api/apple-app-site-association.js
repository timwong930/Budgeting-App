const { requiredEnv } = require("../lib/config");

module.exports = async function handler(req, res) {
  const teamId = requiredEnv("APPLE_TEAM_ID");
  const bundleId = process.env.APP_BUNDLE_ID || "Timothy-Wong.Budgeting-App";
  res.setHeader("Content-Type", "application/json");
  res.status(200).json({
    applinks: {
      apps: [],
      details: [
        {
          appID: `${teamId}.${bundleId}`,
          paths: ["/plaid/oauth", "/plaid/oauth/*"]
        }
      ]
    }
  });
};
