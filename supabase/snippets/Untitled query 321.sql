DROP TABLE IF EXISTS sensor_readings;

CREATE TABLE sensor_readings (
  id BIGINT PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
  member_name TEXT NOT NULL,
  room_location TEXT NOT NULL,
  temperature NUMERIC NOT NULL,
  humidity NUMERIC NOT NULL,
  remark TEXT NOT NULL, -- Changed from readable_summary to remark to follow requirements exactly
  recorded_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE sensor_readings DISABLE ROW LEVEL SECURITY;

-- System settings table for syncing configurations across devices
DROP TABLE IF EXISTS system_settings;

CREATE TABLE system_settings (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  updated_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE system_settings DISABLE ROW LEVEL SECURITY;
GRANT ALL ON system_settings TO anon, authenticated, service_role;

-- Seed default settings keys (Optional/Reference)
INSERT INTO system_settings (key, value) VALUES
  ('r1RoomName', 'Living Room'),
  ('r2RoomName', 'Bedroom'),
  ('r3RoomName', 'Kitchen'),
  ('r1RenameTime', ''),
  ('r2RenameTime', ''),
  ('r3RenameTime', '')
ON CONFLICT (key) DO NOTHING;