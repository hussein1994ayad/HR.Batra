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
Deno.serve(async (req: Request) => {
  try {
    const payload = await req.json();
    console.log("Received payload:", JSON.stringify(payload));

    // The webhook sends { type, table, record, ... }
    const record = payload.record;
    if (!record || !record.employee_id) {
      console.log("No employee_id in record, skipping.");
      return new Response(JSON.stringify({ status: "skipped", reason: "no employee_id" }), {
        headers: { "Content-Type": "application/json" },
      });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

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
                channel_id: "hr_pro_channel_v4", // Target the new channel ID
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
                  sound: "default", // iOS default sound
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

    const successful = results.filter(r => r.status === 'fulfilled').length;
    const failed = results.filter(r => r.status === 'rejected').length;

    return new Response(JSON.stringify({ status: "processed", successful, failed, details: results }), {
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
