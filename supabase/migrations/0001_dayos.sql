-- Phase 2 schema scaffold. Not connected to the local-only iOS prototype.
begin;

create table public.lists (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null check (length(trim(name)) > 0),
  color text not null default 'sage',
  sort_order integer not null default 0,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (id, user_id)
);

create table public.tasks (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null check (length(trim(title)) > 0),
  notes text not null default '',
  list_id uuid,
  due_date timestamptz,
  local_date date,
  time_zone text not null default 'UTC',
  has_time boolean not null default false,
  duration_minutes integer not null default 30 check (duration_minutes > 0),
  reminders timestamptz[] not null default '{}',
  recurrence_rule text not null default '',
  priority integer not null default 0 check (priority between 0 and 3),
  tags text[] not null default '{}',
  subtasks jsonb not null default '[]' check (jsonb_typeof(subtasks) = 'array'),
  completed_at timestamptz,
  next_occurrence_id uuid,
  sort_order integer not null default 0,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  foreign key (list_id, user_id) references public.lists(id, user_id),
  unique (id, user_id)
);

create table public.habits (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null check (length(trim(title)) > 0),
  frequency_rule text not null default 'DAILY',
  target integer not null default 1 check (target > 0),
  color text not null default 'sage',
  icon text not null default 'leaf',
  reminder_minutes integer check (reminder_minutes between 0 and 1439),
  nudge_minutes integer check (nudge_minutes between 0 and 1439),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (id, user_id)
);

create table public.habit_logs (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  habit_id uuid not null,
  day_key date not null,
  count integer not null default 1 check (count >= 0),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  foreign key (habit_id, user_id) references public.habits(id, user_id),
  unique (habit_id, day_key, user_id)
);

create table public.idea_prompts (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  text text not null check (length(trim(text)) > 0),
  shown_at timestamptz,
  dismissed boolean not null default false,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

-- Server timestamps allow incremental pull ordering. Phase 2 must use a revision
-- checked RPC to resolve queued offline writes; ordinary upsert is not sufficient.
create function public.dayos_stamp_update() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.updated_at = clock_timestamp();
  return new;
end;
$$;

do $$
declare table_name text;
begin
  foreach table_name in array array['lists','tasks','habits','habit_logs','idea_prompts'] loop
    execute format('alter table public.%I enable row level security', table_name);
    execute format('create policy owner_select on public.%I for select to authenticated using ((select auth.uid()) = user_id)', table_name);
    execute format('create policy owner_insert on public.%I for insert to authenticated with check ((select auth.uid()) = user_id)', table_name);
    execute format('create policy owner_update on public.%I for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id)', table_name);
    -- No client hard delete: retain tombstones for offline devices.
    execute format('revoke all on public.%I from anon, authenticated', table_name);
    execute format('grant select, insert, update on public.%I to authenticated', table_name);
    execute format('create index on public.%I (user_id, updated_at, id)', table_name);
    execute format('create trigger stamp_update before insert or update on public.%I for each row execute function public.dayos_stamp_update()', table_name);
    execute format('alter publication supabase_realtime add table public.%I', table_name);
  end loop;
end $$;

commit;
