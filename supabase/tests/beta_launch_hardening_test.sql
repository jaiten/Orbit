begin;
select plan(10);

select ok(
  not has_table_privilege('anon', 'public.tasks', 'select,insert,update,delete')
  and not has_table_privilege('authenticated', 'public.tasks', 'select,insert,update,delete'),
  'legacy task API is closed'
);
select ok(
  not has_table_privilege('anon', 'public.habits', 'select,insert,update,delete')
  and not has_table_privilege('authenticated', 'public.habits', 'select,insert,update,delete'),
  'legacy habit API is closed'
);
select ok(
  not has_table_privilege('authenticated', 'orbit_private.account_usage', 'select,insert,update,delete'),
  'account quota counters are private'
);
select ok(
  not has_function_privilege('anon', 'public.orbit_delete_account()', 'execute'),
  'anonymous callers cannot delete accounts'
);
select ok(
  has_function_privilege('authenticated', 'public.orbit_delete_account()', 'execute'),
  'authenticated callers can request their own deletion'
);
select is(
  (select count(*)::integer from pg_publication_tables
    where pubname='supabase_realtime' and tablename in ('lists','tasks','habits','habit_logs','idea_prompts')),
  0,
  'legacy tables are absent from Realtime'
);

insert into auth.users(id) values ('10000000-0000-4000-8000-000000000001');
insert into auth.sessions(id,user_id,created_at,updated_at)
values ('20000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001',now(),now());
insert into orbit_private.account_usage(user_id,record_count,payload_bytes)
values ('10000000-0000-4000-8000-000000000001',20000,0);
select set_config('request.jwt.claims', json_build_object(
  'sub','10000000-0000-4000-8000-000000000001',
  'session_id','20000000-0000-4000-8000-000000000001',
  'role','authenticated')::text, true);
set local role authenticated;
select throws_ok(
  $$select public.orbit_put('tasks/quota-test','{}'::jsonb,false,0,'30000000-0000-4000-8000-000000000001')$$,
  '54000',
  'Account sync storage limit reached',
  'record quota rejects additional records'
);
select is(public.orbit_delete_account(), true, 'signed-in user can delete their account');
reset role;
select is(
  (select count(*)::integer from auth.users where id='10000000-0000-4000-8000-000000000001'),
  0,
  'account deletion removes the auth user'
);
select is(
  (select count(*)::integer from orbit_private.account_usage where user_id='10000000-0000-4000-8000-000000000001'),
  0,
  'account deletion cascades quota metadata'
);

select * from finish();
rollback;
