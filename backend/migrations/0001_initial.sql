CREATE TABLE devices (
  device_id TEXT PRIMARY KEY,
  device_name TEXT NOT NULL DEFAULT '',
  location TEXT NOT NULL DEFAULT '',
  install_date TEXT
);

-- Keep the former per-device/per-WIB-day duplicate scope.
CREATE TABLE sensor_readings (
  device_id TEXT NOT NULL,
  reading_date TEXT NOT NULL,
  document_id TEXT NOT NULL,
  reading_id TEXT NOT NULL,
  timestamp TEXT NOT NULL,
  timestamp_ms INTEGER NOT NULL,
  voltage_v REAL NOT NULL CHECK(voltage_v >= 0),
  current_a REAL NOT NULL CHECK(current_a >= 0),
  power_w REAL NOT NULL CHECK(power_w >= 0),
  energy_wh REAL NOT NULL CHECK(energy_wh >= 0),
  interval_seconds INTEGER NOT NULL CHECK(interval_seconds BETWEEN 1 AND 3600),
  PRIMARY KEY(device_id, reading_date, document_id)
);
CREATE INDEX sensor_device_date_time ON sensor_readings(device_id, reading_date, timestamp_ms);

CREATE TABLE energy_predictions (
  device_id TEXT NOT NULL REFERENCES devices(device_id),
  prediction_date TEXT NOT NULL,
  predicted_energy_wh REAL NOT NULL CHECK(predicted_energy_wh >= 0),
  model_name TEXT NOT NULL,
  created_at TEXT NOT NULL,
  PRIMARY KEY(device_id, prediction_date)
);
