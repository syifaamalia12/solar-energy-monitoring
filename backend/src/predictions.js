import { ApiError, errorResponse, readJsonRequest, requirePrototypeDevice } from "./api.js";

function fail(status, code, detail) { throw new ApiError(status, code, detail); }
function json(body, status = 200) {
  return Response.json(body, { status, headers: { "Cache-Control": "no-store" } });
}
export function validId(value) { return typeof value === "string" && /^[A-Za-z0-9_-]{1,120}$/.test(value); }
export function validDate(value) {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(value) || value.startsWith("0000")) return false;
  const date = new Date(`${value}T00:00:00Z`);
  return Number.isFinite(date.getTime()) && date.toISOString().slice(0, 10) === value;
}
export async function verifyAI(request, env) {
  if (typeof env.AI_API_KEY !== "string" || !env.AI_API_KEY || env.AI_API_KEY === env.IOT_API_KEY) {
    fail(503, "AI_AUTH_UNAVAILABLE", "Konfigurasi autentikasi layanan AI belum tersedia");
  }
  const supplied = request.headers.get("x-api-key");
  if (!supplied || supplied.length > 4096) fail(401, "INVALID_AI_KEY", "Kredensial layanan AI tidak valid");
  const digest = async value => new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value)));
  const [actual, expected] = await Promise.all([digest(supplied), digest(env.AI_API_KEY)]);
  let difference = 0;
  for (let i = 0; i < expected.length; i++) difference |= actual[i] ^ expected[i];
  if (difference !== 0) fail(401, "INVALID_AI_KEY", "Kredensial layanan AI tidak valid");
}
function publicPrediction(row, deviceId, date) {
  if (!row || Array.isArray(row) || row.device_id !== deviceId || row.prediction_date !== date ||
      !validDate(date) || typeof row.predicted_energy_wh !== "number" ||
      !Number.isFinite(row.predicted_energy_wh) || row.predicted_energy_wh < 0 ||
      typeof row.model_name !== "string" || !row.model_name.trim() ||
      typeof row.created_at !== "string" || !Number.isFinite(Date.parse(row.created_at))) {
    fail(503, "INVALID_PREDICTION_DATA", "Data prediksi memerlukan pemeriksaan administrator");
  }
  return { device_id: deviceId, prediction_date: date, predicted_energy_wh: row.predicted_energy_wh,
    model_name: row.model_name, created_at: row.created_at };
}

export async function handlePredictions(request, env, path, firebase) {
  try {
    const root = "/api/v1/ai/predictions";
    const create = path === root;
    if (request.method !== (create ? "POST" : "GET")) return json({ detail: "Method Not Allowed" }, 405);
    if (create) {
      await verifyAI(request, env);
      const data = await readJsonRequest(request);
      if (!data || Array.isArray(data) || typeof data !== "object" ||
          Object.keys(data).some(key => !["device_id", "prediction_date", "predicted_energy_wh", "model_name"].includes(key)) ||
          !validId(data.device_id) || !validDate(data.prediction_date) ||
          typeof data.predicted_energy_wh !== "number" || !Number.isFinite(data.predicted_energy_wh) || data.predicted_energy_wh < 0 ||
          (data.model_name !== undefined && (typeof data.model_name !== "string" || !data.model_name.trim() || data.model_name.length > 100))) {
        fail(422, "INVALID_PREDICTION", "Data prediksi tidak valid");
      }
      const deviceResponse = await firebase(env, `devices/${data.device_id}`);
      if (!deviceResponse.ok) fail(503, "DEVICE_UNAVAILABLE", "Data perangkat sementara tidak tersedia");
      const device = await deviceResponse.json();
      if (!device || typeof device !== "object" || Array.isArray(device)) fail(404, "DEVICE_NOT_FOUND", "Perangkat tidak terdaftar");
      // Forecast of next-day actual daily energy in Wh, supplied by the AI division.
      // Dates remain explicit to support delayed jobs/backfills; no panel-capacity calculation.
      const payload = { device_id: data.device_id, prediction_date: data.prediction_date,
        predicted_energy_wh: data.predicted_energy_wh, model_name: data.model_name?.trim() ?? "Linear Regression",
        created_at: new Date().toISOString() };
      const response = await firebase(env, `energy_predictions/${data.device_id}/${data.prediction_date}`, {
        method: "PUT", headers: { "Content-Type": "application/json", "if-match": "null_etag" }, body: JSON.stringify(payload)
      });
      if (response.status === 412) fail(409, "PREDICTION_EXISTS", "Prediksi untuk tanggal ini sudah tersedia");
      if (!response.ok) fail(503, "PREDICTION_UNAVAILABLE", "Gagal menyimpan hasil prediksi");
      return json({ status: "saved", data: payload }, 201);
    }
    const params = new URL(request.url).searchParams;
    const deviceId = params.get("device_id");
    requirePrototypeDevice(deviceId, env);
    const latest = path === `${root}/latest`;
    const start = params.get("start_date");
    const end = params.get("end_date");
    if (!latest) {
      if (!validDate(start) || !validDate(end)) fail(422, "INVALID_DATE", "Gunakan tanggal YYYY-MM-DD yang valid");
      if (start > end) fail(400, "INVALID_DATE_RANGE", "start_date tidak boleh melebihi end_date");
      if ((Date.parse(end) - Date.parse(start)) / 86400000 > 30) fail(400, "INVALID_DATE_RANGE", "Rentang tanggal maksimal 31 hari");
    }
    const query = latest ? { orderBy: JSON.stringify("$key"), limitToLast: "1" } :
      { orderBy: JSON.stringify("$key"), startAt: JSON.stringify(start), endAt: JSON.stringify(end) };
    const response = await firebase(env, `energy_predictions/${deviceId}`, {}, query);
    if (!response.ok) fail(503, "PREDICTION_UNAVAILABLE", "Gagal mengambil hasil prediksi");
    const records = await response.json();
    if (records !== null && (typeof records !== "object" || Array.isArray(records))) {
      fail(503, "INVALID_PREDICTION_DATA", "Data prediksi memerlukan pemeriksaan administrator");
    }
    const data = Object.keys(records || {}).sort().map(date => publicPrediction(records[date], deviceId, date));
    if (latest) {
      if (!data.length) fail(404, "PREDICTION_NOT_FOUND", "Belum ada hasil prediksi");
      return json({ status: "success", data: data.at(-1) });
    }
    return json({ status: "success", device_id: deviceId, start_date: start, end_date: end,
      total_predictions: data.length, data });
  } catch (error) { return errorResponse(error); }
}
