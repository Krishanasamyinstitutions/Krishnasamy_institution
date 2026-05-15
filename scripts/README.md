# Deployment scripts

Helpers for getting the Supabase side of EduCore360 set up on a brand-new
project, or pushing updates to the existing one.

## Files

| File | Purpose |
|---|---|
| `secrets.env.example` | Template listing every Edge Function secret. Copy to `secrets.env` (gitignored) and fill in real values. |
| `set_secrets.ps1` | Reads `secrets.env` and pushes everything to the linked Supabase project via `supabase secrets set`. |
| `deploy_functions.ps1` | Auto-discovers every folder under `supabase/functions/*/index.ts` and runs `supabase functions deploy` for each. |
| `bootstrap_new_supabase.ps1` | One-shot link + set secrets + deploy. Use when wiring a fresh Supabase project. |

All scripts fall back to `npx supabase ...` when the global CLI isn't on
`PATH`, so you don't need to install the CLI ahead of time.

## Setting up a brand-new Supabase project

```
0. Create the project at https://supabase.com (note the project ref).
1. Apply the database schema:
   • Open C:\pg_backups\complete_setup.sql in your editor.
   • Paste into Supabase Dashboard → SQL Editor → Run.
   • (This creates every table, RPC, and the tbsannuallicense product
     license, RLS policies, etc.)
2. Set up secrets:
   • cp scripts/secrets.env.example scripts/secrets.env
   • Edit scripts/secrets.env and fill in real values
     (RESEND_API_KEY, BULKSMS_*, RAZORPAY_*).
3. Wire up Edge Functions in one shot:
   pwsh -ExecutionPolicy Bypass -File scripts\bootstrap_new_supabase.ps1 `
        -ProjectRef <YOUR_NEW_PROJECT_REF>
4. Point the Flutter app at the new project:
   • Edit lib/config/supabase_config.dart
   • Replace `url` and `anonKey` with the new project's values
     (Dashboard → Project Settings → API).
5. flutter pub get && flutter run -d windows
```

## Common ongoing tasks

**Deploy after editing an Edge Function:**
```
pwsh -ExecutionPolicy Bypass -File scripts\deploy_functions.ps1
```

**Rotate a secret:**
```
# Edit scripts\secrets.env, then:
pwsh -ExecutionPolicy Bypass -File scripts\set_secrets.ps1
```

**Re-run bootstrap after only some pieces changed:**
```
# Only push secrets, skip link + deploy:
pwsh -ExecutionPolicy Bypass -File scripts\bootstrap_new_supabase.ps1 `
     -ProjectRef <ref> -SkipLink -SkipDeploy
```

## Edge Functions currently in the project

| Function | Purpose | Secrets required |
|---|---|---|
| `request-activation-code` | New institution registration emails office a license key. | `RESEND_API_KEY` |
| `request-product-license` | New install requests a product license. Office gets the cleartext code by email. | `RESEND_API_KEY` |
| `send-password-reset-otp` | Sends the 6-digit OTP for institution-user password reset via BulkSMSGateway. | `BULKSMS_USER`, `BULKSMS_PASSWORD`, `BULKSMS_SENDER`, `BULKSMS_TEMPLATE_ID` |
| `create-razorpay-order` | Creates a Razorpay order for a pending fee payment and stamps payorderid on payment row. | `RAZORPAY_KEY_ID`, `RAZORPAY_KEY_SECRET` |
| `get-razorpay-payment` | Fetches Razorpay payment status (used after gateway redirect to confirm capture). | `RAZORPAY_KEY_ID`, `RAZORPAY_KEY_SECRET` |

`SUPABASE_DB_URL`, `SUPABASE_URL`, and `SUPABASE_SERVICE_ROLE_KEY` are
auto-injected by the Edge Function runtime — don't set them manually.
