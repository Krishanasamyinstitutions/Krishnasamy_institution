# Integration Tests

Run scenarios end-to-end against a real (staging) Supabase project.

## Prerequisites

1. **Staging Supabase project** — clone the production schema with `supabase db dump` and restore to a fresh project. NEVER run integration tests against production.
2. **Test seed** — apply `test_data/test_seed.sql` (TBD in Phase 3) so a known student/payment exists.
3. **Local credentials** — set environment variables before running:

```cmd
set TEST_INSTITUTION_EMAIL=test@kcet.local
set TEST_INSTITUTION_PASSWORD=Test@2026
set SUPABASE_URL=https://<staging-ref>.supabase.co
set SUPABASE_ANON_KEY=<staging-anon-key>
```

## Run

```cmd
flutter test integration_test/app_smoke_test.dart -d windows
```

For a specific scenario:

```cmd
flutter test integration_test/auth_flow_test.dart -d windows
```

## Scenarios (per plan)

| File | Scenario |
|---|---|
| `app_smoke_test.dart` | Cold start, MaterialApp renders |
| `auth_flow_test.dart` | Login → Dashboard → Logout (TBD) |
| `auto_login_test.dart` | Persisted password auto-login (TBD) |
| `cash_payment_test.dart` | Cash payment + receipt (TBD) |
| `bank_recon_test.dart` | Upload HDFC/ICICI/SBI/IOB CSVs, reconcile (TBD) |
| `report_export_test.dart` | Daily Collection Excel + PDF export (TBD) |
| `forgot_password_test.dart` | OTP password reset (TBD) |

## Why a separate folder

Integration tests need a real device/window (`-d windows`) and start the full app — they're slow (10-30 s each) and shouldn't run on every save. Unit and widget tests under `test/` run in <10 s and are the first line of defence.
