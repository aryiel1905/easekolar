// worker/send-sms-clicksend.js
// Sends queued messages from public.sms_outbox using ClickSend REST API
// Auth: Basic (username:api_key)

import 'dotenv/config';
import { Client as PgClient } from 'pg';

const {
  DATABASE_URL,
  CLICKSEND_USERNAME,
  CLICKSEND_API_KEY,
  CLICKSEND_FROM, // optional: alphanumeric sender or approved number
  BATCH_SIZE = '20',
  ALLOW_INSECURE_TLS,
} = process.env;

if (!DATABASE_URL || !CLICKSEND_USERNAME || !CLICKSEND_API_KEY) {
  console.error(
    'Missing env. Required: DATABASE_URL, CLICKSEND_USERNAME, CLICKSEND_API_KEY'
  );
  process.exit(1);
}

if (ALLOW_INSECURE_TLS === '1') {
  console.warn(
    'WARNING: ALLOW_INSECURE_TLS=1 — TLS verification disabled for outbound HTTPS.'
  );
  process.env.NODE_TLS_REJECT_UNAUTHORIZED = '0';
}

const pg = new PgClient({ connectionString: DATABASE_URL, ssl: { rejectUnauthorized: false } });

function basicAuthHeader(user, apiKey) {
  const token = Buffer.from(`${user}:${apiKey}`).toString('base64');
  return `Basic ${token}`;
}

async function sendViaClickSend(to, body, customString = undefined) {
  // Prefer global fetch (Node 18+). If unavailable, dynamically import node-fetch.
  const f = globalThis.fetch ?? (await import('node-fetch')).default;
  const url = 'https://rest.clicksend.com/v3/sms/send';
  const payload = {
    messages: [
      {
        source: 'node',
        to,
        body,
        ...(CLICKSEND_FROM ? { from: CLICKSEND_FROM } : {}),
        ...(customString ? { custom_string: customString } : {}),
      },
    ],
  };

  const resp = await f(url, {
    method: 'POST',
    headers: {
      'Authorization': basicAuthHeader(CLICKSEND_USERNAME, CLICKSEND_API_KEY),
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    },
    body: JSON.stringify(payload),
  });

  const json = await resp.json().catch(() => ({}));
  const first = json?.data?.messages?.[0];

  if (!resp.ok || first?.status !== 'SUCCESS') {
    const code = json?.http_code ?? resp.status;
    const errTxt = first?.error ?? json?.response_msg ?? resp.statusText;
    throw new Error(`ClickSend error ${code}: ${errTxt || 'unknown'}`);
  }

  // ClickSend returns message_id UUID
  return first?.message_id || null;
}

async function runOnce() {
  console.log('Connecting to database...');
  await pg.connect();
  console.log('DB connected. Processing queue...');
  try {
    await pg.query('BEGIN');

    const { rows } = await pg.query(
      `SELECT id, to_number, message
         FROM public.sms_outbox
        WHERE status = 'queued'
        ORDER BY created_at
        LIMIT $1
        FOR UPDATE SKIP LOCKED`,
      [parseInt(BATCH_SIZE, 10) || 20]
    );

    console.log(`Found ${rows.length} queued message(s).`);
    for (const r of rows) {
      try {
        console.log(`Sending SMS id=${r.id} to=${r.to_number}...`);
        const messageId = await sendViaClickSend(r.to_number, r.message, `outbox-${r.id}`);
        await pg.query(
          `UPDATE public.sms_outbox
             SET status='sent',
                 provider_message_id=$1,
                 attempts=attempts+1,
                 sent_at=now(),
                 updated_at=now()
           WHERE id=$2`,
          [messageId, r.id]
        );
        console.log(`Sent id=${r.id} message_id=${messageId}`);
      } catch (e) {
        await pg.query(
          `UPDATE public.sms_outbox
             SET status='failed',
                 error=$1,
                 attempts=attempts+1,
                 updated_at=now()
           WHERE id=$2`,
          [String(e), r.id]
        );
        console.warn(`Failed id=${r.id}: ${String(e)}`);
      }
    }

    await pg.query('COMMIT');
  } catch (e) {
    await pg.query('ROLLBACK');
    throw e;
  } finally {
    await pg.end();
  }
}

runOnce().catch((e) => {
  console.error(e);
  process.exit(1);
});

