// Self-service device-code request.
//
// Triggered from the Flutter activation screen when a fresh PC needs a
// code. The user picks their institution (or the trust) and enters
// their details. The Edge Function:
//   1. Validates the email against public.institutionusers — it must
//      be the usemail of an active user of the chosen institution (or a
//      super admin when the trust is chosen).
//   2. Generates a fresh random device activation code.
//   3. Stores its SHA-256 hash in public.device_activations (status='unused').
//   4. Emails the office (tbstechudt@gmail.com) with the details + the
//      cleartext code so the office can forward it to the requester.
//
// The cleartext code is never returned to the requesting PC.
//
// Secrets:
//   RESEND_API_KEY   — same key used by request-activation-code
//   SUPABASE_DB_URL  — auto-injected
//
// Deploy:
//   supabase functions deploy request-device-code

import { Pool } from 'https://deno.land/x/postgres@v0.19.3/mod.ts'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const OFFICE_EMAIL = 'tbstechudt@gmail.com'
const FROM = 'EduCore360 <onboarding@resend.dev>'

function escapeHtml(s: string): string {
  return s
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;').replace(/'/g, '&#39;')
}

const dbUrl = Deno.env.get('SUPABASE_DB_URL') ?? Deno.env.get('DB_URL')
const pool = dbUrl ? new Pool(dbUrl, 1, true) : null

function generateCode(): string {
  const bytes = new Uint8Array(8)
  crypto.getRandomValues(bytes)
  const hex = [...bytes].map((b) => b.toString(16).padStart(2, '0')).join('').toUpperCase()
  return `${hex.slice(0, 4)}-${hex.slice(4, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}`
}

async function sha256Hex(s: string): Promise<string> {
  const buf = new TextEncoder().encode(s)
  const digest = await crypto.subtle.digest('SHA-256', buf)
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, '0')).join('')
}

// AES-256-GCM encrypt `plain` with the shared DEVICE_CODE_ENC_KEY.
// Output is base64( 12-byte IV || ciphertext || 16-byte GCM tag ) —
// the layout the Flutter import expects. Returns null if no key is
// configured, so the caller can fall back to plain JSON.
async function encryptPayload(plain: string): Promise<string | null> {
  const keyB64 = Deno.env.get('DEVICE_CODE_ENC_KEY')
  if (!keyB64) return null
  const keyBytes = Uint8Array.from(atob(keyB64), (c) => c.charCodeAt(0))
  const key = await crypto.subtle.importKey(
    'raw', keyBytes, { name: 'AES-GCM' }, false, ['encrypt'],
  )
  const iv = crypto.getRandomValues(new Uint8Array(12))
  const ct = await crypto.subtle.encrypt(
    { name: 'AES-GCM', iv }, key, new TextEncoder().encode(plain),
  )
  const combined = new Uint8Array(iv.length + ct.byteLength)
  combined.set(iv, 0)
  combined.set(new Uint8Array(ct), iv.length)
  let bin = ''
  for (const b of combined) bin += String.fromCharCode(b)
  return btoa(bin)
}

// True if `email` matches the usemail of an active institutionusers row.
// For the trust (insId null) the row must be a super admin; for an
// institution it must belong to that ins_id.
async function emailIsRegistered(email: string, insId: number | null): Promise<boolean> {
  if (!pool) return false
  const conn = await pool.connect()
  try {
    const res = await conn.queryObject<{ ok: boolean }>(
      `SELECT EXISTS (
         SELECT 1 FROM public.institutionusers
          WHERE activestatus = 1
            AND lower(usemail) = lower($1)
            AND ( ($2::int IS NULL  AND inscode = 'SUPER')
               OR ($2::int IS NOT NULL AND ins_id = $2) )
       ) AS ok`,
      [email, insId],
    )
    return res.rows[0]?.ok === true
  } finally {
    conn.release()
  }
}

async function generateAndStoreCode(insId: number | null, issuedBy: string): Promise<string | null> {
  if (!pool) return null
  const conn = await pool.connect()
  try {
    for (let attempt = 0; attempt < 3; attempt++) {
      const code = generateCode()
      const hash = await sha256Hex(code)
      try {
        await conn.queryObject(
          `INSERT INTO public.device_activations (code_hash, ins_id, status, issued_by)
           VALUES ($1, $2, 'unused', $3)`,
          [hash, insId, issuedBy],
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
        JSON.stringify({ error: 'RESEND_API_KEY not configured' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }

    const body = await req.json().catch(() => ({}))
    const insIdRaw = body.insId
    const insId: number | null = (insIdRaw === null || insIdRaw === undefined) ? null : Number(insIdRaw)
    const isTrust = insId === null
    const insName = String(body.insName ?? '').trim()
    const username = String(body.username ?? '').trim()
    const mobile = String(body.mobile ?? '').trim()
    const email = String(body.email ?? '').trim()
    const machineName = String(body.machineName ?? '').trim()
    const deviceId = String(body.deviceId ?? '').trim()

    if (!isTrust && (!Number.isFinite(insId) || (insId as number) <= 0)) {
      return new Response(
        JSON.stringify({ error: 'insId is required (or pass null for the trust)' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }
    if (email.length === 0) {
      return new Response(
        JSON.stringify({ error: 'Email is required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }

    // Validate the email against the database before issuing a code.
    const validUser = await emailIsRegistered(email, isTrust ? null : (insId as number))
    if (!validUser) {
      return new Response(
        JSON.stringify({
          error: isTrust
            ? 'Email not recognised as a super-admin account.'
            : 'Email not recognised for this institution.',
        }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }

    const issuedBy = isTrust ? 'request-trust' : 'request-institution'
    const code = await generateAndStoreCode(isTrust ? null : (insId as number), issuedBy)
    if (!code) {
      return new Response(
        JSON.stringify({ error: 'Could not generate a code (database unavailable)' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }

    const subject = isTrust
      ? `Device Code Request — Trust: ${insName || '(unknown)'}`
      : `Device Code Request — ${insName || '(unknown)'}`

    // The email body is a JSON payload so it can be parsed by tooling as
    // well as read by a human.
    const payload = {
      type: 'device_code_request',
      target: isTrust ? 'trust' : 'institution',
      institution: insName || null,
      code: code,
      username: username || null,
      mobile: mobile || null,
      email: email || null,
      machineName: machineName || null,
      machineGuid: deviceId || null,
      requestedAt: new Date().toISOString(),
    }
    const jsonStr = JSON.stringify(payload, null, 2)

    // Encrypt the payload when DEVICE_CODE_ENC_KEY is set; otherwise the
    // email carries plain JSON (so it still works before the key is set).
    const encrypted = await encryptPayload(jsonStr)
    const bodyStr = encrypted ?? jsonStr

    // The email has two parts: readable requester details (so the office
    // can verify the request), and the encrypted activation block fenced
    // by markers — the office forwards the whole thing and the app's
    // Import extracts the block between the markers.
    const lbl = (v: string) => (v.length === 0 ? '(not provided)' : v)
    const ACT_BEGIN = '-----BEGIN ACTIVATION-----'
    const ACT_END = '-----END ACTIVATION-----'

    const text = [
      'A device activation code has been requested.',
      '',
      `Target       : ${isTrust ? 'Trust' : 'Institution'}`,
      `Name         : ${lbl(insName)}`,
      `Username     : ${lbl(username)}`,
      `Mobile       : ${lbl(mobile)}`,
      `Email        : ${lbl(email)}`,
      `PC Hostname  : ${lbl(machineName)}`,
      `MachineGuid  : ${lbl(deviceId)}`,
      `Requested At : ${payload.requestedAt}`,
      '',
      'Forward the encrypted block below to the requester. They import it',
      'on the Activate this PC screen (Import Code File).',
      '',
      ACT_BEGIN,
      bodyStr,
      ACT_END,
    ].join('\n')

    const html = `
      <p><b>A device activation code has been requested.</b></p>
      <table style="border-collapse:collapse">
        <tr><td><b>Target</b></td><td style="padding-left:14px">${escapeHtml(isTrust ? 'Trust' : 'Institution')}</td></tr>
        <tr><td><b>Name</b></td><td style="padding-left:14px">${escapeHtml(lbl(insName))}</td></tr>
        <tr><td><b>Username</b></td><td style="padding-left:14px">${escapeHtml(lbl(username))}</td></tr>
        <tr><td><b>Mobile</b></td><td style="padding-left:14px">${escapeHtml(lbl(mobile))}</td></tr>
        <tr><td><b>Email</b></td><td style="padding-left:14px">${escapeHtml(lbl(email))}</td></tr>
        <tr><td><b>PC Hostname</b></td><td style="padding-left:14px">${escapeHtml(lbl(machineName))}</td></tr>
        <tr><td><b>MachineGuid</b></td><td style="padding-left:14px;font-family:monospace">${escapeHtml(lbl(deviceId))}</td></tr>
        <tr><td><b>Requested At</b></td><td style="padding-left:14px">${escapeHtml(payload.requestedAt)}</td></tr>
      </table>
      <p>Forward the encrypted block below to the requester. They import it on the Activate this PC screen.</p>
      <pre style="font-family:monospace;font-size:12px;background:#f4f4f4;padding:14px;border-radius:6px;white-space:pre-wrap;word-break:break-all">${escapeHtml(`${ACT_BEGIN}\n${bodyStr}\n${ACT_END}`)}</pre>
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
