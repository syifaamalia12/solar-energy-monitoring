
const SCOPES =
  "https://www.googleapis.com/auth/firebase.database " +
  "https://www.googleapis.com/auth/userinfo.email";

const ZONE = "Asia/Jakarta";
const ROOT = "sensor_readings";

let cachedToken = null;
let tokenExpiresAt = 0;

function json(data, status = 200) {
  return Response.json(data, {
    status,
    headers: { "Cache-Control": "no-store" }
  });
}

function base64url(value) {
  const bytes = typeof value === "string"
    ? new TextEncoder().encode(value)
    : new Uint8Array(value);

  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);

  return btoa(binary)
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
}

async function getFirebaseAccessToken(env) {
  if (cachedToken && Date.now() < tokenExpiresAt) {
    return cachedToken;
  }

  const now = Math.floor(Date.now() / 1000);
  const header = base64url(JSON.stringify({
    alg: "RS256",
    typ: "JWT"
  }));

  const payload = base64url(JSON.stringify({
    iss: env.FIREBASE_CLIENT_EMAIL,
    scope: SCOPES,
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600
  }));

  const input = `${header}.${payload}`;

  const pem = env.FIREBASE_PRIVATE_KEY
    .replace(/\\n/g, "\n")
    .replace(
      /-----BEGIN PRIVATE KEY-----|-----END PRIVATE KEY-----|\s/g,
      ""
    );

  const bytes = Uint8Array.from(
    atob(pem),
    c => c.charCodeAt(0)
  );

  const key = await crypto.subtle.importKey(
    "pkcs8",
    bytes,
    {
      name: "RSASSA-PKCS1-v1_5",
      hash: "SHA-256"
    },
    false,
    ["sign"]
  );

  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(input)
  );

  const assertion = `${input}.${base64url(signature)}`;

  const response = await fetch(
    "https://oauth2.googleapis.com/token",
    {
      method: "POST",
      headers: {
        "Content-Type": "application/x-www-form-urlencoded"
      },
      body: new URLSearchParams({
        grant_type:
          "urn:ietf:params:oauth:grant-type:jwt-bearer",
        assertion
      })
    }
  );

  if (!response.ok) {
    throw new Error(`Firebase OAuth failed: ${response.status}`);
  }

  const result = await response.json();

  if (!result.access_token) {
    throw new Error("Missing Firebase access token");
  }

  cachedToken = result.access_token;
  tokenExpiresAt =
    Date.now() +
    Math.max(60, Number(result.expires_in || 3600) - 120) * 1000;

  return cachedToken;
}

async function firebase(env, path, options = {}) {
  const base = env.FIREBASE_DATABASE_URL.replace(/\/+$/, "");
  const token = await getFirebaseAccessToken(env);

  return fetch(`${base}/${path}.json`, {
    ...options,
    headers: {
      Authorization: `Bearer ${token}`,
      ...(options.headers || {})
    }
  });
}

function validId(value) {
  return typeof value === "string" &&
    /^[A-Za-z0-9_-]{1,120}$/.test(value);
}

function validDate(value) {
  if (
    typeof value !== "string" ||
    !/^\d{4}-\d{2}-\d{2}$/.test(value)
  ) return false;

  const date = new Date(`${value}T00:00:00Z`);

  return !Number.isNaN(date.getTime()) &&
    date.toISOString().slice(0, 10) === value;
}

function dayJakarta(timestamp) {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: ZONE,
    year: "numeric",
    month: "2-digit",
    day: "2-digit"
  }).formatToParts(new Date(timestamp));

  const get = type =>
    parts.find(part => part.type === type).value;

  return `${get("year")}-${get("month")}-${get("day")}`;
}

function dateRange(days) {
  const today = dayJakarta(new Date().toISOString());

  const result = [];

  for (let i = days - 1; i >= 0; i--) {
    const date = new Date(`${today}T00:00:00Z`);
    date.setUTCDate(date.getUTCDate() - i);
    result.push(date.toISOString().slice(0, 10));
  }

  return result;
}

function round(value, decimals = 9) {
  return Number(value.toFixed(decimals));
}

async function readDay(env, deviceId, date) {
  const response = await firebase(
    env,
    `${ROOT}/${deviceId}/${date}`
  );

  if (!response.ok) {
    throw new Error(`Firebase read failed: ${response.status}`);
  }

  const data = await response.json();

  return Object.values(data || {}).filter(row =>
    row &&
    row.device_id === deviceId &&
    typeof row.timestamp === "string" &&
    Number.isFinite(Date.parse(row.timestamp)) &&
    Number.isFinite(row.power_w) &&
    Number.isFinite(row.energy_wh)
  );
}

async function readDays(env, deviceId, dates) {
  // Baca per kelompok agar permintaan tidak berlebihan.
  const rows = [];

  for (let i = 0; i < dates.length; i += 5) {
    const batch = dates.slice(i, i + 5);

    const results = await Promise.all(
      batch.map(date => readDay(env, deviceId, date))
    );

    for (const result of results) rows.push(...result);
  }

  return rows.sort(
    (a, b) => Date.parse(a.timestamp) - Date.parse(b.timestamp)
  );
}

function summarizeDaily(rows) {
  const grouped = new Map();

  for (const row of rows) {
    const date = dayJakarta(row.timestamp);

    const item = grouped.get(date) || {
      date,
      total_energy_wh: 0,
      reading_count: 0,
      sum_power_w: 0,
      max_power_w: 0
    };

    item.total_energy_wh += row.energy_wh;
    item.sum_power_w += row.power_w;
    item.max_power_w = Math.max(item.max_power_w, row.power_w);
    item.reading_count++;

    grouped.set(date, item);
  }

  return [...grouped.values()]
    .map(({ sum_power_w, ...item }) => ({
      ...item,
      total_energy_wh: round(item.total_energy_wh),
      avg_power_w: round(sum_power_w / item.reading_count),
      max_power_w: round(item.max_power_w)
    }))
    .sort((a, b) => a.date.localeCompare(b.date));
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const path = url.pathname.replace(/\/+$/, "") || "/";

    if (path === "/health" && request.method === "GET") {
      return json({
        status: "ok",
        message:
          "Solar Energy Monitoring API berjalan di Cloudflare Workers"
      });
    }

    const endpoints = [
      "/api/v1/monitoring",
      "/api/v1/monitoring/latest",
      "/api/v1/monitoring/history",
      "/api/v1/monitoring/daily-summary",
      "/api/v1/monitoring/daily-history",
      "/api/v1/ai/dataset"
    ];

    if (!endpoints.includes(path)) {
      return json({ detail: "Not Found" }, 404);
    }

    const expectedMethod =
      path === "/api/v1/monitoring" ? "POST" : "GET";

    if (request.method !== expectedMethod) {
      return json({ detail: "Method Not Allowed" }, 405);
    }

    if (
      !env.IOT_API_KEY ||
      request.headers.get("x-api-key") !== env.IOT_API_KEY
    ) {
      return json({ detail: "Unauthorized" }, 401);
    }

    try {
      // POST: menyimpan pembacaan sensor
      if (path === "/api/v1/monitoring") {
        let data;

        try {
          data = await request.json();
        } catch {
          return json({ detail: "Invalid JSON" }, 400);
        }

        const {
          reading_id,
          device_id,
          timestamp,
          voltage_v,
          current_a,
          interval_seconds
        } = data || {};

        if (
          !validId(reading_id) ||
          !validId(device_id) ||
          typeof timestamp !== "string" ||
          !/(Z|[+-]\d{2}:\d{2})$/.test(timestamp) ||
          !Number.isFinite(Date.parse(timestamp)) ||
          !Number.isFinite(voltage_v) ||
          voltage_v < 0 ||
          !Number.isFinite(current_a) ||
          current_a < 0 ||
          !Number.isInteger(interval_seconds) ||
          interval_seconds < 1 ||
          interval_seconds > 3600
        ) {
          return json({ detail: "Invalid monitoring data" }, 422);
        }

        const power_w = voltage_v * current_a;
        const energy_wh = power_w * interval_seconds / 3600;

        const date = dayJakarta(timestamp);
        const document_id = `${device_id}_${reading_id}`;

        const response = await firebase(
          env,
          `${ROOT}/${device_id}/${date}/${document_id}`,
          {
            method: "PUT",
            headers: {
              "Content-Type": "application/json",
              "if-match": "null_etag"
            },
            body: JSON.stringify({
              reading_id,
              device_id,
              timestamp,
              voltage_v,
              current_a,
              power_w,
              energy_wh,
              interval_seconds
            })
          }
        );

        if (response.status === 412) {
          return json(
            { detail: "Reading already exists" },
            409
          );
        }

        if (!response.ok) {
          console.error("Firebase write:", response.status);
          return json({ detail: "Firebase write failed" }, 502);
        }

        return json({
          status: "saved",
          document_id,
          power_w,
          energy_wh
        });
      }

      const deviceId =
        url.searchParams.get("device_id") || "solar-001";

      if (!validId(deviceId)) {
        return json({ detail: "Invalid device_id" }, 422);
      }

      // GET: pembacaan terbaru
      if (path === "/api/v1/monitoring/latest") {
        const dates = dateRange(14).reverse();
        let latest = null;

        for (const date of dates) {
          const rows = await readDay(env, deviceId, date);

          if (rows.length) {
            latest = rows.sort(
              (a, b) =>
                Date.parse(a.timestamp) - Date.parse(b.timestamp)
            ).at(-1);

            break;
          }
        }

        return json({
          device_id: deviceId,
          data: latest
        });
      }

      // GET: riwayat sensor
      if (path === "/api/v1/monitoring/history") {
        const limit = Number(
          url.searchParams.get("limit") || 100
        );

        if (
          !Number.isInteger(limit) ||
          limit < 1 ||
          limit > 1000
        ) {
          return json(
            { detail: "limit must be 1..1000" },
            422
          );
        }

        const rows = await readDays(
          env,
          deviceId,
          dateRange(14)
        );

        const data = rows.slice(-limit).reverse();

        return json({
          device_id: deviceId,
          count: data.length,
          data
        });
      }

      // GET: rekap satu tanggal
      if (path === "/api/v1/monitoring/daily-summary") {
        const date =
          url.searchParams.get("date") ||
          dayJakarta(new Date().toISOString());

        if (!validDate(date)) {
          return json(
            { detail: "Invalid date; use YYYY-MM-DD" },
            422
          );
        }

        const rows = await readDay(env, deviceId, date);
        const summary = summarizeDaily(rows)[0] || {
          date,
          total_energy_wh: 0,
          reading_count: 0,
          avg_power_w: 0,
          max_power_w: 0
        };

        return json({
          device_id: deviceId,
          timezone: ZONE,
          data: summary
        });
      }

      // GET: riwayat energi / dataset AI
      const days = Number(
        url.searchParams.get("days") ||
        (path === "/api/v1/ai/dataset" ? 14 : 30)
      );

      if (
        !Number.isInteger(days) ||
        days < 1 ||
        days > 30
      ) {
        return json(
          { detail: "days must be 1..30" },
          422
        );
      }

      const rows = await readDays(
        env,
        deviceId,
        dateRange(days)
      );

      const dailyData = summarizeDaily(rows);

      if (path === "/api/v1/ai/dataset") {
        return json({
          device_id: deviceId,
          timezone: ZONE,
          target: "next_day_energy_wh",
          count: dailyData.length,
          data: dailyData.map(item => ({
            date: item.date,
            energy_wh: item.total_energy_wh,
            reading_count: item.reading_count
          }))
        });
      }

      return json({
        device_id: deviceId,
        timezone: ZONE,
        count: dailyData.length,
        data: dailyData
      });

    } catch (error) {
      console.error("API error:", error?.message || String(error));

      return json(
        { detail: "Internal server error" },
        500
      );
    }
  }
};
