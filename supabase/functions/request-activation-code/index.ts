// Send an activation-code request email to the office inbox.
//
// Triggered from the Flutter app when an institution either (a) is filling
// out the registration form and clicks "Don't have a code? Request one", or
// (b) lands on the Subscription Expired screen and clicks "Request
// Activation Code". The Edge Function:
//   1. Generates a fresh random activation code, formatted EDU-XXXXXX-XXXXXX,
//      and inserts it into public.license_keys with status='active'.
//   2. Emails the office (tbstechudt@gmail.com) with the institution's details
//      AND the generated code, so the office can simply forward it to the
//      institution without having to seed or maintain a key pool.
//
// The new key starts as 'active' and is flipped to 'used' atomically when
// the institution registers (inside register_institution). If the institution
// never comes back, the row stays 'active' but is also still reusable —
// every call generates a brand-new code, so abandoned codes don't pile up
// in any meaningful way (they're just unused rows).
//
// Configure secrets in Supabase dashboard → Edge Functions → Secrets:
//   RESEND_API_KEY   — from https://resend.com/api-keys
//   SUPABASE_DB_URL  — auto-injected by the platform
//
// Deploy:
//   supabase functions deploy request-activation-code

import { Pool } from 'https://deno.land/x/postgres@v0.19.3/mod.ts'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const OFFICE_EMAIL = 'tbstechudt@gmail.com'

// Resend lets you send to any inbox without verifying a domain as long as
// the From address uses their sandbox onboarding@resend.dev. Good enough
// for an internal request inbox; switch to a verified domain later if you
// want From: to read like your own brand.
const FROM = 'EduCore360 <onboarding@resend.dev>'

function escapeHtml(s: string): string {
  return s
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;')
}

const dbUrl = Deno.env.get('SUPABASE_DB_URL') ?? Deno.env.get('DB_URL')
const pool = dbUrl ? new Pool(dbUrl, 1, true) : null

// Format: EDU-XXXXXX-XXXXXX (uppercase hex). 12 hex chars = ~4.7e14 entropy,
// enough that random collision against a unique-key table is effectively
// impossible. Hex (vs base32/36) keeps it unambiguous when read aloud.
function generateCode(): string {
  const bytes = new Uint8Array(6)
  crypto.getRandomValues(bytes)
  const hex = [...bytes].map((b) => b.toString(16).padStart(2, '0')).join('').toUpperCase()
  return `EDU-${hex.slice(0, 6)}-${hex.slice(6, 12)}`
}

// SHA-256 hex digest. license_keys stores the hash, never the cleartext —
// only the email recipient (and the institution) ever see the cleartext.
async function sha256Hex(s: string): Promise<string> {
  const buf = new TextEncoder().encode(s)
  const digest = await crypto.subtle.digest('SHA-256', buf)
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, '0')).join('')
}

// Generate a fresh cleartext code, store its hash in license_keys, and
// return the cleartext (which gets emailed to the office). On the
// astronomically unlikely chance of a hash collision or transient DB
// error, retry up to 3 times with a fresh code each time.
async function generateAndStoreKey(): Promise<string | null> {
  if (!pool) return null
  const conn = await pool.connect()
  try {
    for (let attempt = 0; attempt < 3; attempt++) {
      const code = generateCode()
      const hash = await sha256Hex(code)
      try {
        await conn.queryObject(
          `INSERT INTO public.license_keys (license_key, status) VALUES ($1, 'active')`,
          [hash],
        )
        return code
      } catch (e) {
        const msg = String(e)
        if (!msg.includes('23505') && !msg.toLowerCase().includes('unique')) throw e
      }
    }
    return null
  } finally {
    conn.release()
  }
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const apiKey = Deno.env.get('RESEND_API_KEY')
    if (!apiKey) {
      return new Response(
        JSON.stringify({
          error: 'RESEND_API_KEY not configured',
          hint: 'Set it as an Edge Function secret in Supabase dashboard',
        }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }

    const body = await req.json().catch(() => ({}))
    const purpose = String(body.purpose ?? 'register').toLowerCase() // 'register' | 'renewal'
    const insName = String(body.insName ?? '').trim()
    const inscode = String(body.inscode ?? '').trim()
    const contact = String(body.contact ?? '').trim()
    const mobile = String(body.mobile ?? '').trim()
    const email = String(body.email ?? '').trim()

    const labelOrUnknown = (v: string) => (v.length === 0 ? '(not provided)' : v)

    // Generate a fresh activation code and insert it into license_keys.
    // The office gets the code in the email and forwards it to the
    // institution. If DB is unavailable or generation fails after retries,
    // the email goes out anyway with a clear warning.
    const pickedCode = await generateAndStoreKey().catch((e: unknown) => {
      console.error('generateAndStoreKey failed:', e)
      return null
    })

    const subject = purpose === 'renewal'
      ? `Activation Code Renewal Request${insName ? ' - ' + insName : ''}`
      : `Activation Code Request${insName ? ' - ' + insName : ''}`

    const intro = purpose === 'renewal'
      ? 'Our subscription has expired or our license key was revoked. Please issue a new activation code for the following institution:'
      : 'Please issue an activation code for the following institution:'

    const codeLine = pickedCode
      ? `\n\n→ Forward this activation code to the institution:\n  ${pickedCode}\n`
      : `\n\n⚠ Could not generate an activation code (database unavailable). Please retry or generate one manually.\n`

    const text = [
      'Hello,',
      '',
      intro,
      '',
      `Institution Name : ${labelOrUnknown(insName)}`,
      `Institution Code : ${labelOrUnknown(inscode)}`,
      `Contact Person   : ${labelOrUnknown(contact)}`,
      `Mobile           : ${labelOrUnknown(mobile)}`,
      `Email            : ${labelOrUnknown(email)}`,
      codeLine,
      'Thank you.',
    ].join('\n')

    const codeHtml = pickedCode
      ? `<p style="margin-top:16px"><b>Forward this activation code to the institution:</b></p>
         <p style="font-family:monospace;font-size:18px;background:#f4f4f4;padding:10px 14px;border-radius:6px;display:inline-block">${escapeHtml(pickedCode)}</p>`
      : `<p style="margin-top:16px;color:#b00"><b>Could not generate an activation code</b> (database unavailable). Please retry or generate one manually.</p>`

    const html = `
      <p>Hello,</p>
      <p>${escapeHtml(intro)}</p>
      <table style="border-collapse:collapse">
        <tr><td><b>Institution Name</b></td><td>${escapeHtml(labelOrUnknown(insName))}</td></tr>
        <tr><td><b>Institution Code</b></td><td>${escapeHtml(labelOrUnknown(inscode))}</td></tr>
        <tr><td><b>Contact Person</b></td><td>${escapeHtml(labelOrUnknown(contact))}</td></tr>
        <tr><td><b>Mobile</b></td><td>${escapeHtml(labelOrUnknown(mobile))}</td></tr>
        <tr><td><b>Email</b></td><td>${escapeHtml(labelOrUnknown(email))}</td></tr>
      </table>
      ${codeHtml}
      <p>Thank you.</p>
    `

    const resendRes = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${apiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        from: FROM,
        to: [OFFICE_EMAIL],
        // Reply-To sends the office's reply back to the institution's email
        // (when provided) instead of bouncing to the resend.dev sandbox.
        ...(email && { reply_to: email }),
        subject,
        text,
        html,
      }),
    })

    if (!resendRes.ok) {
      const detail = await resendRes.text()
      return new Response(
        JSON.stringify({ error: 'Resend rejected', status: resendRes.status, detail: detail.slice(0, 400) }),
        { status: 502, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }

    return new Response(
      JSON.stringify({ ok: true }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    )
  } catch (e) {
    return new Response(
      JSON.stringify({ error: String(e) }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    )
  }
})
