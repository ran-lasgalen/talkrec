alter table record_station
      add column state text,
      add column state_at timestamp with time zone,
      add column version text,
      add column time_diff interval;
