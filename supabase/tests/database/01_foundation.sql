begin;
-- Runs against a reset local Supabase DB. All users and student records are synthetic.
select plan(55);

select has_table('public','students','student roster table exists');
select has_table('public','events','event table exists');
select has_table('public','event_checkpoints','configurable checkpoint table exists');
select is(public.restrict_hnu_signup('{"user":{"email":"Test@HNU.EDU.PH"}}'::jsonb),
  '{}'::jsonb,'institutional domain accepted in signup hook');
select ok(public.restrict_hnu_signup('{"user":{"email":"someone@gmail.com"}}'::jsonb) ? 'error',
  'outside domain rejected at signup');
select ok(public.restrict_hnu_signup('{"user":{"email":"student@hnu.edu.ph.attacker.test"}}'::jsonb) ? 'error',
  'lookalike domain rejected at signup');
select ok(not has_table_privilege('authenticated','public.students','SELECT'),
  'clients cannot enumerate the canonical student table');

insert into auth.users(id,instance_id,aud,role,email,email_confirmed_at,created_at,updated_at)
values
 ('11111111-1111-4111-8111-111111111111','00000000-0000-0000-0000-000000000000','authenticated','authenticated','admin@hnu.edu.ph',now(),now(),now()),
 ('22222222-2222-4222-8222-222222222222','00000000-0000-0000-0000-000000000000','authenticated','authenticated','leader@hnu.edu.ph',now(),now(),now()),
 ('33333333-3333-4333-8333-333333333333','00000000-0000-0000-0000-000000000000','authenticated','authenticated','outsider@hnu.edu.ph',now(),now(),now()),
 ('44444444-4444-4444-8444-444444444444','00000000-0000-0000-0000-000000000000','authenticated','authenticated','unverified@hnu.edu.ph',null,now(),now());

insert into public.platform_admins(user_id) values ('11111111-1111-4111-8111-111111111111');
insert into public.organizations(id,slug,name) values
 ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','demo-one','Demo One'),
 ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','demo-two','Demo Two');
insert into public.organization_memberships(organization_id,user_id,role,granted_by) values
 ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','22222222-2222-4222-8222-222222222222','leader','11111111-1111-4111-8111-111111111111'),
 ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','44444444-4444-4444-8444-444444444444','leader','11111111-1111-4111-8111-111111111111');
insert into public.events(id,organization_id,created_by,title,starts_at,ends_at)
values
 ('cccccccc-cccc-4ccc-8ccc-cccccccccccc','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  '11111111-1111-4111-8111-111111111111','Demo event','2040-01-01 00:00+00','2040-01-02 00:00+00'),
 ('dddddddd-dddd-4ddd-8ddd-dddddddddddd','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  '11111111-1111-4111-8111-111111111111','Other event','2040-01-01 00:00+00','2040-01-02 00:00+00');

set local role authenticated;
do $$ begin perform set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true); end $$;
select ok(public.is_platform_admin(),'admin role requires server-controlled table');
select is(public.import_students('[
 {"student_id":"00012345","full_name":"Demo Alpha","program_code":"BSIT","year_level":1},
 {"student_id":"00012346","full_name":"Demo Beta","program_code":"BSIT","year_level":2}
]'::jsonb),2,'admin imports synthetic students with leading zeros');

select throws_ok($test$select public.import_students('[
 {"student_id":"00012345","full_name":"First","program_code":"BSIT","year_level":1},
 {"student_id":"00012345","full_name":"Duplicate","program_code":"BSIT","year_level":1}
]'::jsonb)$test$,'23505');
select throws_ok($test$select public.import_students('[
 {"student_id":"00012999","full_name":"Should roll back","program_code":"BSIT","year_level":1},
 {"student_id":"00013000","full_name":"","program_code":"BSIT","year_level":1}
]'::jsonb)$test$,'22023');
select lives_ok($test$select public.bind_student_account(
 '22222222-2222-4222-8222-222222222222','00012345')$test$,
 'admin explicitly binds a verified student account');
select throws_ok($test$select public.bind_student_account(
 '44444444-4444-4444-8444-444444444444','00012346')$test$,'22023');
-- A second organization's checkpoint provides a real RLS target for cross-scope edits.
select lives_ok($test$insert into public.event_checkpoints
 (event_id,label,direction,opens_at,closes_at)
 values ('dddddddd-dddd-4ddd-8ddd-dddddddddddd',
 'Other org checkpoint','IN','2040-01-01 08:00+08','2040-01-01 09:00+08')
$test$, 'admin can create the other organization checkpoint');

reset role;
select is((select count(*)::int from public.students),2,
 'failed import rolls back all its earlier rows');
select is((select student_id from public.profiles where user_id='22222222-2222-4222-8222-222222222222'),
 '00012345','student account binding preserves string ID');

set local role authenticated;
do $$ begin perform set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',true); end $$;
select ok(public.can_manage_org('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
 'leader can manage assigned organization');
select ok(not public.can_manage_org('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'),
 'leader cannot manage a different organization');
select is((select count(*)::int from public.events),1,
 'leader event listing excludes other organizations');
select throws_ok($test$select public.freeze_event_roster(
 'cccccccc-cccc-4ccc-8ccc-cccccccccccc')$test$,'22023');
select throws_ok($test$insert into public.event_checkpoints(event_id,label,direction,opens_at,closes_at)
 values ('cccccccc-cccc-4ccc-8ccc-cccccccccccc','Too Early','IN',
 '2040-01-01 07:00+08','2040-01-01 09:00+08')$test$,'22023');
select throws_ok($test$insert into public.event_checkpoints(event_id,label,direction,opens_at,closes_at)
 values ('cccccccc-cccc-4ccc-8ccc-cccccccccccc','Too Late','OUT',
 '2040-01-02 07:00+08','2040-01-02 09:00+08')$test$,'22023');
select throws_ok($test$insert into public.event_checkpoints(event_id,label,direction,opens_at,closes_at)
 values ('dddddddd-dddd-4ddd-8ddd-dddddddddddd','Foreign Checkpoint','IN',
 '2040-01-01 08:00+08','2040-01-01 09:00+08')$test$,'42501');
select lives_ok($test$update public.event_checkpoints
 set label='Foreign Edited'
 where event_id='dddddddd-dddd-4ddd-8ddd-dddddddddddd'$test$,
 'cross-organization checkpoint update is filtered');
select lives_ok($test$delete from public.event_checkpoints
 where event_id='dddddddd-dddd-4ddd-8ddd-dddddddddddd'$test$,
 'cross-organization checkpoint delete is filtered');
select throws_ok($test$select public.bind_student_account(
 '33333333-3333-4333-8333-333333333333','00012346')$test$,'42501');

select lives_ok($test$insert into public.event_checkpoints(event_id,label,direction,opens_at,closes_at)
 values ('cccccccc-cccc-4ccc-8ccc-cccccccccccc','Morning In','IN',
 '2040-01-01 08:00+08','2040-01-01 10:00+08')$test$,'leader adds a configurable checkpoint');
select throws_ok($test$update public.event_checkpoints
 set closes_at='2040-01-02 09:00+08'
 where event_id='cccccccc-cccc-4ccc-8ccc-cccccccccccc'$test$,'22023');
select throws_ok($test$select public.update_draft_event(
 'cccccccc-cccc-4ccc-8ccc-cccccccccccc','Demo event',
 '2040-01-01 09:00+08','2040-01-02 08:00+08',array[1,2,3,4]::smallint[])
 $test$,'22023');
select lives_ok($test$select public.update_draft_event(
 'cccccccc-cccc-4ccc-8ccc-cccccccccccc','Demo event',
 '2040-01-01 07:00+08','2040-01-02 08:00+08',array[1,2,3,4]::smallint[])
 $test$,'compatible draft schedule expansion is permitted');
select is(public.freeze_event_roster('cccccccc-cccc-4ccc-8ccc-cccccccccccc'),2,
 'freeze snapshots all eligible pilot students');
select throws_ok($test$insert into public.event_checkpoints(event_id,label,direction,opens_at,closes_at)
 values ('cccccccc-cccc-4ccc-8ccc-cccccccccccc','After Freeze','OUT',
 '2040-01-01 08:00+08','2040-01-01 10:00+08')$test$,'42501');
select lives_ok($test$update public.event_checkpoints
 set label='Edited after freeze'
 where event_id='cccccccc-cccc-4ccc-8ccc-cccccccccccc'$test$,
 'RLS filters frozen checkpoint updates');
select lives_ok($test$delete from public.event_checkpoints
 where event_id='cccccccc-cccc-4ccc-8ccc-cccccccccccc'$test$,
 'RLS filters frozen checkpoint deletes');
select throws_ok($test$select public.update_draft_event(
 'cccccccc-cccc-4ccc-8ccc-cccccccccccc','Edited after freeze',
 '2040-01-01 07:00+08','2040-01-02 08:00+08',array[1,2]::smallint[])
 $test$,'42501');
select throws_ok($test$select public.freeze_event_roster(
 'cccccccc-cccc-4ccc-8ccc-cccccccccccc')$test$,'42501');
select throws_ok($test$insert into public.event_roster(
 event_id,student_id,student_name,program_code,year_level,frozen_at)
 values ('cccccccc-cccc-4ccc-8ccc-cccccccccccc',
 '00012345','Forgery','BSIT',1,now())$test$,'42501');
select throws_ok($test$delete from public.event_roster
 where event_id='cccccccc-cccc-4ccc-8ccc-cccccccccccc'$test$,'42501');

select throws_ok($test$select public.import_students('[{"student_id":"OTHER","full_name":"Other","program_code":"BSIT","year_level":1}]'::jsonb)$test$,'42501');

reset role;
select is((select label from public.event_checkpoints
 where event_id='cccccccc-cccc-4ccc-8ccc-cccccccccccc'),
 'Morning In','frozen checkpoint update did not change the record');
select is((select count(*)::int from public.event_checkpoints
 where event_id='cccccccc-cccc-4ccc-8ccc-cccccccccccc'),1,
 'frozen checkpoint delete did not remove records');
-- Even an operator bypassing ordinary RLS cannot casually mutate frozen checkpoints.
select throws_ok($test$update public.event_checkpoints
 set label='Operator overwrite'
 where event_id='cccccccc-cccc-4ccc-8ccc-cccccccccccc'$test$,'42501');
select throws_ok($test$delete from public.event_checkpoints
 where event_id='cccccccc-cccc-4ccc-8ccc-cccccccccccc'$test$,'42501');
select is((select label from public.event_checkpoints
 where event_id='dddddddd-dddd-4ddd-8ddd-dddddddddddd'),
 'Other org checkpoint','foreign checkpoint update was blocked by RLS');
select is((select count(*)::int from public.event_checkpoints
 where event_id='dddddddd-dddd-4ddd-8ddd-dddddddddddd'),1,
 'foreign checkpoint deletion was blocked by RLS');
update public.students set full_name='Edited Demo' where student_id='00012345';
select is((select student_name from public.event_roster
 where event_id='cccccccc-cccc-4ccc-8ccc-cccccccccccc' and student_id='00012345'),
 'Demo Alpha','frozen snapshot does not change when canonical student changes');

set local role authenticated;
do $$ begin perform set_config('request.jwt.claim.sub','33333333-3333-4333-8333-333333333333',true); end $$;
select is((select count(*)::int from public.events),0,
 'unassigned user sees no events');
select throws_ok($test$insert into public.events(organization_id,title,starts_at,ends_at)
 values ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','Intruder event',
 '2040-01-01 00:00+00','2040-01-02 00:00+00')$test$,'42501');
select is((select count(*)::int from public.event_roster),0,
 'unassigned user cannot read a frozen roster');
select throws_ok($test$select public.bind_student_account(
 '33333333-3333-4333-8333-333333333333','00012346')$test$,'42501');
select throws_ok($test$insert into public.event_roster(
 event_id,student_id,student_name,program_code,year_level,frozen_at)
 values ('cccccccc-cccc-4ccc-8ccc-cccccccccccc',
 '00012346','Forged','BSIT',2,now())$test$,'42501');

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','44444444-4444-4444-8444-444444444444',true);
select ok(not public.can_manage_org('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'),
 'unverified leader cannot manage even an assigned organization');
select is((select count(*)::int from public.events),0,
 'unverified member cannot read organization events');
select throws_ok($test$insert into public.event_checkpoints(
 event_id,label,direction,opens_at,closes_at)
 values ('cccccccc-cccc-4ccc-8ccc-cccccccccccc','Unverified',
 'IN','2040-01-01 08:00+08','2040-01-01 09:00+08')$test$,'42501');
select throws_ok($test$select public.bind_student_account(
 '44444444-4444-4444-8444-444444444444','00012346')$test$,'42501');

select * from finish();
rollback;
