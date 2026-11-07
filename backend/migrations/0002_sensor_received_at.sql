-- Old measurements have no known server receipt time. Do not infer it from ESP timestamps.
ALTER TABLE sensor_readings ADD COLUMN received_at TEXT;
CREATE INDEX sensor_device_received_at ON sensor_readings(device_id, received_at DESC)
  WHERE received_at IS NOT NULL;
