-- Run as postgres against a disposable/local project. All fixtures roll back.
begin;
select plan(1);
do $$
declare a uuid:=gen_random_uuid(); b uuid:=gen_random_uuid(); sa uuid:=gen_random_uuid(); sb uuid:=gen_random_uuid();
begin
 insert into auth.users(id) values(a),(b);
 insert into auth.sessions(id,user_id,created_at,updated_at) values(sa,a,now(),now()),(sb,b,now(),now());
 perform set_config('request.jwt.claims',json_build_object('sub',a,'session_id',sa,'role','authenticated')::text,true);
 if jsonb_array_length(public.orbit_devices_list('Test iPhone'))<>1 then raise exception 'session isolation failed'; end if;
 begin
  perform public.orbit_device_remove(sb);
  raise exception 'cross-account revoke accepted';
 exception when insufficient_privilege then null;
 end;
 perform public.orbit_put('tasks/test',jsonb_build_object('title','Test'),false,0,gen_random_uuid());
end $$;
set local role authenticated;
do $$ begin
 if (select count(*) from public.orbit_records)<>1 then raise exception 'owner read failed'; end if;
 perform public.orbit_device_remove((auth.jwt()->>'session_id')::uuid);
 if (select count(*) from public.orbit_records)<>0 then raise exception 'revoked read accepted'; end if;
 begin
  perform public.orbit_put('tasks/test',jsonb_build_object('title','Blocked'),false,1,gen_random_uuid());
  raise exception 'revoked write accepted';
 exception when insufficient_privilege then null;
 end;
 begin
  perform public.orbit_devices_list('Test');
  raise exception 'revoked session accepted';
 exception when insufficient_privilege then null;
 end;
end $$;
select pass('device isolation and revocation checks passed');
select * from finish();
rollback;
