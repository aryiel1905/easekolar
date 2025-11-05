// supabase/functions/send-sms-clicksend/index.ts
// Edge Function that sends SMS immediately via ClickSend and updates sms_outbox
// POST JSON: { to: string, message: string, applicant_id?: number, email?: string, status?: string }
// Env (set with `supabase secrets set`):
//   CLICKSEND_USERNAME, CLICKSEND_API_KEY, (optional) CLICKSEND_FROM
//   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const CLICKSEND_USERNAME = Deno.env.get("CLICKSEND_USERNAME");
const CLICKSEND_API_KEY = Deno.env.get("CLICKSEND_API_KEY");
const CLICKSEND_FROM = Deno.env.get("CLICKSEND_FROM") || "";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST,OPTIONS",
  "Access-Control-Allow-Headers": "authorization, content-type",
  "Content-Type": "application/json",
};

function normalizePhonePH(p?: string | null): string | null {
  if (!p) return null;
  let d = String(p).replace(/[^0-9+]/g, "");
  if (d.startsWith("+")) return d;
  d = d.replace(/[^0-9]/g, "");
  if (d.startsWith("09") && d.length === 11) return "+63" + d.slice(1);
  if (d.startsWith("9") && d.length === 10) return "+63" + d;
  if (d.startsWith("639") && d.length === 12) return "+" + d;
  return null;
}

async function sendViaClickSend(to: string, body: string) {
  const authHeader = "Basic " + btoa(`${CLICKSEND_USERNAME}:${CLICKSEND_API_KEY}`);
  const payload = {
    messages: [
      {
        source: "edge-fn",
        to,
        body,
        ...(CLICKSEND_FROM ? { from: CLICKSEND_FROM } : {}),
      },
    ],
  };

  const r = await fetch("https://rest.clicksend.com/v3/sms/send", {
    method: "POST",
    headers: {
      Authorization: authHeader,
      Accept: "application/json",
      "Content-Type": "application/json",
    },
    body: JSON.stringify(payload),
  });

  const j = await r.json().catch(() => ({} as any));
  const first = (j as any)?.data?.messages?.[0];
  if (!r.ok || first?.status !== "SUCCESS") {
    const errTxt = first?.error ?? (j as any)?.response_msg ?? r.statusText;
    throw new Error(`ClickSend failed: ${errTxt}`);
  }
  return first?.message_id as string | null;
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: cors });
  if (req.method !== "POST") return new Response(JSON.stringify({ error: "POST only" }), { status: 405, headers: cors });

  try {
    if (!CLICKSEND_USERNAME || !CLICKSEND_API_KEY) {
      return new Response(JSON.stringify({ error: "ClickSend env not set" }), { status: 500, headers: cors });
    }

    const { to, message, applicant_id, email, status } = await req.json();
    if (!to || !message) {
      return new Response(JSON.stringify({ error: "to and message required" }), { status: 400, headers: cors });
    }

    const toNorm = normalizePhonePH(to);
    if (!toNorm) {
      return new Response(JSON.stringify({ error: "invalid destination number" }), { status: 400, headers: cors });
    }

    const msgId = await sendViaClickSend(toNorm, message);

    // Try to mark the most recent trigger-queued outbox row as sent
    if (applicant_id) {
      const { data: queued } = await admin
        .from("sms_outbox")
        .select("id")
        .eq("applicant_id", applicant_id)
        .eq("status", "queued")
        .order("created_at", { ascending: false })
        .limit(1)
        .maybeSingle();

      if (queued?.id) {
        await admin
          .from("sms_outbox")
          .update({
            status: "sent",
            provider_message_id: msgId,
            sent_at: new Date().toISOString(),
            updated_at: new Date().toISOString(),
          })
          .eq("id", queued.id);
      } else {
        // If none queued (e.g., status=Processing), record a sent row
        await admin.from("sms_outbox").insert({
          applicant_id,
          email: email ?? null,
          to_number: toNorm,
          message,
          status: "sent",
          provider_message_id: msgId,
        });
      }
    }

    return new Response(JSON.stringify({ ok: true, message_id: msgId }), { status: 200, headers: cors });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), { status: 500, headers: cors });
  }
});

