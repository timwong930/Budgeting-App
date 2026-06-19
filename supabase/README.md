# Supabase Plaid Backend

This replaces the earlier Vercel backend with one routed Supabase Edge Function and Supabase Postgres storage.

## Project

- Supabase project: `Momo's Money`
- Project ref: `zqjvfmkesfwdtgwkcuxc`
- Edge Function URL: `https://zqjvfmkesfwdtgwkcuxc.functions.supabase.co/functions/v1/plaid`

Enter that Edge Function URL as the Plaid backend URL inside the iOS app.

## Secrets

Set these with the Supabase CLI. Do not commit the real values.

```bash
supabase secrets set \
  PLAID_CLIENT_ID='your-plaid-client-id' \
  PLAID_SECRET='your-production-plaid-secret' \
  PLAID_ENV='production' \
  PLAID_PRODUCTS='transactions,investments,liabilities' \
  PLAID_COUNTRY_CODES='US' \
  PLAID_REDIRECT_URI='https://zqjvfmkesfwdtgwkcuxc.functions.supabase.co/functions/v1/plaid/plaid/oauth' \
  PLAID_WEBHOOK_URL='https://zqjvfmkesfwdtgwkcuxc.functions.supabase.co/functions/v1/plaid/api/plaid/webhook' \
  APP_SYNC_KEY='your-private-app-sync-key' \
  PLAID_TOKEN_ENCRYPTION_KEY='your-token-encryption-key' \
  APPLE_TEAM_ID='your-apple-team-id' \
  APP_BUNDLE_ID='Timothy-Wong.Budgeting-App'
```

Generate private keys with:

```bash
openssl rand -base64 32
```

Use one generated value for `APP_SYNC_KEY` and another for `PLAID_TOKEN_ENCRYPTION_KEY`.

## Deploy

```bash
export SUPABASE_DB_PASSWORD='your-supabase-database-password'
supabase db push
supabase functions deploy plaid --no-verify-jwt
```

The function has already been deployed once. Run `supabase functions deploy plaid --no-verify-jwt` again after future function edits.

## Plaid Dashboard

Register these URLs in Plaid:

- OAuth redirect URI: `https://zqjvfmkesfwdtgwkcuxc.functions.supabase.co/functions/v1/plaid/plaid/oauth`
- Webhook URL: `https://zqjvfmkesfwdtgwkcuxc.functions.supabase.co/functions/v1/plaid/api/plaid/webhook`

## Universal Links

Plaid iOS OAuth requires Apple Universal Links. Supabase Edge Functions work for the Plaid API backend, but the default functions domain does not serve `/.well-known/apple-app-site-association` from the domain root.

For OAuth institutions, use one of these:

- Configure a Supabase custom domain that can serve the AASA file at the root.
- Put a tiny static host or reverse proxy in front of the function domain only for `/.well-known/apple-app-site-association`.
- Connect only non-OAuth institutions until the AASA file is reachable from the Associated Domain root.
