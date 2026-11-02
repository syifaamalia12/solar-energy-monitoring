// D1 binding only: no database credentials or direct client database endpoint.
function db(env) {
  if (!env.DB?.prepare) throw new Error("D1 binding unavailable");
  return env.DB;
}
export async function readSensorDay(env, deviceId, date) {
  const result = await db(env).prepare(`SELECT reading_id, device_id, timestamp, voltage_v,
    current_a, power_w, energy_wh, interval_seconds FROM sensor_readings
    WHERE device_id = ? AND reading_date = ? ORDER BY timestamp_ms`).bind(deviceId, date).all();
  return result.results;
}
export async function insertSensor(env, row, date, documentId) {
  const result = await db(env).prepare(`INSERT INTO sensor_readings
    (device_id, reading_date, document_id, reading_id, timestamp, timestamp_ms,
     voltage_v, current_a, power_w, energy_wh, interval_seconds)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(device_id, reading_date, document_id) DO NOTHING`).bind(
    row.device_id, date, documentId, row.reading_id, row.timestamp, Date.parse(row.timestamp),
    row.voltage_v, row.current_a, row.power_w, row.energy_wh, row.interval_seconds).run();
  return result.meta.changes > 0;
}
export async function findDevice(env, deviceId) {
  return db(env).prepare("SELECT device_id FROM devices WHERE device_id = ?").bind(deviceId).first();
}
export async function insertPrediction(env, row) {
  const result = await db(env).prepare(`INSERT INTO energy_predictions
    (device_id, prediction_date, predicted_energy_wh, model_name, created_at)
    VALUES (?, ?, ?, ?, ?) ON CONFLICT(device_id, prediction_date) DO NOTHING`).bind(
    row.device_id, row.prediction_date, row.predicted_energy_wh, row.model_name, row.created_at).run();
  return result.meta.changes > 0;
}
export async function readPredictions(env, deviceId, start, end) {
  const columns = "device_id, prediction_date, predicted_energy_wh, model_name, created_at";
  const statement = start === undefined
    ? db(env).prepare(`SELECT ${columns} FROM energy_predictions WHERE device_id = ? ORDER BY prediction_date DESC LIMIT 1`).bind(deviceId)
    : db(env).prepare(`SELECT ${columns} FROM energy_predictions WHERE device_id = ? AND prediction_date >= ? AND prediction_date <= ? ORDER BY prediction_date`).bind(deviceId, start, end);
  return (await statement.all()).results;
}
