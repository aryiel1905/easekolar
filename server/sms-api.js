// server/sms-api.js
// Tiny local API to send SMS via ClickSend immediately when admin clicks Confirm.
// Reads credentials from .env and updates public.sms_outbox for audit.

import 'dotenv/config';
import express from 'express';
import cors from 'cors';
import { Client as PgClient } from 'pg';

const {
  PORT = '8787',
  DATABASE_URL,
  ALLOW_INSECURE_TLS,
  CLICKSEND_USERNAME,
  CLICKSEND_API_KEY,
  CLICKSEND_FROM,
} = process.env;

if (ALLOW_INSECURE_TLS === '1') {
  console.warn('WARNING: ALLOW_INSECURE_TLS=1 — TLS verification disabled for outbound HTTPS.');
  process.env.NODE_TLS_REJECT_UNAUTHORIZED = '0';
}

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
  const f = globalThis.fetch ?? (await import('node-fetch')).default;
  const url = 'https://rest.clicksend.com/v3/sms/send';
  const token = Buffer.from(`${CLICKSEND_USERNAME}:${CLICKSEND_API_KEY}`).toString('base64');
  const headers = {
    Authorization: `Basic ${token}`,
    Accept: 'application/json',
    'Content-Type': 'application/json',
  };
  const payload = {
    messages: [
      {
        source: 'local-api',
        to,
        body,
        ...(CLICKSEND_FROM ? { from: CLICKSEND_FROM } : {}),
      },
    ],
  };
  const resp = await f(url, { method: 'POST', headers, body: JSON.stringify(payload) });
  const json = await resp.json().catch(() => ({}));
  const first = json?.data?.messages?.[0];
  if (!resp.ok || first?.status !== 'SUCCESS') {
    const code = json?.http_code ?? resp.status;
    const errTxt = first?.error ?? json?.response_msg ?? resp.statusText;
    throw new Error(`ClickSend error ${code}: ${errTxt || 'unknown'}`);
  }
  return first?.message_id || null;
}

const app = express();
app.use(cors());
app.use(express.json({ limit: '256kb' }));

let pgClient = null;
async function getDb() {
  if (!DATABASE_URL) return null;
  if (pgClient) return pgClient;
  pgClient = new PgClient({ connectionString: DATABASE_URL, ssl: { rejectUnauthorized: false } });
  await pgClient.connect().catch((e) => {
    console.warn('DB connect failed (continuing without DB updates):', String(e));
    pgClient = null;
  });
  return pgClient;
}

app.post('/sms/send', async (req, res) => {
  try {
    if (!CLICKSEND_USERNAME || !CLICKSEND_API_KEY) {
      return res.status(500).json({ error: 'ClickSend credentials not configured' });
    }

    const { to, message, applicant_id, email, status } = req.body || {};
    if (!to || !message) {
      return res.status(400).json({ error: 'to and message required' });
    }

    const toNorm = normalizePhonePH(to);
    if (!toNorm) return res.status(400).json({ error: 'invalid destination number' });

    const messageId = await sendViaClickSend(toNorm, message);

    // Best-effort DB update
    try {
      const db = await getDb();
      if (db && applicant_id) {
        const { rows } = await db.query(
          `SELECT id FROM public.sms_outbox
            WHERE applicant_id=$1 AND status='queued'
            ORDER BY created_at DESC LIMIT 1`,
          [applicant_id]
        );
        if (rows.length) {
          await db.query(
            `UPDATE public.sms_outbox
                SET status='sent', provider_message_id=$1, attempts=attempts+1,
                    sent_at=now(), updated_at=now()
              WHERE id=$2`,
            [messageId, rows[0].id]
          );
        } else {
          await db.query(
            `INSERT INTO public.sms_outbox (applicant_id, email, to_number, message, status, provider_message_id)
             VALUES ($1,$2,$3,$4,'sent',$5)`,
            [applicant_id, email ?? null, toNorm, message, messageId]
          );
        }
      }
    } catch (e) {
      console.warn('DB update warning:', String(e));
    }

    res.json({ ok: true, message_id: messageId });
  } catch (e) {
    console.error('Send error:', e);
    res.status(502).json({ error: String(e) });
  }
});

app.get('/health', (req, res) => {
  res.json({ ok: true });
});

app.listen(parseInt(PORT, 10) || 8787, () => {
  console.log(`SMS API listening on http://127.0.0.1:${PORT}`);
});

