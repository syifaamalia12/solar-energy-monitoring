import { AuthError, authErrorResponse, readJsonRequest } from "./auth.js";
import { requireOwnedDevice } from "./device-reference.js";
import { validId, validDate, verifyAI } from "./predictions.js";

function fail(status, code, message) { throw new AuthError(status, code, message); }
function json(body, status = 200) {
  return Response.json(body, { status, headers: { "Cache-Control": "no-store" } });
}
function validEnergy(value) { return typeof value === "number" && Number.isFinite(value) && value >= 0; }
function items(value, status = 422) {
  if (!Array.isArray(value) || !value.length || value.length > 100) {
    fail(status, "INVALID_RECOMMENDATIONS", "Daftar rekomendasi harus berisi 1–100 item");
  }
  const seen = new Set();
  return value.map(item => {
    if (!item || typeof item !== "object" || Array.isArray(item) ||
        Object.keys(item).some(key => !["reference_id", "device_name", "category", "power_w", "estimated_duration_hours"].includes(key)) ||
        !validId(item.reference_id) || typeof item.device_name !== "string" || !item.device_name.trim() || [...item.device_name].length > 100 ||
        typeof item.category !== "string" || !item.category.trim() || [...item.category].length > 50 ||
        !validEnergy(item.power_w) || item.power_w === 0 || !validEnergy(item.estimated_duration_hours)) {
      fail(status, "INVALID_RECOMMENDATION_ITEM", "Item rekomendasi tidak valid");
    }
    if (seen.has(item.reference_id)) fail(status, "DUPLICATE_REFERENCE", "Referensi perangkat tidak boleh berulang");
    seen.add(item.reference_id);
    return { reference_id: item.reference_id, device_name: item.device_name, category: item.category,
      power_w: item.power_w, estimated_duration_hours: item.estimated_duration_hours };
  });
}
async function read(env, firebase, path) {
  const response = await firebase(env, path);
  if (!response.ok) fail(503, "RECOMMENDATION_UNAVAILABLE", "Data rekomendasi sementara tidak tersedia");
  return response.json();
}
function publicRecord(row, deviceId, date) {
  if (!row || Array.isArray(row) || row.device_id !== deviceId || row.prediction_date !== date ||
      !validEnergy(row.predicted_energy_wh) || typeof row.created_at !== "string" || !Number.isFinite(Date.parse(row.created_at))) {
    fail(503, "INVALID_RECOMMENDATION_DATA", "Data rekomendasi memerlukan pemeriksaan administrator");
  }
  return { device_id: deviceId, prediction_date: date, predicted_energy_wh: row.predicted_energy_wh,
    recommendations: items(row.recommendations, 503), created_at: row.created_at };
}

export async function handleRecommendations(request, env, firebase) {
  try {
    if (!["POST", "GET"].includes(request.method)) return json({ detail: "Method Not Allowed" }, 405);
    if (request.method === "GET") {
      const params = new URL(request.url).searchParams;
      const deviceId = params.get("device_id");
      await requireOwnedDevice(request, env, firebase, deviceId);
      const date = params.get("prediction_date");
      if (!validDate(date)) fail(422, "INVALID_DATE", "Gunakan prediction_date berupa YYYY-MM-DD");
      const row = await read(env, firebase, `recommendations/${deviceId}/${date}`);
      if (row === null) fail(404, "RECOMMENDATION_NOT_FOUND", "Rekomendasi energi belum tersedia");
      return json({ status: "success", data: publicRecord(row, deviceId, date) });
    }
    await verifyAI(request, env);
    const data = await readJsonRequest(request);
    if (!data || Array.isArray(data) || typeof data !== "object" ||
        Object.keys(data).some(key => !["device_id", "prediction_date", "predicted_energy_wh", "recommendations"].includes(key)) ||
        !validId(data.device_id) || !validDate(data.prediction_date) ||
        (data.predicted_energy_wh !== undefined && !validEnergy(data.predicted_energy_wh))) {
      fail(422, "INVALID_RECOMMENDATION", "Data rekomendasi tidak valid");
    }
    const recommendations = items(data.recommendations);
    const device = await read(env, firebase, `devices/${data.device_id}`);
    if (!device || typeof device !== "object" || Array.isArray(device)) fail(404, "DEVICE_NOT_FOUND", "Perangkat tidak terdaftar");
    const prediction = await read(env, firebase, `energy_predictions/${data.device_id}/${data.prediction_date}`);
    if (prediction === null) fail(404, "PREDICTION_NOT_FOUND", "Prediksi energi untuk tanggal tersebut belum tersedia");
    if (prediction.device_id !== data.device_id || prediction.prediction_date !== data.prediction_date || !validEnergy(prediction.predicted_energy_wh)) {
      fail(503, "INVALID_PREDICTION_DATA", "Data prediksi memerlukan pemeriksaan administrator");
    }
    if (data.predicted_energy_wh !== undefined && data.predicted_energy_wh !== prediction.predicted_energy_wh) {
      fail(422, "PREDICTION_MISMATCH", "Energi rekomendasi tidak sesuai dengan hasil prediksi tersimpan");
    }
    const references = await read(env, firebase, "device_reference");
    if (!references || typeof references !== "object" || Array.isArray(references)) fail(404, "REFERENCE_NOT_FOUND", "Referensi perangkat belum tersedia");
    for (const item of recommendations) {
      const reference = Object.hasOwn(references, item.reference_id) ? references[item.reference_id] : null;
      if (!reference) fail(404, "REFERENCE_NOT_FOUND", "Referensi perangkat tidak ditemukan");
      if (reference.reference_id !== item.reference_id || reference.device_name !== item.device_name ||
          reference.category !== item.category || reference.power_w !== item.power_w) {
        fail(422, "REFERENCE_MISMATCH", "Item rekomendasi tidak sesuai dengan referensi perangkat");
      }
    }
    // AI supplies durations; backend performs no inference or duration calculation.
    recommendations.sort((a, b) => b.estimated_duration_hours - a.estimated_duration_hours);
    const payload = { device_id: data.device_id, prediction_date: data.prediction_date,
      predicted_energy_wh: prediction.predicted_energy_wh, recommendations, created_at: new Date().toISOString() };
    // Preserve FastAPI's upsert contract: one record per device/date, not appended duplicates.
    const response = await firebase(env, `recommendations/${data.device_id}/${data.prediction_date}`, {
      method: "PUT", headers: { "Content-Type": "application/json" }, body: JSON.stringify(payload)
    });
    if (!response.ok) fail(503, "RECOMMENDATION_UNAVAILABLE", "Gagal menyimpan rekomendasi energi");
    return json({ status: "saved", data: payload }, 201);
  } catch (error) { return authErrorResponse(error); }
}
