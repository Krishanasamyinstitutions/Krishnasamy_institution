// Product-license request.
//
// Triggered from the Flutter "Activate Product" screen when an
// institution wants to apply for a new annual product license. The
// Edge Function:
//   1. Generates a fresh random license code (alregcode).
//   2. Inserts a row into public.tbsannuallicense with alpermit='N',
//      default 1-year validity (start = today, end = today + 365),
//      and the requester's metadata.
//   3. Emails the office (tbstechudt@gmail.com) with the institution
//      details + the cleartext code so the office can review and
//      forward it to the requester. The office can also adjust the
//      dates by editing the row in SQL before the customer activates.
//
// The cleartext code is never returned to the requesting PC — only the
// office sees it and forwards it externally.
//
// Secrets:
//   RESEND_API_KEY   — same key used by request-activation-code
//   SUPABASE_DB_URL  — auto-injected
//
// Deploy:
//   supabase functions deploy request-product-license

import { Pool } from 'https://deno.land/x/postgres@v0.19.3/mod.ts'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const OFFICE_EMAIL = 'tbstechudt@gmail.com'
const FROM = 'EduCore360 <onboarding@resend.dev>'
const PRODUCT_CODE = 'EDUCORE360'

function escapeHtml(s: string): string {
  return s
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;').replace(/'/g, '&#39;')
}

const dbUrl = Deno.env.get('SUPABASE_DB_URL') ?? Deno.env.get('DB_URL')
const pool = dbUrl ? new Pool(dbUrl, 1, true) : null

function generateCode(): string {
  const bytes = new Uint8Array(4)
  crypto.getRandomValues(bytes)
  const hex = [...bytes].map((b) => b.toString(16).padStart(2, '0')).join('').toUpperCase()
  return `EDU-PROD-${new Date().getFullYear()}-${hex}`
}

async function insertLicenseRow(
  code: string,
  insName: string,
  contact: string,
): Promise<{ alId: number; startDate: string; endDate: string; alyear: string } | null> {
  if (!pool) return null
  const conn = await pool.connect()
  try {
    const idRes = await conn.queryObject<{ next_id: number }>(
      `SELECT COALESCE(MAX(al_id), 0) + 1 AS next_id FROM public.tbsannuallicense`,
    )
    const nextId = Number(idRes.rows[0]?.next_id ?? 1)

    const today = new Date()
    const end = new Date(today)
    end.setFullYear(end.getFullYear() + 1)
    const toIso = (d: Date) => d.toISOString().slice(0, 10)
    const startIso = toIso(today)
    const endIso = toIso(end)
    const alyear = `${today.getFullYear()}-${today.getFullYear() + 1}`

    await conn.queryObject(
      `INSERT INTO public.tbsannuallicense
         (al_id, alyear, alpermit, alperdate, alperref, aluser, alprodcode, alregcode, start_date, end_date)
       VALUES ($1, $2, 'N', CURRENT_DATE, $3, $4, $5, $6, $7, $8)`,
      [nextId, alyear, `REQ${nextId}`, contact || 'office', PRODUCT_CODE, code, startIso, endIso],
    )
    return { alId: nextId, startDate: startIso, endDate: endIso, alyear }
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
    const insName = String(body.insName ?? '').trim()
    const contact = String(body.contact ?? '').trim()
    const mobile = String(body.mobile ?? '').trim()
    const email = String(body.email ?? '').trim()
    const machineName = String(body.machineName ?? '').trim()

    let code = ''
    let alyear = ''
    let startDate = ''
    let endDate = ''
    for (let attempt = 0; attempt < 3; attempt++) {
      code = generateCode()
      try {
        const row = await insertLicenseRow(code, insName, contact)
        if (row) {
          alyear = row.alyear
          startDate = row.startDate
          endDate = row.endDate
        }
        break
      } catch (e) {
        const msg = String(e)
        if (!msg.includes('23505') && !msg.toLowerCase().includes('unique')) throw e
      }
    }
    if (!code || !startDate) {
      return new Response(
        JSON.stringify({ error: 'Could not generate a license code (database unavailable)' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      )
    }

    const labelOrUnknown = (v: string) => (v.length === 0 ? '(not provided)' : v)
    const subject = `Product License Request — ${labelOrUnknown(insName)}`

    const text = [
      'Hello,',
      '',
      'A new product license has been requested. The license row has been pre-seeded in tbsannuallicense (alpermit=N) with a 1-year default validity. Adjust start_date / end_date in SQL if you want a different period before forwarding.',
      '',
      'Requester details:',
      `  Institution/Business : ${labelOrUnknown(insName)}`,
      `  Contact Person       : ${labelOrUnknown(contact)}`,
      `  Mobile               : ${labelOrUnknown(mobile)}`,
      `  Email                : ${labelOrUnknown(email)}`,
      `  Machine hostname     : ${labelOrUnknown(machineName)}`,
      '',
      'License details:',
      `  Year   : ${alyear}`,
      `  Start  : ${startDate}`,
      `  End    : ${endDate}`,
      '',
      '→ Forward this product license code to the requester:',
      `  ${code}`,
      '',
      'The customer can enter this on the Activate Product screen. After entry, alpermit flips to Y and the app unlocks until end_date.',
      '',
      'Thank you.',
    ].join('\n')

    const html = `
      <p>Hello,</p>
      <p>A new product license has been requested. The license row has been pre-seeded in <code>tbsannuallicense</code> (alpermit=N) with a 1-year default validity. Adjust <code>start_date</code> / <code>end_date</code> in SQL if you want a different period before forwarding.</p>
      <p><b>Requester details</b></p>
      <table style="border-collapse:collapse">
        <tr><td><b>Institution/Business</b></td><td style="padding-left:14px">${escapeHtml(labelOrUnknown(insName))}</td></tr>
        <tr><td><b>Contact Person</b></td><td style="padding-left:14px">${escapeHtml(labelOrUnknown(contact))}</td></tr>
        <tr><td><b>Mobile</b></td><td style="padding-left:14px">${escapeHtml(labelOrUnknown(mobile))}</td></tr>
        <tr><td><b>Email</b></td><td style="padding-left:14px">${escapeHtml(labelOrUnknown(email))}</td></tr>
        <tr><td><b>Machine hostname</b></td><td style="padding-left:14px">${escapeHtml(labelOrUnknown(machineName))}</td></tr>
      </table>
      <p><b>License details</b></p>
      <table style="border-collapse:collapse">
        <tr><td><b>Year</b></td><td style="padding-left:14px">${escapeHtml(alyear)}</td></tr>
        <tr><td><b>Start</b></td><td style="padding-left:14px">${escapeHtml(startDate)}</td></tr>
        <tr><td><b>End</b></td><td style="padding-left:14px">${escapeHtml(endDate)}</td></tr>
      </table>
      <p style="margin-top:16px"><b>Forward this product license code to the requester:</b></p>
      <p style="font-family:monospace;font-size:20px;background:#f4f4f4;padding:10px 14px;border-radius:6px;display:inline-block;letter-spacing:2px">${escapeHtml(code)}</p>
      <p>The customer can enter this on the Activate Product screen. After entry, alpermit flips to Y and the app unlocks until end_date.</p>
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
