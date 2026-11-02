-- Synced preferences (one record: when the planner day starts). Widens the key check only.
alter table public.orbit_records drop constraint orbit_records_key_check;
alter table public.orbit_records add constraint orbit_records_key_check
  check (key ~ '^(tasks|habits|habit_logs|lists|idea_prompts|preferences)/[a-z0-9-]{1,100}$');
