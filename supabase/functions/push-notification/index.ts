import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const FIREBASE_MESSAGING_SCOPE = "https://www.googleapis.com/auth/firebase.messaging";

// ==========================================
// JWT / OAuth2 helpers (no external library)
// ==========================================
function base64url(data: Uint8Array): string {
  let s = "";
  for (const b of data) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function createSignedJwt(email: string, key: string, scope: string): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: "RS256", typ: "JWT" };
  const payload = {
    iss: email,
    scope: scope,
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  };

  const enc = new TextEncoder();
  const headerB64 = base64url(enc.encode(JSON.stringify(header)));
  const payloadB64 = base64url(enc.encode(JSON.stringify(payload)));
  const unsignedToken = `${headerB64}.${payloadB64}`;

  // Import the private key
  const pemBody = key
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s/g, "");
  const binaryKey = Uint8Array.from(atob(pemBody), (c) => c.charCodeAt(0));

  const cryptoKey = await crypto.subtle.importKey(
    "pkcs8",
    binaryKey,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"]
  );

  const signature = new Uint8Array(
    await crypto.subtle.sign("RSASSA-PKCS1-v1_5", cryptoKey, enc.encode(unsignedToken))
  );

  return `${unsignedToken}.${base64url(signature)}`;
}

async function getAccessToken(email: string, key: string): Promise<string> {
  const jwt = await createSignedJwt(email, key, FIREBASE_MESSAGING_SCOPE);
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: `grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=${jwt}`,
  });
  const data = await res.json();
  if (!data.access_token) {
    console.error("Failed to get access token:", JSON.stringify(data));
    throw new Error("Could not obtain access token");
  }
  return data.access_token as string;
}

// ==========================================
// Main handler
// ==========================================
const jsonResponse = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });

Deno.serve(async (req: Request) => {
  try {
    // Optional shared secret: set WEBHOOK_SECRET in the function secrets and
    // send the same value in the `x-webhook-secret` header of the DB webhook.
    const webhookSecret = Deno.env.get("WEBHOOK_SECRET");
    if (webhookSecret && req.headers.get("x-webhook-secret") !== webhookSecret) {
      return jsonResponse({ error: "unauthorized" }, 401);
    }

    const payload = await req.json();

    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

    // The webhook sends { type, table, record, ... }. Never trust the payload's
    // title/body: anyone holding the public anon key can call this function.
    // Re-read the notification by id so only rows that really exist get pushed.
    const notificationId = payload?.record?.id;
    if (typeof notificationId !== "string" || !/^[0-9a-f-]{36}$/i.test(notificationId)) {
      return jsonResponse({ status: "skipped", reason: "no notification id" });
    }

    const notifRes = await fetch(
      `${supabaseUrl}/rest/v1/notifications?id=eq.${notificationId}&select=id,employee_id,title,body,type,created_at`,
      { headers: { apikey: supabaseKey, Authorization: `Bearer ${supabaseKey}` } },
    );
    const notifRows = notifRes.ok ? await notifRes.json() : [];
    const record = notifRows[0];
    if (!record || !record.employee_id) {
      return jsonResponse({ status: "skipped", reason: "notification not found" });
    }

    // Replays of old notifications are ignored.
    if (Date.now() - new Date(record.created_at).getTime() > 10 * 60 * 1000) {
      return jsonResponse({ status: "skipped", reason: "stale notification" });
    }
    console.log(`Pushing notification ${record.id} to employee ${record.employee_id}`);

    const tokens: string[] = [];

    // 1. Get employee FCM token from employees table (column fcm_token)
    try {
      const empRes = await fetch(
        `${supabaseUrl}/rest/v1/employees?id=eq.${record.employee_id}&select=fcm_token`,
        {
          headers: {
            apikey: supabaseKey,
            Authorization: `Bearer ${supabaseKey}`,
          },
        }
      );
      if (empRes.ok) {
        const empData = await empRes.json();
        if (empData && empData.length > 0 && empData[0].fcm_token) {
          const t = empData[0].fcm_token.trim();
          if (t && !tokens.includes(t)) {
            tokens.push(t);
          }
        }
      } else {
        console.error("Failed to query employees table:", empRes.status, await empRes.text());
      }
    } catch (err) {
      console.error("Error fetching fcm_token from employees table:", err);
    }

    // 2. Get tokens from fcm_tokens table
    try {
      const tokensRes = await fetch(
        `${supabaseUrl}/rest/v1/fcm_tokens?employee_id=eq.${record.employee_id}&select=token`,
        {
          headers: {
            apikey: supabaseKey,
            Authorization: `Bearer ${supabaseKey}`,
          },
        }
      );
      if (tokensRes.ok) {
        const tokensData = await tokensRes.json();
        if (tokensData && tokensData.length > 0) {
          for (const item of tokensData) {
            if (item.token) {
              const t = item.token.trim();
              if (t && !tokens.includes(t)) {
                tokens.push(t);
              }
            }
          }
        }
      } else {
        console.error("Failed to query fcm_tokens table:", tokensRes.status, await tokensRes.text());
      }
    } catch (err) {
      console.error("Error fetching tokens from fcm_tokens table:", err);
    }

    console.log(`FCM Tokens found for employee ${record.employee_id}:`, tokens.length);

    if (tokens.length === 0) {
      console.log("No FCM tokens found for employee:", record.employee_id);
      return new Response(
        JSON.stringify({ status: "skipped", reason: "no fcm_token" }),
        { headers: { "Content-Type": "application/json" } }
      );
    }

    // 3. Get Firebase credentials
    const serviceAccountStr = Deno.env.get("FIREBASE_SERVICE_ACCOUNT");
    if (!serviceAccountStr) {
      throw new Error("FIREBASE_SERVICE_ACCOUNT secret is missing");
    }
    const serviceAccount = JSON.parse(serviceAccountStr);

    // 4. Get OAuth2 access token using the service account
    const accessToken = await getAccessToken(
      serviceAccount.client_email,
      serviceAccount.private_key
    );
    console.log("Got Firebase access token successfully");

    // 5. Build FCM message - use 'body' column
    const notificationTitle = record.title || "إشعار جديد";
    const notificationBody = record.body || "لديك إشعار جديد في HR Pro";

    const results = await Promise.allSettled(
      tokens.map(async (fcmToken) => {
        const fcmPayload = {
          message: {
            token: fcmToken,
            notification: {
              title: notificationTitle,
              body: notificationBody,
            },
            android: {
              priority: "HIGH", // Case-sensitive uppercase HIGH is required!
              notification: {
                channel_id: "hr_pro_channel_v6", // Target the new channel ID
                sound: "special_chime", // Android custom sound
                default_vibrate_timings: true,
                default_light_settings: true,
                notification_priority: "PRIORITY_MAX",
                visibility: "PUBLIC",
              },
            },
            apns: {
              payload: {
                aps: {
                  alert: {
                    title: notificationTitle,
                    body: notificationBody,
                  },
                  sound: "special_chime.wav", // iOS default sound
                  badge: 1,
                  "content-available": 1,
                  "mutable-content": 1,
                },
              },
              headers: {
                "apns-priority": "10",
                "apns-push-type": "alert",
              },
            },
            data: {
              type: record.type || "general",
              notification_id: record.id || "",
              employee_id: record.employee_id || "",
              click_action: "FLUTTER_NOTIFICATION_CLICK",
            },
          },
        };

        const fcmRes = await fetch(
          `https://fcm.googleapis.com/v1/projects/${serviceAccount.project_id}/messages:send`,
          {
            method: "POST",
            headers: {
              "Content-Type": "application/json",
              Authorization: `Bearer ${accessToken}`,
            },
            body: JSON.stringify(fcmPayload),
          }
        );

        const fcmResult = await fcmRes.json();
        console.log(`FCM Send result for token ${fcmToken.substring(0, 15)}...:`, fcmRes.status, JSON.stringify(fcmResult));
        return { status: fcmRes.status, result: fcmResult };
      })
    );

    // Tokens Firebase no longer recognises (app uninstalled/reinstalled, old
    // builds) are removed so later pushes don't keep fanning out to them.
    const deadTokens = tokens.filter((_, i) => {
      const r = results[i];
      if (r.status !== "fulfilled") return false;
      const code = r.value.result?.error?.details?.find?.((d: { errorCode?: string }) => d.errorCode)?.errorCode;
      return r.value.status === 404 || code === "UNREGISTERED";
    });
    if (deadTokens.length > 0) {
      const inList = deadTokens.map((t) => `"${t.replace(/"/g, "")}"`).join(",");
      const headers = { apikey: supabaseKey, Authorization: `Bearer ${supabaseKey}`, "Content-Type": "application/json" };
      await Promise.allSettled([
        fetch(`${supabaseUrl}/rest/v1/fcm_tokens?token=in.(${encodeURIComponent(inList)})`, { method: "DELETE", headers }),
        fetch(`${supabaseUrl}/rest/v1/device_tokens?token=in.(${encodeURIComponent(inList)})`, { method: "DELETE", headers }),
        fetch(`${supabaseUrl}/rest/v1/employees?id=eq.${record.employee_id}&fcm_token=in.(${encodeURIComponent(inList)})`, {
          method: "PATCH",
          headers,
          body: JSON.stringify({ fcm_token: null }),
        }),
      ]);
      console.log(`Removed ${deadTokens.length} unregistered token(s) for employee ${record.employee_id}`);
    }

    const delivered = results.filter((r) => r.status === "fulfilled" && r.value.status === 200).length;
    const successful = results.filter(r => r.status === 'fulfilled').length;
    const failed = results.filter(r => r.status === 'rejected').length;

    return new Response(JSON.stringify({ status: "processed", delivered, removed: deadTokens.length, successful, failed, details: results }), {
      headers: { "Content-Type": "application/json" },
    });
  } catch (error: unknown) {
    const errMsg = error instanceof Error ? error.message : String(error);
    console.error("Error in push-notification function:", errMsg);
    return new Response(JSON.stringify({ error: errMsg }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});
