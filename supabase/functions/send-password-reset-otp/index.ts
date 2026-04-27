// Send a password-reset OTP to an institutionusers row's mobile number
// via BulkSMSGateway. Generates the OTP server-side, stores it in
// usemobotp + mobotp_at, then calls the gateway. Returns the masked
// phone (e.g. "******1234") so the UI can show a hint.
//
// We use a direct Postgres connection (SUPABASE_DB_URL) instead of
// PostgREST. PostgREST on projects that have rolled their JWT signing
// secret rejects the legacy service_role JWT as anon, hitting "permission
// denied for schema public" — direct DB access via SUPABASE_DB_URL
// always works because the connection string contains real Postgres
// credentials, not a JWT.
//
// Configure secrets in Supabase dashboard → Edge Functions → Secrets:
//   BULKSMS_USER, BULKSMS_PASSWORD, BULKSMS_SENDER, BULKSMS_TEMPLATE_ID
//   SUPABASE_DB_URL  — auto-injected by the platform
//
// Deploy:
//   supabase functions deploy send-password-reset-otp

import { Pool } from 'https://deno.land/x/postgres@v0.19.3/mod.ts'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

function maskPhone(phone: string): string {
  const digits = phone.replace(/\D/g, '')
  if (digits.length < 4) return '****'
  return '*'.repeat(digits.length - 4) + digits.slice(-4)
}

// Strip country code and non-digits, leave a clean 10-digit Indian number.
function cleanMobile(raw: string): string {
  const digits = raw.replace(/\D/g, '')
  return digits.length > 10 ? digits.slice(-10) : digits
}

const dbUrl = Deno.env.get('SUPABASE_DB_URL') ?? Deno.env.get('DB_URL')
const pool = dbUrl ? new Pool(dbUrl, 1, true) : null

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const { email } = await req.json()
    if (!email || typeof email !== 'string') {
      return new Response(JSON.stringify({ error: 'email required' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    if (!pool) {
      return new Response(JSON.stringify({
        error: 'database connection not configured',
        hint: 'Set SUPABASE_DB_URL (or DB_URL) as an Edge Function secret',
      }), {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      })
    }

    const conn = await pool.connect()
    try {
      const lookup = await conn.queryObject<{ use_id: number; usephone: string }>(
        `SELECT use_id, usephone
           FROM public.institutionusers
          WHERE LOWER(usemail) = LOWER($1)
            AND activestatus = 1
          LIMIT 1`,
        [email.trim()],
      )

      if (lookup.rows.length === 0) {
        // Don't leak whether the email exists.
        return new Response(JSON.stringify({ ok: true, masked: '****' }), {
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        })
      }

      const user = lookup.rows[0]
      const phone = cleanMobile(user.usephone ?? '')
      if (phone.length !== 10) {
        return new Response(JSON.stringify({ error: 'no valid mobile on file' }), {
          status: 422,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        })
      }

      const otp = Math.floor(100000 + Math.random() * 900000)

      await conn.queryObject(
        `UPDATE public.institutionusers
            SET usemobotp = $1,
                mobotp_at = now(),
                useotpstatus = 0
          WHERE use_id = $2`,
        [otp, user.use_id],
      )

      // Must match the DLT-approved template registered against
      // BULKSMS_TEMPLATE_ID exactly — TRAI rejects any deviation.
      // The same template is reused for password reset; the text is
      // intentionally generic ("Login User Account creation") because
      // that's what the regulator approved.
      const message = `Thanks for Choosing Krishnasamy Institution. OTP for Login User Account creation is: ${otp}.`
      const url = new URL('http://api.bulksmsgateway.in/sendmessage.php')
      url.searchParams.set('user', Deno.env.get('BULKSMS_USER') ?? '')
      url.searchParams.set('password', Deno.env.get('BULKSMS_PASSWORD') ?? '')
      url.searchParams.set('mobile', phone)
      url.searchParams.set('message', message)
      url.searchParams.set('sender', Deno.env.get('BULKSMS_SENDER') ?? 'TBSTEC')
      url.searchParams.set('type', '3')
      url.searchParams.set('template_id', Deno.env.get('BULKSMS_TEMPLATE_ID') ?? '')

      const smsRes = await fetch(url.toString())
      const smsBody = await smsRes.text()
      const looksOk =
        smsRes.status === 200 &&
        (/^\d+$/.test(smsBody.trim()) || /success|sent/i.test(smsBody))
      if (!looksOk) {
        return new Response(
          JSON.stringify({
            error: 'SMS gateway rejected',
            detail: smsBody.slice(0, 200),
          }),
          {
            status: 502,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          },
        )
      }

      return new Response(
        JSON.stringify({ ok: true, masked: maskPhone(phone) }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    } finally {
      conn.release()
    }
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})
