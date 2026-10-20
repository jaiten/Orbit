-- Session access is enforced by the database, including for older Orbit clients.
create schema if not exists orbit_private;
revoke all on schema orbit_private from public, anon, authenticated;
create table public.orbit_devices (
 session_id uuid primary key,
 user_id uuid not null references auth.users(id) on delete cascade,
 name text not null check (char_length(name) between 1 and 100),
 last_seen timestamptz not null default now(),
 revoked_at timestamptz
);
alter table public.orbit_devices enable row level security;
revoke all on public.orbit_devices from public, anon, authenticated;
create index orbit_devices_owner on public.orbit_devices(user_id);

create function orbit_private.session_allowed() returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from auth.sessions s where s.id=(auth.jwt()->>'session_id')::uuid and s.user_id=auth.uid())
 and not exists(select 1 from public.orbit_devices d where d.session_id=(auth.jwt()->>'session_id')::uuid and d.revoked_at is not null)
$$;
-- Only the policy and the explicitly checked RPCs use this function.
grant usage on schema orbit_private to authenticated;
revoke all on function orbit_private.session_allowed() from public, anon;
grant execute on function orbit_private.session_allowed() to authenticated;

alter policy owner_read on public.orbit_records to authenticated
 using ((select auth.uid())=user_id and (select orbit_private.session_allowed()));

create function public.orbit_devices_list(p_name text default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid(); sid uuid:=(auth.jwt()->>'session_id')::uuid;
begin
 if uid is null or not orbit_private.session_allowed() then raise exception 'This device no longer has access. Sign in again.' using errcode='42501'; end if;
 if p_name is not null then
  insert into public.orbit_devices(session_id,user_id,name) values(sid,uid,left(p_name,100))
  on conflict(session_id) do update set last_seen=now(),name=excluded.name;
 end if;
 return coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'name',coalesce(d.name,case when s.user_agent ilike '%Windows%' then 'Windows' when s.user_agent ilike '%iPhone%' then 'iPhone' else 'Earlier sign-in' end),'current',s.id=sid,'last_seen',coalesce(d.last_seen,s.updated_at,s.created_at)))
 from auth.sessions s left join public.orbit_devices d on d.session_id=s.id
 where s.user_id=uid and d.revoked_at is null and (s.not_after is null or s.not_after>now())), '[]'::jsonb);
end $$;

create function public.orbit_device_remove(p_session uuid) returns boolean
language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid();
begin
 if uid is null or not orbit_private.session_allowed() then raise exception 'Sign in required' using errcode='42501'; end if;
 if not exists(select 1 from auth.sessions where id=p_session and user_id=uid) then raise exception 'Device not found' using errcode='42501'; end if;
 insert into public.orbit_devices(session_id,user_id,name,revoked_at) values(p_session,uid,'Removed device',now())
 on conflict(session_id) do update set revoked_at=now();
 return true;
end $$;

create or replace function public.orbit_put(p_key text,p_payload jsonb,p_deleted boolean,p_base bigint,p_mutation uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare uid uuid:=auth.uid(); current_row public.orbit_records;
begin
 if uid is null or not orbit_private.session_allowed() then raise exception 'This device no longer has access. Sign in again.' using errcode='42501'; end if;
 perform pg_advisory_xact_lock(hashtextextended(uid::text || '/' || p_key,0));
 select * into current_row from public.orbit_records where user_id=uid and key=p_key;
 if found then
  if current_row.mutation=p_mutation then return jsonb_build_object('accepted',true,'record',to_jsonb(current_row)); end if;
  if current_row.revision<>p_base then return jsonb_build_object('accepted',false,'record',to_jsonb(current_row)); end if;
  update public.orbit_records set payload=p_payload,deleted=p_deleted,revision=revision+1,mutation=p_mutation where user_id=uid and key=p_key returning * into current_row;
 else
  if p_base<>0 then raise exception 'Unknown base revision'; end if;
  insert into public.orbit_records(user_id,key,payload,deleted,mutation) values(uid,p_key,p_payload,p_deleted,p_mutation) returning * into current_row;
 end if;
 return jsonb_build_object('accepted',true,'record',to_jsonb(current_row));
end $$;
revoke all on function public.orbit_devices_list(text),public.orbit_device_remove(uuid),public.orbit_put(text,jsonb,boolean,bigint,uuid) from public,anon;
grant execute on function public.orbit_devices_list(text),public.orbit_device_remove(uuid),public.orbit_put(text,jsonb,boolean,bigint,uuid) to authenticated;
