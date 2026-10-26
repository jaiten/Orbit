-- Small-beta hardening: retire the unused normalized API, cap per-account sync
-- storage, and provide an authenticated, atomic account-deletion endpoint.

-- These tables were the pre-sync scaffold. Active clients use orbit_records only.
-- Keep the data for now, but remove every client/API and Realtime path to it.
revoke all on table public.lists, public.tasks, public.habits,
  public.habit_logs, public.idea_prompts from anon, authenticated;
alter publication supabase_realtime drop table public.lists;
alter publication supabase_realtime drop table public.tasks;
alter publication supabase_realtime drop table public.habits;
alter publication supabase_realtime drop table public.habit_logs;
alter publication supabase_realtime drop table public.idea_prompts;
revoke all on function public.orbit_stamp_update() from public, anon, authenticated;

create table orbit_private.account_usage (
  user_id uuid primary key references auth.users(id) on delete cascade,
  record_count integer not null default 0 check (record_count >= 0),
  payload_bytes bigint not null default 0 check (payload_bytes >= 0)
);
alter table orbit_private.account_usage enable row level security;
revoke all on table orbit_private.account_usage from public, anon, authenticated;

insert into orbit_private.account_usage(user_id, record_count, payload_bytes)
select user_id, count(*)::integer, coalesce(sum(octet_length(payload::text)), 0)::bigint
from public.orbit_records
group by user_id;

create or replace function public.orbit_put(
  p_key text,
  p_payload jsonb,
  p_deleted boolean,
  p_base bigint,
  p_mutation uuid
) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
  uid uuid := auth.uid();
  current_row public.orbit_records;
  usage_row orbit_private.account_usage;
  new_bytes bigint := octet_length(p_payload::text);
  old_bytes bigint := 0;
begin
  if uid is null or not orbit_private.session_allowed() then
    raise exception 'This device no longer has access. Sign in again.' using errcode='42501';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(uid::text || '/' || p_key, 0));
  insert into orbit_private.account_usage(user_id, record_count, payload_bytes)
  select uid, count(*)::integer, coalesce(sum(octet_length(payload::text)), 0)::bigint
  from public.orbit_records where user_id=uid
  on conflict(user_id) do nothing;
  select * into usage_row from orbit_private.account_usage where user_id=uid for update;
  select * into current_row from public.orbit_records where user_id=uid and key=p_key;
  if found then
    if current_row.mutation=p_mutation then
      return jsonb_build_object('accepted',true,'record',to_jsonb(current_row));
    end if;
    if current_row.revision<>p_base then
      return jsonb_build_object('accepted',false,'record',to_jsonb(current_row));
    end if;
    old_bytes := octet_length(current_row.payload::text);
    if usage_row.payload_bytes-old_bytes+new_bytes > 67108864 then
      raise exception 'Account sync storage limit reached' using errcode='54000';
    end if;
    update public.orbit_records
      set payload=p_payload, deleted=p_deleted, revision=revision+1, mutation=p_mutation
      where user_id=uid and key=p_key returning * into current_row;
    update orbit_private.account_usage
      set payload_bytes=payload_bytes-old_bytes+new_bytes where user_id=uid;
  else
    if p_base<>0 then raise exception 'Unknown base revision'; end if;
    if usage_row.record_count >= 20000 or usage_row.payload_bytes+new_bytes > 67108864 then
      raise exception 'Account sync storage limit reached' using errcode='54000';
    end if;
    insert into public.orbit_records(user_id,key,payload,deleted,mutation)
      values(uid,p_key,p_payload,p_deleted,p_mutation) returning * into current_row;
    update orbit_private.account_usage
      set record_count=record_count+1, payload_bytes=payload_bytes+new_bytes where user_id=uid;
  end if;
  return jsonb_build_object('accepted',true,'record',to_jsonb(current_row));
end $$;

-- Deleting auth.users invalidates every session and cascades all Orbit data. The
-- caller identity is taken only from the verified JWT, never from an argument.
create function public.orbit_delete_account() returns boolean
language plpgsql security definer set search_path='' as $$
declare uid uuid := auth.uid();
begin
  if uid is null or not orbit_private.session_allowed() then
    raise exception 'Sign in required' using errcode='42501';
  end if;
  delete from auth.users where id=uid;
  return found;
end $$;

revoke all on function public.orbit_put(text,jsonb,boolean,bigint,uuid),
  public.orbit_delete_account() from public, anon;
grant execute on function public.orbit_put(text,jsonb,boolean,bigint,uuid),
  public.orbit_delete_account() to authenticated;
