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