// worker/send-sms-twilio.js
import 'dotenv/config';
import { Client as PgClient } from 'pg';
import twilio from 'twilio';

const {
  DATABASE_URL,
  TWILIO_ACCOUNT_SID,
  TWILIO_AUTH_TOKEN,
  TWILIO_FROM_NUMBER,
  BATCH_SIZE = '20',
  ALLOW_INSECURE_TLS,
} = process.env;

if (!DATABASE_URL || !TWILIO_ACCOUNT_SID || !TWILIO_AUTH_TOKEN || !TWILIO_FROM_NUMBER) {
  console.error('Missing env. Required: DATABASE_URL, TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN, TWILIO_FROM_NUMBER');
  process.exit(1);
}

if (ALLOW_INSECURE_TLS === '1') {
  console.warn('WARNING: ALLOW_INSECURE_TLS=1 — TLS verification disabled for outbound HTTPS.');
  process.env.NODE_TLS_REJECT_UNAUTHORIZED = '0';
}

const pg = new PgClient({ connectionString: DATABASE_URL, ssl: { rejectUnauthorized: false } });
const tw = twilio(TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN);

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
        const resp = await tw.messages.create({
          from: TWILIO_FROM_NUMBER,
          to: r.to_number,
          body: r.message,
        });
        await pg.query(
          `UPDATE public.sms_outbox
             SET status='sent',
                 provider_message_id=$1,
                 attempts=attempts+1,
                 sent_at=now(),
                 updated_at=now()
           WHERE id=$2`,
          [resp.sid, r.id]
        );
        console.log(`Sent id=${r.id} sid=${resp.sid}`);
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

