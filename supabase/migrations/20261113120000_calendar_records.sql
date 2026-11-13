-- Calendars shared from the iPhone: one record per calendar and one per event occurrence. Widens the
-- key check only; writes still go through orbit_put.
alter table public.orbit_records drop constraint orbit_records_key_check;
alter table public.orbit_records add constraint orbit_records_key_check
  check (key ~ '^(tasks|habits|habit_logs|lists|idea_prompts|preferences|calendars|events)/[a-z0-9-]{1,100}$');
