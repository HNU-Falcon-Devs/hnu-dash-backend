begin;
-- M3.1 synthetic, transaction-rolled-back integration tests.
select plan(52);

select ok(to_regprocedure('public.get_event_checkpoint_coverage(uuid,integer,integer)') is not null,
  'coverage RPC exists with the documented signature');
select ok(not has_function_privilege('anon',
  'public.get_event_checkpoint_coverage(uuid,integer,integer)','EXECUTE'),
  'anonymous EXECUTE is revoked');
select ok(has_function_privilege('authenticated',
  'public.get_event_checkpoint_coverage(uuid,integer,integer)','EXECUTE'),
  'authenticated EXECUTE is explicitly granted');
select is((select prosecdef from pg_proc
  where oid='public.get_event_checkpoint_coverage(uuid,integer,integer)'::regprocedure),
  false,'coverage uses invoker rights and existing table RLS');
select ok(not has_table_privilege('authenticated','public.attendance_scans','INSERT'),
  'coverage did not enable direct scan insertion');
select ok(not has_table_privilege('authenticated','public.attendance_scans','UPDATE'),
  'coverage did not enable direct scan updates');
select ok(not has_table_privilege('authenticated','public.attendance_scans','DELETE'),
  'coverage did not enable direct scan deletion');
select ok(not has_table_privilege('authenticated','public.event_roster','INSERT'),
  'frozen roster remains read-only for clients');
select ok(not has_table_privilege('authenticated','public.events','UPDATE'),
  'event status remains controlled by prior RPC');

insert into auth.users(id,instance_id,aud,role,email,email_confirmed_at,created_at,updated_at)
values
 ('82000000-0000-4000-8000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','admin-coverage@hnu.edu.ph',now(),now(),now()),
 ('82000000-0000-4000-8000-000000000002','00000000-0000-0000-0000-000000000000','authenticated','authenticated','leader-coverage@hnu.edu.ph',now(),now(),now()),
 ('82000000-0000-4000-8000-000000000003','00000000-0000-0000-0000-000000000000','authenticated','authenticated','other-leader-coverage@hnu.edu.ph',now(),now(),now()),
 ('82000000-0000-4000-8000-000000000004','00000000-0000-0000-0000-000000000000','authenticated','authenticated','staff-coverage@hnu.edu.ph',now(),now(),now()),
 ('82000000-0000-4000-8000-000000000005','00000000-0000-0000-0000-000000000000','authenticated','authenticated','unverified-coverage@hnu.edu.ph',null,now(),now()),
 ('82000000-0000-4000-8000-000000000006','00000000-0000-0000-0000-000000000000','authenticated','authenticated','wrong-domain@example.org',now(),now(),now()),
 ('82000000-0000-4000-8000-000000000007','00000000-0000-0000-0000-000000000000','authenticated','authenticated','inactive-coverage@hnu.edu.ph',now(),now(),now()),
 ('82000000-0000-4000-8000-000000000008','00000000-0000-0000-0000-000000000000','authenticated','authenticated','student-coverage@hnu.edu.ph',now(),now(),now());
insert into public.platform_admins(user_id)
values ('82000000-0000-4000-8000-000000000001');
insert into public.organizations(id,slug,name) values
 ('81000000-0000-4000-8000-000000000001','coverage-one','Coverage One'),
 ('81000000-0000-4000-8000-000000000002','coverage-two','Coverage Two');
insert into public.organization_memberships(organization_id,user_id,role,active,granted_by) values
 ('81000000-0000-4000-8000-000000000001','82000000-0000-4000-8000-000000000002','leader',true,'82000000-0000-4000-8000-000000000001'),
 ('81000000-0000-4000-8000-000000000002','82000000-0000-4000-8000-000000000003','leader',true,'82000000-0000-4000-8000-000000000001'),
 ('81000000-0000-4000-8000-000000000001','82000000-0000-4000-8000-000000000004','staff',true,'82000000-0000-4000-8000-000000000001'),
 ('81000000-0000-4000-8000-000000000001','82000000-0000-4000-8000-000000000005','leader',true,'82000000-0000-4000-8000-000000000001'),
 ('81000000-0000-4000-8000-000000000001','82000000-0000-4000-8000-000000000006','leader',true,'82000000-0000-4000-8000-000000000001'),
 ('81000000-0000-4000-8000-000000000001','82000000-0000-4000-8000-000000000007','leader',false,'82000000-0000-4000-8000-000000000001');
insert into public.students(student_id,full_name,program_code,year_level)
select lpad(n::text,11,'0'), 'Synthetic Coverage ' || n, 'BSIT', 1
from generate_series(1,600) as n;
insert into public.events(id,organization_id,created_by,title,starts_at,ends_at) values
 ('83000000-0000-4000-8000-000000000001','81000000-0000-4000-8000-000000000001','82000000-0000-4000-8000-000000000001','Four Checkpoint Coverage',now()-interval '2 hours',now()+interval '2 hours'),
 ('83000000-0000-4000-8000-000000000002','81000000-0000-4000-8000-000000000001','82000000-0000-4000-8000-000000000001','IN Only Coverage',now()-interval '2 hours',now()+interval '2 hours'),
 ('83000000-0000-4000-8000-000000000003','81000000-0000-4000-8000-000000000001','82000000-0000-4000-8000-000000000001','Unfrozen Coverage',now()-interval '2 hours',now()+interval '2 hours'),
 ('83000000-0000-4000-8000-000000000004','81000000-0000-4000-8000-000000000002','82000000-0000-4000-8000-000000000001','Foreign Coverage',now()-interval '2 hours',now()+interval '2 hours');

-- Deterministic checkpoint UUIDs are operator-only fixture setup.
reset role;
select set_config('request.jwt.claim.sub','82000000-0000-4000-8000-000000000001',true);
insert into public.event_checkpoints(id,event_id,label,direction,opens_at,closes_at,sort_order) values
 ('84000000-0000-4000-8000-000000000001','83000000-0000-4000-8000-000000000001','Morning IN','IN',now()-interval '1 hour',now()+interval '1 hour',0),
 ('84000000-0000-4000-8000-000000000002','83000000-0000-4000-8000-000000000001','Morning OUT','OUT',now()-interval '1 hour',now()+interval '1 hour',0),
 ('84000000-0000-4000-8000-000000000003','83000000-0000-4000-8000-000000000001','Afternoon IN','IN',now()-interval '1 hour',now()+interval '1 hour',1),
 ('84000000-0000-4000-8000-000000000004','83000000-0000-4000-8000-000000000001','Afternoon OUT','OUT',now()-interval '1 hour',now()+interval '1 hour',2),
 ('84000000-0000-4000-8000-000000000005','83000000-0000-4000-8000-000000000002','Only IN','IN',now()-interval '1 hour',now()+interval '1 hour',0),
 ('84000000-0000-4000-8000-000000000006','83000000-0000-4000-8000-000000000003','Draft IN','IN',now()-interval '1 hour',now()+interval '1 hour',0),
 ('84000000-0000-4000-8000-000000000007','83000000-0000-4000-8000-000000000004','Foreign IN','IN',now()-interval '1 hour',now()+interval '1 hour',0);

set local role authenticated;
select is(public.freeze_event_roster('83000000-0000-4000-8000-000000000001'),600,
  'four-checkpoint roster freezes 600 synthetic students');
select is(public.freeze_event_roster('83000000-0000-4000-8000-000000000002'),600,
  'IN-only roster freezes 600 synthetic students');
select is(public.freeze_event_roster('83000000-0000-4000-8000-000000000004'),600,
  'foreign organization roster freezes independently');
select is((select event_state from public.open_event('83000000-0000-4000-8000-000000000001')),
  'OPEN','coverage event opens through existing lifecycle RPC');
select is((select event_state from public.open_event('83000000-0000-4000-8000-000000000002')),
  'OPEN','IN-only event opens through existing lifecycle RPC');
select ok(public.assign_event_staff('83000000-0000-4000-8000-000000000001',
  '82000000-0000-4000-8000-000000000004') is not null,
  'ordinary Staff has a real active event assignment');
select is((select count(*)::int from public.get_event_checkpoint_coverage(
  '83000000-0000-4000-8000-000000000001')),200,
  'default page is capped at 200 rows');
select is((select count(*)::int from public.get_event_checkpoint_coverage(
  '83000000-0000-4000-8000-000000000001',200,0) where has_accepted_scan),0,
  'initial coverage is false before accepted scans exist');
select is((select count(*)::int from public.get_event_checkpoint_coverage(
  '83000000-0000-4000-8000-000000000002',200,0) where has_accepted_scan),0,
  'IN-only event initially has no accepted evidence');
select is((select count(*)::int from public.get_event_checkpoint_coverage(
  '83000000-0000-4000-8000-000000000001',200,0)
  where accepted_received_at is not null),0,
  'missing evidence has null authoritative receipt time');
select is((select string_agg(checkpoint_id::text,',' order by checkpoint_sort_order,checkpoint_id)
  from public.get_event_checkpoint_coverage('83000000-0000-4000-8000-000000000001',4,0)),
  '84000000-0000-4000-8000-000000000001,84000000-0000-4000-8000-000000000002,84000000-0000-4000-8000-000000000003,84000000-0000-4000-8000-000000000004',
  'equal sort orders break ties by checkpoint UUID');
select is((select student_id from public.get_event_checkpoint_coverage(
  '83000000-0000-4000-8000-000000000001',1,0)),
  '00000000001','leading-zero student ID is returned unchanged');
select is((select student_id from public.get_event_checkpoint_coverage(
  '83000000-0000-4000-8000-000000000001',1,200)),
  '00000000051','second 200-row page starts at the expected student');
select is((select count(*)::int from public.get_event_checkpoint_coverage(
  '83000000-0000-4000-8000-000000000001',200,2400)),0,
  'page beyond 2400 returns an empty set');
select is((select count(*)::int
  from generate_series(0,11) as pg(n)
  cross join lateral public.get_event_checkpoint_coverage(
    '83000000-0000-4000-8000-000000000001',200,pg.n*200)),2400,
  'all 2400 combinations are retrievable across twelve pages');
select is((select count(distinct (c.student_id,c.checkpoint_id))::int
  from generate_series(0,11) as pg(n)
  cross join lateral public.get_event_checkpoint_coverage(
    '83000000-0000-4000-8000-000000000001',200,pg.n*200) as c),2400,
  'paginated result covers each student-checkpoint pair once');

-- Seed accepted/rejected/duplicate receipts as a synthetic database operator.
-- No hosted or real student records are used, and this test rolls back.
reset role;
insert into public.attendance_scans
 (scan_id,event_id,checkpoint_id,student_id,submitted_by,received_at,outcome) values
 ('85000000-0000-4000-8000-000000000001','83000000-0000-4000-8000-000000000001','84000000-0000-4000-8000-000000000001','00000000001','82000000-0000-4000-8000-000000000004',now()-interval '1 minute','accepted'),
 ('85000000-0000-4000-8000-000000000002','83000000-0000-4000-8000-000000000001','84000000-0000-4000-8000-000000000003','00000000002','82000000-0000-4000-8000-000000000004',now()-interval '1 minute','accepted'),
 ('85000000-0000-4000-8000-000000000003','83000000-0000-4000-8000-000000000001','84000000-0000-4000-8000-000000000001','00000000003','82000000-0000-4000-8000-000000000004',now()-interval '1 minute','rejected'),
 ('85000000-0000-4000-8000-000000000004','83000000-0000-4000-8000-000000000001','84000000-0000-4000-8000-000000000002','00000000004','82000000-0000-4000-8000-000000000004',now()-interval '1 minute','duplicate');
insert into public.attendance_scans
 (scan_id,event_id,checkpoint_id,student_id,submitted_by,received_at,outcome)
select gen_random_uuid(),'83000000-0000-4000-8000-000000000002'::uuid,
 '84000000-0000-4000-8000-000000000005'::uuid,r.student_id,
 '82000000-0000-4000-8000-000000000004'::uuid,now()-interval '1 minute','accepted'
from public.event_roster r
where r.event_id='83000000-0000-4000-8000-000000000002';

set local role authenticated;
select is((select count(*)::int from public.get_event_checkpoint_coverage(
  '83000000-0000-4000-8000-000000000001',200,0) where has_accepted_scan),2,
  'only two accepted big-event receipts create coverage');
select is((select count(*)::int from public.get_event_checkpoint_coverage(
  '83000000-0000-4000-8000-000000000001',200,0) where accepted_received_at is not null),2,
  'only accepted coverage carries receipt timestamps');
select is((select count(*)::int from public.get_event_checkpoint_coverage(
  '83000000-0000-4000-8000-000000000001',200,0)
  where student_id='00000000003' and has_accepted_scan),0,
  'rejected evidence does not create coverage');
select is((select count(*)::int from public.get_event_checkpoint_coverage(
  '83000000-0000-4000-8000-000000000001',200,0)
  where student_id='00000000004' and has_accepted_scan),0,
  'duplicate evidence does not create coverage');
select is((select accepted_received_at from public.get_event_checkpoint_coverage(
  '83000000-0000-4000-8000-000000000001',200,0)
  where student_id='00000000001' and checkpoint_id='84000000-0000-4000-8000-000000000001'),
  (select received_at from public.attendance_scans
   where scan_id='85000000-0000-4000-8000-000000000001'),
  'preview exposes the exact immutable server receipt timestamp');
select is((select count(*)::int
  from generate_series(0,2) as pg(n)
  cross join lateral public.get_event_checkpoint_coverage(
    '83000000-0000-4000-8000-000000000002',200,pg.n*200) as c
  where c.has_accepted_scan),600,
  'IN-only event supports fully covered 600-student roster');
select is((select count(*)::int from public.attendance_scans
  where event_id='83000000-0000-4000-8000-000000000001'),4,
  'preview did not mutate or erase immutable big-event evidence');
select is((select count(*)::int from public.attendance_scans
  where event_id='83000000-0000-4000-8000-000000000002'),600,
  'preview did not alter accepted IN-only evidence');

select throws_ok($test$select * from public.get_event_checkpoint_coverage(
  '83000000-0000-4000-8000-000000000099')$test$,'42501');
select throws_ok($test$select * from public.get_event_checkpoint_coverage(
  '83000000-0000-4000-8000-000000000003')$test$,'55000');
select throws_ok($test$select * from public.get_event_checkpoint_coverage(null)$test$,'22023');
select throws_ok($test$select * from public.get_event_checkpoint_coverage(
  '83000000-0000-4000-8000-000000000001',0,0)$test$,'22023');
select throws_ok($test$select * from public.get_event_checkpoint_coverage(
  '83000000-0000-4000-8000-000000000001',201,0)$test$,'22023');
select throws_ok($test$select * from public.get_event_checkpoint_coverage(
  '83000000-0000-4000-8000-000000000001',200,-1)$test$,'22023');
select throws_ok($test$select * from public.get_event_checkpoint_coverage(
  '83000000-0000-4000-8000-000000000001',null,0)$test$,'22023');

-- An active leader can read the owning organization's event, but not another.
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','82000000-0000-4000-8000-000000000002',true);
select is((select count(*)::int from public.get_event_checkpoint_coverage(
  '83000000-0000-4000-8000-000000000001',200,0)),200,
  'verified active owning-organization leader can preview coverage');
select throws_ok($test$select * from public.get_event_checkpoint_coverage(
  '83000000-0000-4000-8000-000000000004')$test$,'42501');

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','82000000-0000-4000-8000-000000000003',true);
select throws_ok($test$select * from public.get_event_checkpoint_coverage(
  '83000000-0000-4000-8000-000000000001')$test$,'42501');

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','82000000-0000-4000-8000-000000000004',true);
select ok(public.can_access_assigned_event('83000000-0000-4000-8000-000000000001'),
  'Staff is genuinely assigned to the event');
select throws_ok($test$select * from public.get_event_checkpoint_coverage(
  '83000000-0000-4000-8000-000000000001')$test$,'42501');

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','82000000-0000-4000-8000-000000000005',true);
select throws_ok($test$select * from public.get_event_checkpoint_coverage(
  '83000000-0000-4000-8000-000000000001')$test$,'42501');

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','82000000-0000-4000-8000-000000000006',true);
select throws_ok($test$select * from public.get_event_checkpoint_coverage(
  '83000000-0000-4000-8000-000000000001')$test$,'42501');

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','82000000-0000-4000-8000-000000000007',true);
select throws_ok($test$select * from public.get_event_checkpoint_coverage(
  '83000000-0000-4000-8000-000000000001')$test$,'42501');

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','82000000-0000-4000-8000-000000000008',true);
select throws_ok($test$select * from public.get_event_checkpoint_coverage(
  '83000000-0000-4000-8000-000000000001')$test$,'42501');

reset role;
set local role anon;
select set_config('request.jwt.claim.sub','',true);
select throws_ok($test$select * from public.get_event_checkpoint_coverage(
  '83000000-0000-4000-8000-000000000001')$test$,'42501');

reset role;
select is((select count(*)::int from public.attendance_scans where outcome='accepted'),602,
  'all accepted scan evidence survives role denials and previews');
select is((select count(*)::int from public.attendance_scans where outcome in ('rejected','duplicate')),2,
  'rejected and duplicate evidence remain immutable and present');

select * from finish();
rollback;
