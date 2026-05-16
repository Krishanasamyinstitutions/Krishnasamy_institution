import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders })
  }

  try {
    const { amount, currency, pay_id, receipt } = await req.json()

    if (!amount || !pay_id) {
      return new Response(JSON.stringify({ error: "Missing required fields" }), {
        status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" },
      })
    }

    const razorpayKeyId = Deno.env.get("RAZORPAY_KEY_ID")
    const razorpayKeySecret = Deno.env.get("RAZORPAY_KEY_SECRET")

    if (!razorpayKeyId || !razorpayKeySecret) {
      return new Response(JSON.stringify({ error: "Payment gateway not configured" }), {
        status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" },
      })
    }

    const basicAuth = btoa(`${razorpayKeyId}:${razorpayKeySecret}`)
    const razorpayResponse = await fetch("https://api.razorpay.com/v1/orders", {
      method: "POST",
      headers: { Authorization: `Basic ${basicAuth}`, "Content-Type": "application/json" },
      body: JSON.stringify({ amount, currency: currency || "INR", receipt: receipt || `PAY-${pay_id}`, payment_capture: 1 }),
    })

    const razorpayOrder = await razorpayResponse.json()

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    const supabase = createClient(supabaseUrl, supabaseServiceKey)
    await supabase.from("payment").update({ payorderid: razorpayOrder.id }).eq("pay_id", pay_id)

    return new Response(JSON.stringify({ order_id: razorpayOrder.id, amount: razorpayOrder.amount, currency: razorpayOrder.currency, status: razorpayOrder.status }), {
      status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" },
    })
  } catch (err) {
    return new Response(JSON.stringify({ error: err.message }), {
      status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" },
    })
  }
})
