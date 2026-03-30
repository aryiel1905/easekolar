async function sendViaResend(to, subject, message) {
  const { RESEND_API_KEY, EMAIL_FROM } = process.env;
  if (!RESEND_API_KEY || !EMAIL_FROM) {
    throw new Error("Email credentials not configured (RESEND_API_KEY / EMAIL_FROM).");
  }

  const resp = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${RESEND_API_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from: EMAIL_FROM,
      to: [to],
      subject,
      text: message,
    }),
  });

  const json = await resp.json().catch(() => ({}));
  if (!resp.ok) {
    const reason = json?.message || json?.error || resp.statusText;
    throw new Error(`Resend error ${resp.status}: ${reason}`);
  }
  return json?.id || null;
}

export default async function handler(req, res) {
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Methods", "POST,OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type");
  if (req.method === "OPTIONS") return res.status(204).end();

  if (req.method !== "POST") return res.status(405).json({ error: "POST only" });

  try {
    const { to, subject, message } = req.body || {};
    const toEmail = String(to || "").trim();
    const msg = String(message || "").trim();
    const subj = String(subject || "Scholarship Application Update").trim();

    if (!toEmail || !msg) {
      return res.status(400).json({ error: "to and message required" });
    }

    const emailId = await sendViaResend(toEmail, subj, msg);
    return res.status(200).json({ ok: true, email_id: emailId });
  } catch (err) {
    console.error(err);
    return res.status(502).json({ error: String(err) });
  }
}

