# Legacy Vercel Plaid Backend

This Vercel backend has been superseded by the Supabase implementation in `../supabase`.

## Required Environment Variables

- `PLAID_CLIENT_ID`
- `PLAID_SECRET`
- `PLAID_ENV=production`
- `PLAID_PRODUCTS=transactions,investments,liabilities`
- `PLAID_COUNTRY_CODES=US`
- `PLAID_REDIRECT_URI=https://<your-domain>/plaid/oauth`
- `PLAID_WEBHOOK_URL=https://<your-domain>/api/plaid/webhook`
- `APP_SYNC_KEY`
- `PLAID_TOKEN_ENCRYPTION_KEY`
- `POSTGRES_URL` and related Vercel Postgres env vars
- `APPLE_TEAM_ID`
- `APP_BUNDLE_ID=Timothy-Wong.Budgeting-App`

## Plaid Dashboard Setup

1. Enable Production or Limited Production access.
2. Enable `transactions`, `investments`, and `liabilities`.
3. Add `https://<your-domain>/plaid/oauth` as the iOS OAuth redirect URI.
4. Add `https://<your-domain>/api/plaid/webhook` as the webhook URL.

## iOS Setup

1. Deploy this backend to Vercel.
2. In Xcode, set the Associated Domains entitlement to `applinks:<your-domain>`.
3. In the app, open Settings -> Plaid Sync.
4. Enter the backend URL and `APP_SYNC_KEY`.
5. Tap Connect Account.
