const { sql } = require("@vercel/postgres");

let initialized = false;

async function ensureSchema() {
  if (initialized) return;
  await sql`
    CREATE TABLE IF NOT EXISTS plaid_items (
      item_id TEXT PRIMARY KEY,
      access_token_cipher TEXT NOT NULL,
      institution_name TEXT NOT NULL,
      transaction_cursor TEXT,
      health TEXT NOT NULL DEFAULT 'connected',
      error_message TEXT,
      created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
    )
  `;
  await sql`
    CREATE TABLE IF NOT EXISTS plaid_accounts (
      account_id TEXT PRIMARY KEY,
      item_id TEXT NOT NULL REFERENCES plaid_items(item_id) ON DELETE CASCADE,
      name TEXT NOT NULL,
      type TEXT,
      subtype TEXT,
      current_balance DOUBLE PRECISION,
      available_balance DOUBLE PRECISION,
      credit_limit DOUBLE PRECISION,
      updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
    )
  `;
  await sql`
    CREATE TABLE IF NOT EXISTS plaid_sync_logs (
      id BIGSERIAL PRIMARY KEY,
      item_id TEXT,
      event_type TEXT NOT NULL,
      message TEXT,
      created_at TIMESTAMPTZ NOT NULL DEFAULT now()
    )
  `;
  initialized = true;
}

async function upsertItem({ itemId, accessTokenCipher, institutionName }) {
  await ensureSchema();
  await sql`
    INSERT INTO plaid_items (item_id, access_token_cipher, institution_name, health, updated_at)
    VALUES (${itemId}, ${accessTokenCipher}, ${institutionName || "Plaid Institution"}, 'connected', now())
    ON CONFLICT (item_id)
    DO UPDATE SET
      access_token_cipher = excluded.access_token_cipher,
      institution_name = excluded.institution_name,
      health = 'connected',
      error_message = NULL,
      updated_at = now()
  `;
}

async function listItems() {
  await ensureSchema();
  const { rows } = await sql`SELECT * FROM plaid_items ORDER BY institution_name`;
  return rows;
}

async function getItem(itemId) {
  await ensureSchema();
  const { rows } = await sql`SELECT * FROM plaid_items WHERE item_id = ${itemId}`;
  return rows[0] || null;
}

async function deleteItem(itemId) {
  await ensureSchema();
  await sql`DELETE FROM plaid_items WHERE item_id = ${itemId}`;
}

async function updateCursor(itemId, cursor) {
  await ensureSchema();
  await sql`UPDATE plaid_items SET transaction_cursor = ${cursor}, health = 'connected', error_message = NULL, updated_at = now() WHERE item_id = ${itemId}`;
}

async function markItemError(itemId, message) {
  await ensureSchema();
  await sql`UPDATE plaid_items SET health = 'error', error_message = ${message}, updated_at = now() WHERE item_id = ${itemId}`;
}

async function updateInstitutionName(itemId, institutionName) {
  await ensureSchema();
  await sql`UPDATE plaid_items SET institution_name = ${institutionName}, updated_at = now() WHERE item_id = ${itemId}`;
}

async function upsertAccounts(itemId, accounts) {
  await ensureSchema();
  for (const account of accounts) {
    await sql`
      INSERT INTO plaid_accounts (
        account_id, item_id, name, type, subtype,
        current_balance, available_balance, credit_limit, updated_at
      )
      VALUES (
        ${account.account_id}, ${itemId}, ${account.name}, ${account.type}, ${account.subtype || null},
        ${account.balances?.current ?? null}, ${account.balances?.available ?? null}, ${account.balances?.limit ?? null}, now()
      )
      ON CONFLICT (account_id)
      DO UPDATE SET
        item_id = excluded.item_id,
        name = excluded.name,
        type = excluded.type,
        subtype = excluded.subtype,
        current_balance = excluded.current_balance,
        available_balance = excluded.available_balance,
        credit_limit = excluded.credit_limit,
        updated_at = now()
    `;
  }
}

async function logSync(itemId, eventType, message) {
  await ensureSchema();
  await sql`INSERT INTO plaid_sync_logs (item_id, event_type, message) VALUES (${itemId || null}, ${eventType}, ${message || null})`;
}

module.exports = {
  deleteItem,
  ensureSchema,
  getItem,
  listItems,
  logSync,
  markItemError,
  updateCursor,
  updateInstitutionName,
  upsertAccounts,
  upsertItem
};
