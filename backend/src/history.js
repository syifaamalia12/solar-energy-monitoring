import { ApiError, errorResponse } from "./api.js";
import { validDate } from "./predictions.js";
import { sensorSnapshot, readSensorPage, readPeriodSummary, readDailySummaries, readHourlySummaries } from "./database.js";

const timezone = "Asia/Jakarta";
function fail(status, detail) { throw new ApiError(status, "INVALID_HISTORY_PARAMETER", detail); }
function json(body) { return Response.json(body, { headers: { "Cache-Control": "no-store" } }); }
function dateValue(value) {
  if (!validDate(value)) fail(422, "Tanggal harus valid dalam format YYYY-MM-DD");
  return value;
}
function integer(params, key, fallback, min, max) {
  const value = params.get(key);
  if (value === null) return fallback;
  if (!/^\d+$/.test(value) || !Number.isSafeInteger(Number(value)) || Number(value) < min || Number(value) > max) {
    fail(422, `${key} harus bilangan bulat ${min}..${max}`);
  }
  return Number(value);
}
function range(params) {
  const start = dateValue(params.get("start_date"));
  const end = dateValue(params.get("end_date"));
  if (start > end) fail(400, "start_date tidak boleh melebihi end_date");
  if ((Date.parse(end) - Date.parse(start)) / 86400000 > 365) fail(400, "Rentang maksimal 366 hari inklusif");
  return [start, end];
}
function shift(date, days) {
  const value = new Date(`${date}T00:00:00Z`);
  value.setUTCDate(value.getUTCDate() + days);
  return value.toISOString().slice(0, 10);
}
function daily(row) {
  return { date: row.date, total_energy_wh: row.total_energy_wh, reading_count: row.reading_count,
    max_power_w: row.max_power_w, avg_power_w: row.avg_power_w };
}

function encodeSnapshot(value) {
  return btoa(JSON.stringify(value)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}
function decodeSnapshot(token, deviceId, date) {
  let value;
  try {
    if (token.length > 1024 || !/^[A-Za-z0-9_-]+$/.test(token)) throw new Error();
    value = JSON.parse(atob(token.replace(/-/g, "+").replace(/_/g, "/")));
  } catch { fail(422, "Snapshot pagination tidak valid"); }
  // This token is a query boundary, not an authentication credential. Device authorization
  // is always performed independently by index.js before reaching this handler.
  if (!value || value.device_id !== deviceId || value.date !== date ||
      !validDate(value.start) || !validDate(value.end) || value.start > value.end ||
      !Number.isSafeInteger(value.max_rowid) || value.max_rowid < 0 ||
      (date ? value.start !== date || value.end !== date :
        (Date.parse(value.end) - Date.parse(value.start)) / 86400000 !== 13)) {
    fail(422, "Snapshot tidak sesuai dengan perangkat atau filter tanggal");
  }
  return value;
}

// Called only after public-device authorization in index.js.
export async function handleHistory(env, deviceId, path, params, today) {
  try {
    if (path.endsWith("/history")) {
      const limit = integer(params, "limit", 100, 1, 1000);
      const offset = integer(params, "offset", 0, 0, 1000000);
      const date = params.has("date") ? dateValue(params.get("date")) : null;
      let snapshot;
      if (params.has("snapshot")) {
        snapshot = decodeSnapshot(params.get("snapshot"), deviceId, date);
      } else {
        const start = date || shift(today, -13);
        const end = date || today;
        snapshot = { device_id: deviceId, date, start, end, max_rowid: await sensorSnapshot(env, deviceId, start, end) };
      }
      const rows = await readSensorPage(env, deviceId, snapshot.start, snapshot.end, limit + 1, offset, snapshot.max_rowid);
      const data = rows.slice(0, limit);
      const body = { device_id: deviceId, count: data.length, data };
      if (params.has("date") || params.has("offset") || params.has("snapshot")) {
        Object.assign(body, { ...(date ? { date } : {}), limit, offset, has_more: rows.length > limit,
          next_offset: rows.length > limit ? offset + limit : null, snapshot: encodeSnapshot(snapshot) });
      }
      return json(body);
    }
    if (path.endsWith("/daily-summary")) {
      const date = params.has("date") ? dateValue(params.get("date")) : today;
      const row = await readPeriodSummary(env, deviceId, date, date);
      return json({ device_id: deviceId, timezone, data: { date, ...row } });
    }
    if (path.endsWith("/hourly-summary")) {
      const date = dateValue(params.get("date"));
      const rows = await readHourlySummaries(env, deviceId, date);
      const byHour = new Map(rows.map(row => [row.hour, row]));
      const data = Array.from({ length: 24 }, (_, hour) => ({ hour,
        total_energy_wh: byHour.get(hour)?.total_energy_wh ?? 0,
        reading_count: byHour.get(hour)?.reading_count ?? 0 }));
      return json({ device_id: deviceId, date, timezone, count: 24, data });
    }
    if (path.endsWith("/period-summary")) {
      const [start, end] = range(params);
      const { max_power_w, ...data } = await readPeriodSummary(env, deviceId, start, end);
      return json({ device_id: deviceId, start_date: start, end_date: end, timezone, data });
    }
    const explicitRange = params.has("start_date") || params.has("end_date");
    // Explicit dates take precedence over the legacy days parameter.
    const [start, end] = explicitRange ? range(params) : [shift(today, 1 - integer(params, "days", 30, 1, 30)), today];
    const rows = await readDailySummaries(env, deviceId, start, end);
    let data = rows.map(daily);
    if (explicitRange) {
      const byDate = new Map(data.map(row => [row.date, row]));
      data = [];
      for (let date = start; date <= end; date = shift(date, 1)) {
        data.push(byDate.get(date) || { date, total_energy_wh: 0, reading_count: 0, max_power_w: 0, avg_power_w: 0 });
        if (date === end) break;
      }
    }
    return json({ device_id: deviceId, timezone, ...(explicitRange ? { start_date: start, end_date: end } : {}), count: data.length, data });
  } catch (error) { return errorResponse(error); }
}
