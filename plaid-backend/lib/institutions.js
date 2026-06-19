const { plaidCountryCodes } = require("./config");
const { decryptToken } = require("./crypto");
const { updateInstitutionName } = require("./db");

function isPlaidInstitutionId(value) {
  return /^ins_[A-Za-z0-9]+$/.test(value || "");
}

function needsInstitutionNameRefresh(value) {
  return !value || value === "Plaid Institution" || isPlaidInstitutionId(value);
}

async function resolveInstitutionName(client, accessToken, fallback = "Plaid Institution") {
  try {
    const item = await client.itemGet({ access_token: accessToken });
    const institutionId = item.data.item?.institution_id;
    if (!institutionId) return fallback;
    const response = await client.institutionsGetById({
      institution_id: institutionId,
      country_codes: plaidCountryCodes()
    });
    return response.data.institution?.name || fallback;
  } catch {
    return fallback;
  }
}

async function refreshInstitutionName(client, item, accessToken = null) {
  if (!needsInstitutionNameRefresh(item.institution_name)) return item.institution_name;
  const token = accessToken || decryptToken(item.access_token_cipher);
  const name = await resolveInstitutionName(client, token, item.institution_name);
  if (name !== item.institution_name) await updateInstitutionName(item.item_id, name);
  return name;
}

async function refreshMissingInstitutionNames(client, items) {
  return Promise.all(items.map(async (item) => {
    try {
      const institutionName = await refreshInstitutionName(client, item);
      return { ...item, institution_name: institutionName };
    } catch {
      return item;
    }
  }));
}

module.exports = {
  isPlaidInstitutionId,
  refreshInstitutionName,
  refreshMissingInstitutionNames,
  resolveInstitutionName
};
