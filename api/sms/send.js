import { Client as PgClient } from 'pg';

function normalizePhonePH(p) {
  if (!p) return null;
  let d = String(p).replace(/[^0-9+]/g, '');
  if (d.startsWith('+')) return d;
  d = d.replace(/[^0-9]/g, '');
  if (d.startsWith('09') && d.length === 11) return '+63' + d.slice(1);
  if (d.startsWith('9') && d.length === 10) return '+63' + d;
  if (d.startsWith('639') && d.length === 12) return '+' + d;
  return null;
}

async function sendViaClickSend(to, body) {
  const { CLICKSEND_USERNAME, CLICKSEND_API_KEY, CLICKSEND_FROM } = process.env;
  if (!CLICKSEND_USERNAME || !CLICKSEND_API_KEY) {
    throw new Error('ClickSend credentials not configured');
  }
  const token = Buffer.from(`${CLICKSEND_USERNAME}:${CLICKSEND_API_KEY}`).toString('base64');
  const payload = {
    messages: [
      { source: 'vercel-fn', to, body, ...(CLICKSEND_FROM ? { from: CLICKSEND_FROM } : {}) },
    ],
  };
  const r = await fetch('https://rest.clicksend.com/v3/sms/send', {
    method: 'POST',
    headers: {
      Authorization: `Basic ${token}`,
      Accept: 'application/json',
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(payload),
  });
  const j = await r.json().catch(() => ({}));
  const first = j?.data?.messages?.[0];
  if (!r.ok || first?.status !== 'SUCCESS') {
    const code = j?.http_code ?? r.status;
    const errTxt = first?.error ?? j?.response_msg ?? r.statusText;
    throw new Error(`ClickSend error ${code}: ${errTxt}`);
  }
  return first?.message_id || null;
}

async function updateOutbox(applicant_id, email, to, message, providerId) {
  const { DATABASE_URL } = process.env;
  if (!DATABASE_URL) return; // DB optional on Vercel; skip if missing
  const pg = new PgClient({ connectionString: DATABASE_URL, ssl: { rejectUnauthorized: false } });
  try {
    await pg.connect();
    const { rows } = await pg.query(
      `SELECT id FROM public.sms_outbox
         WHERE applicant_id=$1 AND status='queued'
         ORDER BY created_at DESC LIMIT 1`,
      [applicant_id]
    );
    if (rows.length) {
      await pg.query(
        `UPDATE public.sms_outbox
            SET status='sent', provider_message_id=$1, attempts=attempts+1,
                sent_at=now(), updated_at=now()
          WHERE id=$2`,
        [providerId, rows[0].id]
      );
    } else {
      await pg.query(
        `INSERT INTO public.sms_outbox (applicant_id, email, to_number, message, status, provider_message_id)
         VALUES ($1,$2,$3,$4,'sent',$5)`,
        [applicant_id, email ?? null, to, message, providerId]
      );
    }
  } catch (e) {
    console.warn('DB update warning:', String(e));
  } finally {
    try { await pg.end(); } catch (_) {}
  }
}

export default async function handler(req, res) {
  // CORS
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST,OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  if (req.method === 'OPTIONS') return res.status(204).end();

  if (req.method !== 'POST') return res.status(405).json({ error: 'POST only' });
  try {
    const { to, message, applicant_id, email, status } = req.body || {};
    if (!to || !message) return res.status(400).json({ error: 'to and message required' });
    const toNorm = normalizePhonePH(to);
    if (!toNorm) return res.status(400).json({ error: 'invalid destination number' });

    const messageId = await sendViaClickSend(toNorm, message);
    await updateOutbox(applicant_id, email, toNorm, message, messageId);

    return res.status(200).json({ ok: true, message_id: messageId });
  } catch (e) {
    console.error(e);
    return res.status(502).json({ error: String(e) });
  }
}

