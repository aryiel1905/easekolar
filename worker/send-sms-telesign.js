// worker/send-sms-telesign.js
import "dotenv/config";
import { Client } from "pg";
import telesignSDK from "telesignsdk";

const {
  DATABASE_URL,
  TELESIGN_CUSTOMER_ID,
  TELESIGN_API_KEY,
  TELESIGN_REST_ENDPOINT = "https://rest-api.telesign.com",
  BATCH_SIZE = "20",
  ALLOW_INSECURE_TLS,
} = process.env;

if (!DATABASE_URL || !TELESIGN_CUSTOMER_ID || !TELESIGN_API_KEY) {
  console.error(
    "Missing required env: DATABASE_URL, TELESIGN_CUSTOMER_ID, TELESIGN_API_KEY"
  );
  process.exit(1);
}

// Optionally relax global TLS verification (e.g., behind corp proxy). Use only if needed.
if (ALLOW_INSECURE_TLS === "1") {
  // eslint-disable-next-line no-console
  console.warn(
    "WARNING: ALLOW_INSECURE_TLS=1 set — TLS certificate verification disabled for outbound HTTPS."
  );
  process.env.NODE_TLS_REJECT_UNAUTHORIZED = "0";
}

// Disable DB cert verification explicitly to avoid SELF_SIGNED_CERT_IN_CHAIN issues
const db = new Client({
  connectionString: DATABASE_URL,
  ssl: { rejectUnauthorized: false },
});
const timeoutMs = 10000;
const ts = new telesignSDK(
  TELESIGN_CUSTOMER_ID,
  TELESIGN_API_KEY,
  TELESIGN_REST_ENDPOINT,
  timeoutMs
);

function sendViaTelesign(to, body) {
  return new Promise((resolve, reject) => {
    const messageType = "ARN"; // Alerts, Reminders, Notifications
    ts.sms.message(
      (err, resp) => {
        if (err) return reject(err);
        const ref = resp?.reference_id ?? resp?.status?.resource_id ?? null;
        resolve(ref);
      },
      to,
      body,
      messageType
    );
  });
}

async function runOnce() {
  console.log("Connecting to database...");
  await db.connect();
  console.log("DB connected. Processing queue...");
  try {
    await db.query("BEGIN");

    const { rows } = await db.query(
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
        console.log(`Sending SMS for outbox id=${r.id} to=${r.to_number}...`);
        const refId = await sendViaTelesign(r.to_number, r.message);
        await db.query(
          `UPDATE public.sms_outbox
              SET status='sent',
                  provider_message_id=$1,
                  attempts=attempts+1,
                  sent_at=now(),
                  updated_at=now()
            WHERE id=$2`,
          [refId, r.id]
        );
        console.log(`Sent outbox id=${r.id} ref=${refId}`);
      } catch (e) {
        await db.query(
          `UPDATE public.sms_outbox
              SET status='failed',
                  error=$1,
                  attempts=attempts+1,
                  updated_at=now()
            WHERE id=$2`,
          [String(e), r.id]
        );
        console.warn(`Failed outbox id=${r.id}: ${String(e)}`);
      }
    }

    await db.query("COMMIT");
  } catch (e) {
    await db.query("ROLLBACK");
    throw e;
  } finally {
    await db.end();
  }
}

runOnce().catch((e) => {
  console.error(e);
  process.exit(1);
});
