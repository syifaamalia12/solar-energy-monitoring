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

export async function sensorSnapshot(env, deviceId, start, end) {
  const row = await db(env).prepare(`SELECT COALESCE(MAX(rowid), 0) AS max_rowid
    FROM sensor_readings WHERE device_id = ? AND reading_date BETWEEN ? AND ?`)
    .bind(deviceId, start, end).first();
  return row.max_rowid;
}

export async function readSensorPage(env, deviceId, start, end, limit, offset, maxRowid) {
  return (await db(env).prepare(`SELECT reading_id, device_id, timestamp, voltage_v,
    current_a, power_w, energy_wh, interval_seconds FROM sensor_readings
    WHERE device_id = ? AND reading_date BETWEEN ? AND ? AND rowid <= ?
    ORDER BY timestamp_ms DESC, reading_date DESC, document_id DESC LIMIT ? OFFSET ?`)
    .bind(deviceId, start, end, maxRowid, limit, offset).all()).results;
}

const aggregateColumns = `ROUND(COALESCE(SUM(energy_wh), 0), 9) AS total_energy_wh,
  COUNT(*) AS reading_count,
  ROUND(COALESCE(AVG(voltage_v), 0), 9) AS avg_voltage_v,
  ROUND(COALESCE(AVG(current_a), 0), 9) AS avg_current_a,
  ROUND(COALESCE(AVG(power_w), 0), 9) AS avg_power_w,
  ROUND(COALESCE(MAX(power_w), 0), 9) AS max_power_w`;

export async function readPeriodSummary(env, deviceId, start, end) {
  return db(env).prepare(`SELECT ${aggregateColumns} FROM sensor_readings
    WHERE device_id = ? AND reading_date BETWEEN ? AND ?`).bind(deviceId, start, end).first();
}

export async function readDailySummaries(env, deviceId, start, end) {
  return (await db(env).prepare(`SELECT reading_date AS date, ${aggregateColumns}
    FROM sensor_readings WHERE device_id = ? AND reading_date BETWEEN ? AND ?
    GROUP BY reading_date ORDER BY reading_date`).bind(deviceId, start, end).all()).results;
}

export async function readHourlySummaries(env, deviceId, date) {
  return (await db(env).prepare(`SELECT
    CAST(strftime('%H', timestamp_ms / 1000.0, 'unixepoch', '+7 hours') AS INTEGER) AS hour,
    ROUND(SUM(energy_wh), 9) AS total_energy_wh, COUNT(*) AS reading_count
    FROM sensor_readings WHERE device_id = ? AND reading_date = ?
    GROUP BY hour ORDER BY hour`).bind(deviceId, date).all()).results;
}
