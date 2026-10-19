-- Revision-checked document transport shared by the native iOS and Windows apps.
create table public.orbit_records (
 user_id uuid not null references auth.users(id) on delete cascade,
 key text not null check (key ~ '^(tasks|habits|habit_logs|lists|idea_prompts)/[a-z0-9-]{1,100}$'),
 payload jsonb not null check (jsonb_typeof(payload) = 'object' and octet_length(payload::text) < 131072),
 deleted boolean not null default false,
 revision bigint not null default 1,
 mutation uuid not null,
 primary key (user_id,key)
);
alter table public.orbit_records enable row level security;
revoke all on public.orbit_records from anon, authenticated;
grant select on public.orbit_records to authenticated;
create policy owner_read on public.orbit_records for select to authenticated using ((select auth.uid())=user_id);

-- Writes must go through CAS: direct INSERT/UPDATE grants would bypass revisions.
-- Definer is intentional; identity comes only from auth.uid(), never a parameter.
create function public.orbit_put(p_key text,p_payload jsonb,p_deleted boolean,p_base bigint,p_mutation uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid(); current_row public.orbit_records;
begin
 if uid is null then raise exception 'Sign in required' using errcode='42501'; end if;
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
revoke all on function public.orbit_put(text,jsonb,boolean,bigint,uuid) from public,anon;
grant execute on function public.orbit_put(text,jsonb,boolean,bigint,uuid) to authenticated;
alter publication supabase_realtime add table public.orbit_records;
