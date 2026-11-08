begin;
-- All identities, rosters, and scans are synthetic and rolled back.
select plan(76);

select has_table('public','attendance_scans','durable scan evidence relation exists');
select ok(not has_table_privilege('authenticated','public.attendance_scans','INSERT'),
  'authenticated clients cannot insert evidence directly');
select ok(not has_table_privilege('authenticated','public.attendance_scans','UPDATE'),
  'authenticated clients cannot rewrite evidence');
select ok(not has_table_privilege('authenticated','public.attendance_scans','DELETE'),
  'authenticated clients cannot delete evidence');
select ok(not has_table_privilege('anon','public.attendance_scans','SELECT'),
  'anonymous users cannot enumerate scans');
select ok(not has_column_privilege('authenticated','public.event_checkpoints','id','INSERT'),
  'authenticated clients cannot supply internal checkpoint IDs');
select ok(not has_function_privilege('anon',
  'public.ingest_attendance_scan(uuid,uuid,uuid,text)','EXECUTE'),
  'anonymous role cannot call scan ingestion');

insert into auth.users(id,instance_id,aud,role,email,email_confirmed_at,created_at,updated_at)
values
('62000000-0000-4000-8000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','admin-ingest@hnu.edu.ph',now(),now(),now()),
('62000000-0000-4000-8000-000000000002','00000000-0000-0000-0000-000000000000','authenticated','authenticated','leader-ingest@hnu.edu.ph',now(),now(),now()),
('62000000-0000-4000-8000-000000000003','00000000-0000-0000-0000-000000000000','authenticated','authenticated','staff-ingest@hnu.edu.ph',now(),now(),now()),
('62000000-0000-4000-8000-000000000004','00000000-0000-0000-0000-000000000000','authenticated','authenticated','foreign-staff-ingest@hnu.edu.ph',now(),now(),now()),
('62000000-0000-4000-8000-000000000005','00000000-0000-0000-0000-000000000000','authenticated','authenticated','second-staff-ingest@hnu.edu.ph',now(),now(),now()),
('62000000-0000-4000-8000-000000000006','00000000-0000-0000-0000-000000000000','authenticated','authenticated','outsider-ingest@hnu.edu.ph',now(),now(),now()),
('62000000-0000-4000-8000-000000000007','00000000-0000-0000-0000-000000000000','authenticated','authenticated','unverified-ingest@hnu.edu.ph',null,now(),now());
insert into public.platform_admins(user_id) values ('62000000-0000-4000-8000-000000000001');
insert into public.organizations(id,slug,name) values
 ('61000000-0000-4000-8000-000000000001','ingest-test-one','Ingestion Test One'),
 ('61000000-0000-4000-8000-000000000002','ingest-test-two','Ingestion Test Two');
insert into public.organization_memberships(organization_id,user_id,role,active,granted_by) values
 ('61000000-0000-4000-8000-000000000001','62000000-0000-4000-8000-000000000002','leader',true,'62000000-0000-4000-8000-000000000001'),
 ('61000000-0000-4000-8000-000000000001','62000000-0000-4000-8000-000000000003','staff',true,'62000000-0000-4000-8000-000000000001'),
 ('61000000-0000-4000-8000-000000000001','62000000-0000-4000-8000-000000000005','staff',true,'62000000-0000-4000-8000-000000000001'),
 ('61000000-0000-4000-8000-000000000001','62000000-0000-4000-8000-000000000007','staff',true,'62000000-0000-4000-8000-000000000001'),
 ('61000000-0000-4000-8000-000000000002','62000000-0000-4000-8000-000000000004','staff',true,'62000000-0000-4000-8000-000000000001');
insert into public.students(student_id,full_name,program_code,year_level) values
 ('00000123456','Synthetic Zero-Prefixed Student','BSIT',1);
insert into public.events(id,organization_id,created_by,title,starts_at,ends_at) values
 ('63000000-0000-4000-8000-000000000001','61000000-0000-4000-8000-000000000001','62000000-0000-4000-8000-000000000001','Live Ingestion Event',
    now()-interval '3 hours',now()+interval '3 hours'),
 ('63000000-0000-4000-8000-000000000002','61000000-0000-4000-8000-000000000002','62000000-0000-4000-8000-000000000001','Foreign Ingestion Event',
    now()-interval '3 hours',now()+interval '3 hours'),
 ('63000000-0000-4000-8000-000000000003','61000000-0000-4000-8000-000000000001','62000000-0000-4000-8000-000000000001','Draft Ingestion Event',
    now()-interval '3 hours',now()+interval '3 hours');

-- Test operator must supply deterministic checkpoint UUIDs. Normal browser
-- clients intentionally lack INSERT(id); the trigger still validates auth.uid().
reset role;
select set_config('request.jwt.claim.sub','62000000-0000-4000-8000-000000000001',true);

select lives_ok($test$insert into public.event_checkpoints(
 id,event_id,label,direction,opens_at,closes_at) values
 ('64000000-0000-4000-8000-000000000001','63000000-0000-4000-8000-000000000001','Current In','IN',now()-interval '30 minutes',now()+interval '30 minutes')$test$,
 'isolated operator seeds current IN checkpoint');
select lives_ok($test$insert into public.event_checkpoints(
 id,event_id,label,direction,opens_at,closes_at) values
 ('64000000-0000-4000-8000-000000000002','63000000-0000-4000-8000-000000000001','Current Out','OUT',now()-interval '30 minutes',now()+interval '30 minutes')$test$,
 'isolated operator seeds independent OUT checkpoint');
select lives_ok($test$insert into public.event_checkpoints(
 id,event_id,label,direction,opens_at,closes_at) values
 ('64000000-0000-4000-8000-000000000003','63000000-0000-4000-8000-000000000001','Past In','IN',now()-interval '2 hours',now()-interval '1 hour')$test$,
 'isolated operator seeds expired checkpoint inside event schedule');
select lives_ok($test$insert into public.event_checkpoints(
 id,event_id,label,direction,opens_at,closes_at) values
 ('64000000-0000-4000-8000-000000000004','63000000-0000-4000-8000-000000000002','Foreign In','IN',now()-interval '30 minutes',now()+interval '30 minutes')$test$,
 'isolated operator seeds other-org checkpoint');
select lives_ok($test$insert into public.event_checkpoints(
 id,event_id,label,direction,opens_at,closes_at) values
 ('64000000-0000-4000-8000-000000000005','63000000-0000-4000-8000-000000000003','Draft In','IN',now()-interval '30 minutes',now()+interval '30 minutes')$test$,
 'isolated operator seeds draft checkpoint');
set local role authenticated;
select ok(public.freeze_event_roster('63000000-0000-4000-8000-000000000001')>0,'roster frozen for scan event');
select ok(public.freeze_event_roster('63000000-0000-4000-8000-000000000002')>0,'roster frozen for other event');
select is((select event_state from public.open_event('63000000-0000-4000-8000-000000000001')),'OPEN','scan event opened');
select is((select event_state from public.open_event('63000000-0000-4000-8000-000000000002')),'OPEN','other event opened');
select ok(public.assign_event_staff('63000000-0000-4000-8000-000000000001','62000000-0000-4000-8000-000000000003') is not null,'Staff assigned');
select ok(public.assign_event_staff('63000000-0000-4000-8000-000000000001','62000000-0000-4000-8000-000000000005') is not null,'second Staff assigned');
select ok(public.assign_event_staff('63000000-0000-4000-8000-000000000002','62000000-0000-4000-8000-000000000004') is not null,'other-org Staff assigned');
select ok(public.assign_event_staff('63000000-0000-4000-8000-000000000003','62000000-0000-4000-8000-000000000003') is not null,'Staff assigned to DRAFT test event');

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','62000000-0000-4000-8000-000000000003',true);

select ok(public.can_access_assigned_event('63000000-0000-4000-8000-000000000001'),'effective event assignment confirmed');
select ok(set_config('test.scan_initial',
  public.ingest_attendance_scan('65000000-0000-4000-8000-000000000001','63000000-0000-4000-8000-000000000001','64000000-0000-4000-8000-000000000001','00000123456')::text, true) <> '',
  'first authorized scan yields a receipt');
select is((current_setting('test.scan_initial')::jsonb->>'outcome'),
  'accepted','valid Student ID is accepted');
select is((current_setting('test.scan_initial')::jsonb->>'replayed')::boolean,
  false,'first submission is not a replay');
select ok((current_setting('test.scan_initial')::jsonb->>'received_at')::timestamptz
  between now()-interval '5 minutes' and now()+interval '5 minutes',
  'server receipt has plausible authoritative timestamp');
select is((public.ingest_attendance_scan('65000000-0000-4000-8000-000000000001','63000000-0000-4000-8000-000000000001','64000000-0000-4000-8000-000000000001','00000123456')->>'outcome'),
  'accepted','identical UUID retry returns original accepted outcome');
select is((public.ingest_attendance_scan('65000000-0000-4000-8000-000000000001','63000000-0000-4000-8000-000000000001','64000000-0000-4000-8000-000000000001','00000123456')->>'replayed')::boolean,
  true,'identical UUID retry is reported as replayed');
select is((select count(*)::int from public.attendance_scans where scan_id='65000000-0000-4000-8000-000000000001'),
  1,'retry did not append a second receipt');
select is((select student_id from public.attendance_scans where scan_id='65000000-0000-4000-8000-000000000001'),
  '00000123456','leading zero Student ID stored without conversion');
select is((select submitted_by from public.attendance_scans where scan_id='65000000-0000-4000-8000-000000000001'),
  '62000000-0000-4000-8000-000000000003'::uuid,'server recorded actual submitting account');
select is((select received_at from public.attendance_scans where scan_id='65000000-0000-4000-8000-000000000001'),
  (current_setting('test.scan_initial')::jsonb->>'received_at')::timestamptz,
  'replayed receipt preserves original server timestamp');

select throws_ok($test$select public.ingest_attendance_scan('65000000-0000-4000-8000-000000000001','63000000-0000-4000-8000-000000000001','64000000-0000-4000-8000-000000000001','00000999999')$test$,'23505');
select throws_ok($test$select public.ingest_attendance_scan('65000000-0000-4000-8000-000000000001','63000000-0000-4000-8000-000000000001','64000000-0000-4000-8000-000000000002','00000123456')$test$,'23505');
select throws_ok($test$select public.ingest_attendance_scan('65000000-0000-4000-8000-000000000001','63000000-0000-4000-8000-000000000003','64000000-0000-4000-8000-000000000005','00000123456')$test$,'23505');

select ok(set_config('test.scan_duplicate',
  public.ingest_attendance_scan('65000000-0000-4000-8000-000000000002','63000000-0000-4000-8000-000000000001','64000000-0000-4000-8000-000000000001','00000123456')::text,
  true) <> '', 'distinct duplicate-attempt receipt was stored');
select is((current_setting('test.scan_duplicate')::jsonb->>'outcome'),
  'duplicate','new UUID for the same capture is marked duplicate');
select is((current_setting('test.scan_duplicate')::jsonb->>'replayed')::boolean,
  false,'first duplicate attempt is not an idempotent replay');
select is((public.ingest_attendance_scan('65000000-0000-4000-8000-000000000002','63000000-0000-4000-8000-000000000001','64000000-0000-4000-8000-000000000001','00000123456')->>'replayed')::boolean,
  true,'retrying duplicate attempt UUID replays original duplicate receipt');
select is((select count(*)::int from public.attendance_scans
  where event_id='63000000-0000-4000-8000-000000000001' and checkpoint_id='64000000-0000-4000-8000-000000000001' and student_id='00000123456'
    and outcome='accepted'),1,'at most one accepted capture at the checkpoint');
select is((select count(*)::int from public.attendance_scans
  where event_id='63000000-0000-4000-8000-000000000001' and checkpoint_id='64000000-0000-4000-8000-000000000001' and student_id='00000123456'
    and outcome='duplicate'),1,'duplicate attempt remains durable evidence');
select is((public.ingest_attendance_scan('65000000-0000-4000-8000-000000000003','63000000-0000-4000-8000-000000000001','64000000-0000-4000-8000-000000000002','00000123456')->>'outcome'),'accepted',
  'same student at independent OUT checkpoint may be accepted');
select is((public.ingest_attendance_scan('65000000-0000-4000-8000-000000000004','63000000-0000-4000-8000-000000000001','64000000-0000-4000-8000-000000000001','00000999999')->>'outcome'),'rejected',
  'Student ID absent from frozen roster is rejected');
select is((public.ingest_attendance_scan('65000000-0000-4000-8000-000000000004','63000000-0000-4000-8000-000000000001','64000000-0000-4000-8000-000000000001','00000999999')->>'replayed')::boolean,true,
  'rejected receipt can be retried idempotently');
select is((public.ingest_attendance_scan('65000000-0000-4000-8000-000000000005','63000000-0000-4000-8000-000000000001','64000000-0000-4000-8000-000000000003','00000123456')->>'outcome'),'rejected',
  'authoritative server time rejects a closed capture window');
select is((public.ingest_attendance_scan('65000000-0000-4000-8000-000000000006','63000000-0000-4000-8000-000000000003','64000000-0000-4000-8000-000000000005','00000123456')->>'outcome'),'rejected',
  'assigned Staff cannot accept captures before event OPEN');
select is((select count(*)::int from public.attendance_scans
  where scan_id in ('65000000-0000-4000-8000-000000000004','65000000-0000-4000-8000-000000000005','65000000-0000-4000-8000-000000000006') and outcome='rejected'),
  3,'all three validation rejections are recorded immutably');

select throws_ok($test$select public.ingest_attendance_scan('65000000-0000-4000-8000-000000000007','63000000-0000-4000-8000-000000000001','64000000-0000-4000-8000-000000000004','00000123456')$test$,'42501');
select throws_ok($test$select public.ingest_attendance_scan('65000000-0000-4000-8000-000000000007','63000000-0000-4000-8000-000000000001','64000000-0000-4000-8000-000000000099','00000123456')$test$,'42501');
select is((select count(*)::int from public.attendance_scans where scan_id='65000000-0000-4000-8000-000000000007'),
  0,'foreign and missing checkpoint requests create no receipt');
select throws_ok($test$select public.ingest_attendance_scan('65000000-0000-4000-8000-000000000007','63000000-0000-4000-8000-000000000002','64000000-0000-4000-8000-000000000004','00000123456')$test$,'42501');
select throws_ok($test$select public.ingest_attendance_scan('65000000-0000-4000-8000-000000000007','63000000-0000-4000-8000-000000000001','64000000-0000-4000-8000-000000000001','0000 bad')$test$,'22023');
select is((select count(*)::int from public.attendance_scans
  where event_id='63000000-0000-4000-8000-000000000002'),0,'cross-org event is not writable');
select throws_ok($test$select public.ingest_attendance_scan('65000000-0000-4000-8000-000000000007','63000000-0000-4000-8000-000000000099','64000000-0000-4000-8000-000000000001','00000123456')$test$,'42501');

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','62000000-0000-4000-8000-000000000005',true);

select throws_ok($test$select public.ingest_attendance_scan('65000000-0000-4000-8000-000000000001','63000000-0000-4000-8000-000000000001','64000000-0000-4000-8000-000000000001','00000123456')$test$,'23505');
select is((select count(*)::int from public.attendance_scans where submitted_by='62000000-0000-4000-8000-000000000003'),
  0,'different Staff cannot read another Staff member receipts');

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','62000000-0000-4000-8000-000000000004',true);

select throws_ok($test$select public.ingest_attendance_scan('65000000-0000-4000-8000-000000000007','63000000-0000-4000-8000-000000000001','64000000-0000-4000-8000-000000000001','00000123456')$test$,'42501');
select is((select count(*)::int from public.attendance_scans where event_id='63000000-0000-4000-8000-000000000001'),
  0,'foreign Staff cannot enumerate scans from another organization');

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','62000000-0000-4000-8000-000000000002',true);

select throws_ok($test$select public.ingest_attendance_scan('65000000-0000-4000-8000-000000000007','63000000-0000-4000-8000-000000000001','64000000-0000-4000-8000-000000000001','00000123456')$test$,'42501');
select ok((select count(*)::int from public.attendance_scans where event_id='63000000-0000-4000-8000-000000000001')=5,
  'Leader may audit organization receipts but cannot submit Staff scans');

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','62000000-0000-4000-8000-000000000006',true);

select throws_ok($test$select public.ingest_attendance_scan('65000000-0000-4000-8000-000000000007','63000000-0000-4000-8000-000000000001','64000000-0000-4000-8000-000000000001','00000123456')$test$,'42501');
select is((select count(*)::int from public.attendance_scans),0,
  'unassigned outsider sees no evidence');

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','62000000-0000-4000-8000-000000000007',true);

select throws_ok($test$select public.ingest_attendance_scan('65000000-0000-4000-8000-000000000007','63000000-0000-4000-8000-000000000001','64000000-0000-4000-8000-000000000001','00000123456')$test$,'42501');
select is((select count(*)::int from public.attendance_scans),0,
  'unverified user cannot read scan evidence');

reset role;
set local role anon;
select set_config('request.jwt.claim.sub','',true);

select throws_ok($test$select public.ingest_attendance_scan('65000000-0000-4000-8000-000000000007','63000000-0000-4000-8000-000000000001','64000000-0000-4000-8000-000000000001','00000123456')$test$,'42501');

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','62000000-0000-4000-8000-000000000001',true);

select ok(public.revoke_event_staff(
  (select id from public.event_staff where event_id='63000000-0000-4000-8000-000000000001'
   and staff_user_id='62000000-0000-4000-8000-000000000003' and revoked_at is null)) is not null,
  'Admin revokes original Staff assignment');

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','62000000-0000-4000-8000-000000000003',true);

select throws_ok($test$select public.ingest_attendance_scan('65000000-0000-4000-8000-000000000001','63000000-0000-4000-8000-000000000001','64000000-0000-4000-8000-000000000001','00000123456')$test$,'42501');
select throws_ok($test$select public.ingest_attendance_scan('65000000-0000-4000-8000-000000000007','63000000-0000-4000-8000-000000000001','64000000-0000-4000-8000-000000000001','00000123456')$test$,'42501');
select is((select count(*)::int from public.attendance_scans
  where event_id='63000000-0000-4000-8000-000000000001'),0,
  'revoked Staff loses receipts for the revoked event');
select is((select count(*)::int from public.attendance_scans
  where event_id='63000000-0000-4000-8000-000000000003'),1,
  'Staff retains receipt visibility only for separately assigned DRAFT event');
select is((select count(*)::int from public.events where id='63000000-0000-4000-8000-000000000001'),0,
  'revoked Staff loses event visibility');

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','62000000-0000-4000-8000-000000000001',true);

select ok(public.revoke_event_staff(
  (select id from public.event_staff where event_id='63000000-0000-4000-8000-000000000001'
   and staff_user_id='62000000-0000-4000-8000-000000000005' and revoked_at is null)) is not null,
  'Admin revokes second Staff assignment');

reset role;
select is((select count(*)::int from public.attendance_scans where scan_id='65000000-0000-4000-8000-000000000001'),
  1,'revocation did not erase accepted evidence');
select throws_ok($test$update public.attendance_scans
  set outcome='rejected' where scan_id='65000000-0000-4000-8000-000000000001'$test$,'42501');
select throws_ok($test$delete from public.attendance_scans
  where scan_id='65000000-0000-4000-8000-000000000001'$test$,'42501');
select is((select outcome from public.attendance_scans where scan_id='65000000-0000-4000-8000-000000000001'),
  'accepted','tampering attempts did not modify durable evidence');
select is((select count(*)::int from public.attendance_scans
  where outcome='accepted' and checkpoint_id='64000000-0000-4000-8000-000000000001'),1,
  'accepted capture uniqueness survives all retries and revocations');

select * from finish();
rollback;
