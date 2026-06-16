create table public.sensor_readings (
  id bigint generated always as identity not null,
  member_name text not null,
  room_location text not null,
  temperature numeric not null,
  humidity numeric not null,
  remark text not null,
  recorded_at timestamp with time zone null default now(),
  constraint sensor_readings_pkey primary key (id)
) TABLESPACE pg_default;