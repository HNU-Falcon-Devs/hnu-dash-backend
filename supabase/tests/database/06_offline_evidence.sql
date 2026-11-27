begin;
-- Disposable synthetic-only M4.1 fixtures, including historical cutoff cases.
select plan(122);

insert into auth.users(id,instance_id,aud,role,email,email_confirmed_at,created_at,updated_at) values
 ('b2000000-0000-4000-8000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','m41-synthetic-1@hnu.edu.ph',now(),now(),now()),
 ('b2000000-0000-4000-8000-000000000002','00000000-0000-0000-0000-000000000000','authenticated','authenticated','m41-synthetic-2@hnu.edu.ph',now(),now(),now()),
 ('b2000000-0000-4000-8000-000000000003','00000000-0000-0000-0000-000000000000','authenticated','authenticated','m41-synthetic-3@hnu.edu.ph',now(),now(),now()),
 ('b2000000-0000-4000-8000-000000000004','00000000-0000-0000-0000-000000000000','authenticated','authenticated','m41-synthetic-4@hnu.edu.ph',now(),now(),now()),
 ('b2000000-0000-4000-8000-000000000005','00000000-0000-0000-0000-000000000000','authenticated','authenticated','m41-synthetic-5@hnu.edu.ph',now(),now(),now()),
 ('b2000000-0000-4000-8000-000000000006','00000000-0000-0000-0000-000000000000','authenticated','authenticated','m41-synthetic-6@hnu.edu.ph',null,now(),now()),
 ('b2000000-0000-4000-8000-000000000007','00000000-0000-0000-0000-000000000000','authenticated','authenticated','m41-synthetic-7@example.org',now(),now(),now()),
 ('b2000000-0000-4000-8000-000000000008','00000000-0000-0000-0000-000000000000','authenticated','authenticated','m41-synthetic-8@hnu.edu.ph',now(),now(),now()),
 ('b2000000-0000-4000-8000-000000000009','00000000-0000-0000-0000-000000000000','authenticated','authenticated','m41-synthetic-9@hnu.edu.ph',now(),now(),now());
insert into public.platform_admins(user_id) values ('b2000000-0000-4000-8000-000000000001');
insert into public.organizations(id,slug,name) values ('b1000000-0000-4000-8000-000000000001','offline-one','Offline One'),('b1000000-0000-4000-8000-000000000002','offline-two','Offline Two');
insert into public.organization_memberships(organization_id,user_id,role,active,granted_by) values
 ('b1000000-0000-4000-8000-000000000001','b2000000-0000-4000-8000-000000000002','leader',true,'b2000000-0000-4000-8000-000000000001'),
 ('b1000000-0000-4000-8000-000000000002','b2000000-0000-4000-8000-000000000003','leader',true,'b2000000-0000-4000-8000-000000000001'),
 ('b1000000-0000-4000-8000-000000000001','b2000000-0000-4000-8000-000000000004','staff',true,'b2000000-0000-4000-8000-000000000001'),
 ('b1000000-0000-4000-8000-000000000001','b2000000-0000-4000-8000-000000000005','staff',true,'b2000000-0000-4000-8000-000000000001'),
 ('b1000000-0000-4000-8000-000000000001','b2000000-0000-4000-8000-000000000006','staff',true,'b2000000-0000-4000-8000-000000000001'),
 ('b1000000-0000-4000-8000-000000000001','b2000000-0000-4000-8000-000000000007','staff',true,'b2000000-0000-4000-8000-000000000001'),
 ('b1000000-0000-4000-8000-000000000001','b2000000-0000-4000-8000-000000000008','staff',false,'b2000000-0000-4000-8000-000000000001'),
 ('b1000000-0000-4000-8000-000000000002','b2000000-0000-4000-8000-000000000009','staff',true,'b2000000-0000-4000-8000-000000000001');
insert into public.students(student_id,full_name,program_code,year_level) values
 ('00000000001','Synthetic Offline One','BSIT',1),('00000000002','Synthetic Offline Two','BSIT',1);
insert into public.events(id,organization_id,created_by,title,starts_at,ends_at) values
 ('b3000000-0000-4000-8000-000000000001','b1000000-0000-4000-8000-000000000001','b2000000-0000-4000-8000-000000000001','Synthetic Offline Event 1',now()-interval '30 hours',now()+interval '15 hours'),
 ('b3000000-0000-4000-8000-000000000002','b1000000-0000-4000-8000-000000000001','b2000000-0000-4000-8000-000000000001','Synthetic Offline Event 2',now()-interval '30 hours',now()+interval '15 hours'),
 ('b3000000-0000-4000-8000-000000000003','b1000000-0000-4000-8000-000000000001','b2000000-0000-4000-8000-000000000001','Synthetic Offline Event 3',now()-interval '30 hours',now()+interval '15 hours'),
 ('b3000000-0000-4000-8000-000000000004','b1000000-0000-4000-8000-000000000001','b2000000-0000-4000-8000-000000000001','Synthetic Offline Event 4',now()-interval '30 hours',now()+interval '15 hours'),
 ('b3000000-0000-4000-8000-000000000005','b1000000-0000-4000-8000-000000000001','b2000000-0000-4000-8000-000000000001','Synthetic Offline Event 5',now()-interval '30 hours',now()+interval '15 hours'),
 ('b3000000-0000-4000-8000-000000000006','b1000000-0000-4000-8000-000000000002','b2000000-0000-4000-8000-000000000001','Synthetic Offline Event 6',now()-interval '30 hours',now()+interval '15 hours'),
 ('b3000000-0000-4000-8000-000000000007','b1000000-0000-4000-8000-000000000001','b2000000-0000-4000-8000-000000000001','Synthetic Offline Event 7',now()-interval '30 hours',now()+interval '15 hours');
select set_config('request.jwt.claim.sub','b2000000-0000-4000-8000-000000000001',true);
insert into public.event_checkpoints(id,event_id,label,direction,opens_at,closes_at) values
 ('b4000000-0000-4000-8000-000000000001','b3000000-0000-4000-8000-000000000001','Checkpoint 1','IN',now()-interval '29 hours',now()+interval '12 hours'),
 ('b4000000-0000-4000-8000-000000000002','b3000000-0000-4000-8000-000000000002','Checkpoint 2','IN',now()-interval '29 hours',now()+interval '-1 hours'),
 ('b4000000-0000-4000-8000-000000000003','b3000000-0000-4000-8000-000000000003','Checkpoint 3','IN',now()-interval '29 hours',now()+interval '-25 hours'),
 ('b4000000-0000-4000-8000-000000000004','b3000000-0000-4000-8000-000000000004','Checkpoint 4','IN',now()-interval '29 hours',now()+interval '-1 hours'),
 ('b4000000-0000-4000-8000-000000000005','b3000000-0000-4000-8000-000000000005','Checkpoint 5','IN',now()-interval '29 hours',now()+interval '-1 hours'),
 ('b4000000-0000-4000-8000-000000000006','b3000000-0000-4000-8000-000000000006','Checkpoint 6','IN',now()-interval '29 hours',now()+interval '1 hours'),
 ('b4000000-0000-4000-8000-000000000007','b3000000-0000-4000-8000-000000000007','Checkpoint 7','IN',now()-interval '29 hours',now()+interval '1 hours'),
 ('b4000000-0000-4000-8000-000000000008','b3000000-0000-4000-8000-000000000001','Checkpoint 8','IN',now()-interval '29 hours',now()+interval '1 hours');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','b2000000-0000-4000-8000-000000000002',true);
select is((select offline_enabled from public.events where id='b3000000-0000-4000-8000-000000000001'),false,'default offline disabled');
select ok((select offline_upload_cutoff is null from public.events where id='b3000000-0000-4000-8000-000000000001'),'draft default no cutoff');
select throws_ok($test$select public.enable_event_offline('b3000000-0000-4000-8000-000000000006')$test$,'42501');
select throws_ok($test$select public.enable_event_offline(null)$test$,'22023');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','b2000000-0000-4000-8000-000000000004',true);
select throws_ok($test$select public.enable_event_offline('b3000000-0000-4000-8000-000000000001')$test$,'42501');
reset role;
set local role anon;
select set_config('request.jwt.claim.sub','',true);
select throws_ok($test$select public.enable_event_offline('b3000000-0000-4000-8000-000000000001')$test$,'42501');
select throws_ok($test$select public.prepare_offline_capture('b3000000-0000-4000-8000-000000000001','b6000000-0000-4000-8000-000000000001')$test$,'42501');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','b2000000-0000-4000-8000-000000000001',true);
select is((select public.enable_event_offline('b3000000-0000-4000-8000-000000000001')),true,'enable draft 1');
select is((select public.enable_event_offline('b3000000-0000-4000-8000-000000000002')),true,'enable draft 2');
select is((select public.enable_event_offline('b3000000-0000-4000-8000-000000000003')),true,'enable draft 3');
select is((select public.enable_event_offline('b3000000-0000-4000-8000-000000000005')),true,'enable draft 5');
select is((select public.enable_event_offline('b3000000-0000-4000-8000-000000000006')),true,'enable draft 6');
select is((select public.enable_event_offline('b3000000-0000-4000-8000-000000000007')),true,'enable draft 7');
select is((select public.enable_event_offline('b3000000-0000-4000-8000-000000000001')),true,'draft opt-in retry');
select public.update_draft_event('b3000000-0000-4000-8000-000000000001','Edited Offline Event',now()-interval '30 hours',now()+interval '15 hours',array[1]::smallint[]);
update public.event_checkpoints set closes_at=now()+interval '13 hours' where id='b4000000-0000-4000-8000-000000000001';
select is((select public.freeze_event_roster('b3000000-0000-4000-8000-000000000001')),2,'freeze 1');
select is((select public.freeze_event_roster('b3000000-0000-4000-8000-000000000002')),2,'freeze 2');
select is((select public.freeze_event_roster('b3000000-0000-4000-8000-000000000003')),2,'freeze 3');
select is((select public.freeze_event_roster('b3000000-0000-4000-8000-000000000004')),2,'freeze 4');
select is((select public.freeze_event_roster('b3000000-0000-4000-8000-000000000005')),2,'freeze 5');
select is((select public.freeze_event_roster('b3000000-0000-4000-8000-000000000006')),2,'freeze 6');
select is((select public.freeze_event_roster('b3000000-0000-4000-8000-000000000007')),2,'freeze 7');
select is((select event_state from public.open_event('b3000000-0000-4000-8000-000000000001')),'OPEN','open 1');
select is((select event_state from public.open_event('b3000000-0000-4000-8000-000000000006')),'OPEN','open 6');
select is((select event_state from public.open_event('b3000000-0000-4000-8000-000000000007')),'OPEN','open 7');
reset role;
-- Historical disposable fixtures only: no server clock modification.
-- Derive the cutoff through the real policy trigger at the OPEN transition.
update public.events set state='OPEN',opened_at=now()-interval '28 hours'
where id in ('b3000000-0000-4000-8000-000000000002','b3000000-0000-4000-8000-000000000003','b3000000-0000-4000-8000-000000000004','b3000000-0000-4000-8000-000000000005');
insert into public.event_staff(id,event_id,staff_user_id,assigned_at,assigned_by) values
 ('b5000000-0000-4000-8000-000000000001','b3000000-0000-4000-8000-000000000001','b2000000-0000-4000-8000-000000000004',now()-interval '28 hours','b2000000-0000-4000-8000-000000000001'),
 ('b5000000-0000-4000-8000-000000000002','b3000000-0000-4000-8000-000000000002','b2000000-0000-4000-8000-000000000004',now()-interval '28 hours','b2000000-0000-4000-8000-000000000001'),
 ('b5000000-0000-4000-8000-000000000003','b3000000-0000-4000-8000-000000000003','b2000000-0000-4000-8000-000000000004',now()-interval '28 hours','b2000000-0000-4000-8000-000000000001'),
 ('b5000000-0000-4000-8000-000000000004','b3000000-0000-4000-8000-000000000004','b2000000-0000-4000-8000-000000000004',now()-interval '28 hours','b2000000-0000-4000-8000-000000000001'),
 ('b5000000-0000-4000-8000-000000000005','b3000000-0000-4000-8000-000000000001','b2000000-0000-4000-8000-000000000005',now()-interval '28 hours','b2000000-0000-4000-8000-000000000001'),
 ('b5000000-0000-4000-8000-000000000006','b3000000-0000-4000-8000-000000000006','b2000000-0000-4000-8000-000000000009',now()-interval '28 hours','b2000000-0000-4000-8000-000000000001'),
 ('b5000000-0000-4000-8000-000000000007','b3000000-0000-4000-8000-000000000007','b2000000-0000-4000-8000-000000000004',now()-interval '28 hours','b2000000-0000-4000-8000-000000000001'),
 ('b5000000-0000-4000-8000-000000000008','b3000000-0000-4000-8000-000000000001','b2000000-0000-4000-8000-000000000006',now()-interval '28 hours','b2000000-0000-4000-8000-000000000001'),
 ('b5000000-0000-4000-8000-000000000009','b3000000-0000-4000-8000-000000000001','b2000000-0000-4000-8000-000000000007',now()-interval '28 hours','b2000000-0000-4000-8000-000000000001'),
 ('b5000000-0000-4000-8000-000000000010','b3000000-0000-4000-8000-000000000001','b2000000-0000-4000-8000-000000000008',now()-interval '28 hours','b2000000-0000-4000-8000-000000000001');
insert into public.offline_preparations(id,request_id,event_id,assignment_id,staff_user_id,issued_at,expires_at) values
 ('b7000000-0000-4000-8000-000000000002','b6000000-0000-4000-8000-000000000002','b3000000-0000-4000-8000-000000000002','b5000000-0000-4000-8000-000000000002','b2000000-0000-4000-8000-000000000004',now()-interval '3 hours',now()-interval '1 hour'),
 ('b7000000-0000-4000-8000-000000000003','b6000000-0000-4000-8000-000000000003','b3000000-0000-4000-8000-000000000003','b5000000-0000-4000-8000-000000000003','b2000000-0000-4000-8000-000000000004',now()-interval '27 hours',now()-interval '25 hours'),
 ('b7000000-0000-4000-8000-000000000007','b6000000-0000-4000-8000-000000000007','b3000000-0000-4000-8000-000000000007','b5000000-0000-4000-8000-000000000007','b2000000-0000-4000-8000-000000000004',now()-interval '10 hours',now()-interval '2 hours');
-- An immutable historical acknowledgement, already committed before cutoff.
insert into public.offline_capture_claims(capture_id,preparation_id,event_id,checkpoint_id,student_id,claimed_at,received_at,review_eligible)
values ('b8000000-0000-4000-8000-000000000030','b7000000-0000-4000-8000-000000000003','b3000000-0000-4000-8000-000000000003','b4000000-0000-4000-8000-000000000003','00000000001',now()-interval '26 hours',now()-interval '24 hours',true);
select is((select offline_upload_cutoff from public.events where id='b3000000-0000-4000-8000-000000000001'),(select max(closes_at)+interval '24 hours' from public.event_checkpoints where event_id='b3000000-0000-4000-8000-000000000001'),'cutoff derived from final edited checkpoint');
select ok((select not offline_enabled and offline_upload_cutoff is null from public.events where id='b3000000-0000-4000-8000-000000000004'),'online activation keeps default');
select throws_ok($test$update public.events set offline_upload_cutoff=now() where id='b3000000-0000-4000-8000-000000000001'$test$,'42501');
select throws_ok($test$update public.events set offline_enabled=false where id='b3000000-0000-4000-8000-000000000001'$test$,'55000');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','b2000000-0000-4000-8000-000000000001',true);
select throws_ok($test$select public.enable_event_offline('b3000000-0000-4000-8000-000000000001')$test$,'55000');
select throws_ok($test$select public.enable_event_offline('b3000000-0000-4000-8000-000000000004')$test$,'55000');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','b2000000-0000-4000-8000-000000000004',true);
select set_config('m41.prep',(public.prepare_offline_capture('b3000000-0000-4000-8000-000000000001','b6000000-0000-4000-8000-000000000001'))::text,true);
select is((select current_setting('m41.prep')::jsonb->>'replayed'),'false','initial preparation');
select is((select current_setting('m41.prep')::jsonb->>'assignment_id'),'b5000000-0000-4000-8000-000000000001'::text,'exact assignment period');
select is((select current_setting('m41.prep')::jsonb->>'staff_user_id'),'b2000000-0000-4000-8000-000000000004'::text,'actor derived');
select is((select (current_setting('m41.prep')::jsonb->>'expires_at')::timestamptz),(current_setting('m41.prep')::jsonb->>'issued_at')::timestamptz+interval '8 hours','eight hour bound');
select is((select jsonb_array_length(current_setting('m41.prep')::jsonb->'checkpoints')),2,'minimal configured checkpoint context');
select ok(not (current_setting('m41.prep')::jsonb ? 'roster') and not (current_setting('m41.prep')::jsonb ? 'access_token'),'no roster or credentials');
select set_config('m41.preplay',(public.prepare_offline_capture('b3000000-0000-4000-8000-000000000001','b6000000-0000-4000-8000-000000000001'))::text,true);
select is((select current_setting('m41.preplay')::jsonb-'replayed'),current_setting('m41.prep')::jsonb-'replayed','preparation replay exact metadata');
select is((select current_setting('m41.preplay')::jsonb->>'replayed'),'true','preparation replay flag');
select throws_ok($test$select public.prepare_offline_capture('b3000000-0000-4000-8000-000000000001','b6000000-0000-4000-8000-000000000011')$test$,'55000');
select throws_ok($test$select public.prepare_offline_capture('b3000000-0000-4000-8000-000000000004','b6000000-0000-4000-8000-000000000044')$test$,'55000');
select throws_ok($test$select public.prepare_offline_capture('b3000000-0000-4000-8000-000000000006','b6000000-0000-4000-8000-000000000066')$test$,'42501');
select throws_ok($test$select public.prepare_offline_capture(null,'b6000000-0000-4000-8000-000000000001')$test$,'22023');
select throws_ok($test$select public.prepare_offline_capture('b3000000-0000-4000-8000-000000000001',null)$test$,'22023');
select set_config('m41.short',(public.prepare_offline_capture('b3000000-0000-4000-8000-000000000007','b6000000-0000-4000-8000-000000000071'))::text,true);
select is((select (current_setting('m41.short')::jsonb->>'expires_at')::timestamptz),(select closes_at from public.event_checkpoints where id='b4000000-0000-4000-8000-000000000007'),'fresh preparation after expiry bounded by last close');
select is((select public.prepare_offline_capture('b3000000-0000-4000-8000-000000000007','b6000000-0000-4000-8000-000000000007')->>'preparation_id'),'b7000000-0000-4000-8000-000000000007'::text,'old request does not extend or replace history');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','b2000000-0000-4000-8000-000000000005',true);
select throws_ok($test$select public.prepare_offline_capture('b3000000-0000-4000-8000-000000000001','b6000000-0000-4000-8000-000000000001')$test$,'42501');
select throws_ok($test$select public.submit_offline_capture((current_setting('m41.prep')::jsonb->>'preparation_id')::uuid,'b8000000-0000-4000-8000-000000000099','b4000000-0000-4000-8000-000000000001','00000000001',(current_setting('m41.prep')::jsonb->>'issued_at')::timestamptz)$test$,'42501');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','b2000000-0000-4000-8000-000000000001',true);
select throws_ok($test$select public.prepare_offline_capture('b3000000-0000-4000-8000-000000000001','b6000000-0000-4000-8000-000000000090')$test$,'42501');
select throws_ok($test$select public.submit_offline_capture((current_setting('m41.prep')::jsonb->>'preparation_id')::uuid,'b8000000-0000-4000-8000-000000000099','b4000000-0000-4000-8000-000000000001','00000000001',(current_setting('m41.prep')::jsonb->>'issued_at')::timestamptz)$test$,'42501');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','b2000000-0000-4000-8000-000000000002',true);
select throws_ok($test$select public.prepare_offline_capture('b3000000-0000-4000-8000-000000000001','b6000000-0000-4000-8000-000000000090')$test$,'42501');
select throws_ok($test$select public.submit_offline_capture((current_setting('m41.prep')::jsonb->>'preparation_id')::uuid,'b8000000-0000-4000-8000-000000000099','b4000000-0000-4000-8000-000000000001','00000000001',(current_setting('m41.prep')::jsonb->>'issued_at')::timestamptz)$test$,'42501');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','b2000000-0000-4000-8000-000000000003',true);
select throws_ok($test$select public.prepare_offline_capture('b3000000-0000-4000-8000-000000000001','b6000000-0000-4000-8000-000000000090')$test$,'42501');
select throws_ok($test$select public.submit_offline_capture((current_setting('m41.prep')::jsonb->>'preparation_id')::uuid,'b8000000-0000-4000-8000-000000000099','b4000000-0000-4000-8000-000000000001','00000000001',(current_setting('m41.prep')::jsonb->>'issued_at')::timestamptz)$test$,'42501');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','b2000000-0000-4000-8000-000000000006',true);
select throws_ok($test$select public.prepare_offline_capture('b3000000-0000-4000-8000-000000000001','b6000000-0000-4000-8000-000000000090')$test$,'42501');
select throws_ok($test$select public.submit_offline_capture((current_setting('m41.prep')::jsonb->>'preparation_id')::uuid,'b8000000-0000-4000-8000-000000000099','b4000000-0000-4000-8000-000000000001','00000000001',(current_setting('m41.prep')::jsonb->>'issued_at')::timestamptz)$test$,'42501');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','b2000000-0000-4000-8000-000000000007',true);
select throws_ok($test$select public.prepare_offline_capture('b3000000-0000-4000-8000-000000000001','b6000000-0000-4000-8000-000000000090')$test$,'42501');
select throws_ok($test$select public.submit_offline_capture((current_setting('m41.prep')::jsonb->>'preparation_id')::uuid,'b8000000-0000-4000-8000-000000000099','b4000000-0000-4000-8000-000000000001','00000000001',(current_setting('m41.prep')::jsonb->>'issued_at')::timestamptz)$test$,'42501');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','b2000000-0000-4000-8000-000000000008',true);
select throws_ok($test$select public.prepare_offline_capture('b3000000-0000-4000-8000-000000000001','b6000000-0000-4000-8000-000000000090')$test$,'42501');
select throws_ok($test$select public.submit_offline_capture((current_setting('m41.prep')::jsonb->>'preparation_id')::uuid,'b8000000-0000-4000-8000-000000000099','b4000000-0000-4000-8000-000000000001','00000000001',(current_setting('m41.prep')::jsonb->>'issued_at')::timestamptz)$test$,'42501');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','b2000000-0000-4000-8000-000000000009',true);
select throws_ok($test$select public.prepare_offline_capture('b3000000-0000-4000-8000-000000000001','b6000000-0000-4000-8000-000000000090')$test$,'42501');
select throws_ok($test$select public.submit_offline_capture((current_setting('m41.prep')::jsonb->>'preparation_id')::uuid,'b8000000-0000-4000-8000-000000000099','b4000000-0000-4000-8000-000000000001','00000000001',(current_setting('m41.prep')::jsonb->>'issued_at')::timestamptz)$test$,'42501');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','b2000000-0000-4000-8000-000000000004',true);
select throws_ok($test$select public.submit_offline_capture((current_setting('m41.prep')::jsonb->>'preparation_id')::uuid,'b8000000-0000-4000-8000-000000000099','b4000000-0000-4000-8000-000000000006','00000000001',(current_setting('m41.prep')::jsonb->>'issued_at')::timestamptz)$test$,'42501');
select throws_ok($test$select public.submit_offline_capture((current_setting('m41.prep')::jsonb->>'preparation_id')::uuid,'b8000000-0000-4000-8000-000000000099','b4000000-0000-4000-8000-000000000001','bad id',(current_setting('m41.prep')::jsonb->>'issued_at')::timestamptz)$test$,'22023');
select throws_ok($test$select public.submit_offline_capture((current_setting('m41.prep')::jsonb->>'preparation_id')::uuid,'b8000000-0000-4000-8000-000000000099','b4000000-0000-4000-8000-000000000001','00000000001','infinity'::timestamptz)$test$,'22023');
select throws_ok($test$select public.submit_offline_capture((current_setting('m41.prep')::jsonb->>'preparation_id')::uuid,'b8000000-0000-4000-8000-000000000099','b4000000-0000-4000-8000-000000000001','00000000001',null)$test$,'22023');
select throws_ok($test$select public.submit_offline_capture(null,'b8000000-0000-4000-8000-000000000099','b4000000-0000-4000-8000-000000000001','00000000001',now())$test$,'22023');
select throws_ok($test$select * from public.offline_capture_claims$test$,'42501');
select throws_ok($test$select * from public.offline_preparations$test$,'42501');
select throws_ok($test$insert into public.offline_capture_claims(capture_id) values ('b8000000-0000-4000-8000-000000000099')$test$,'42501');
select set_config('m41.claim',(public.submit_offline_capture((current_setting('m41.prep')::jsonb->>'preparation_id')::uuid,'b8000000-0000-4000-8000-000000000001','b4000000-0000-4000-8000-000000000001','00000000001',(current_setting('m41.prep')::jsonb->>'issued_at')::timestamptz))::text,true);
select is((select current_setting('m41.claim')::jsonb->>'status'),'submitted','offline durable acknowledgement');
select is((select current_setting('m41.claim')::jsonb->>'replayed'),'false','new claim flag');
select ok(not (current_setting('m41.claim')::jsonb ? 'review_eligible') and not (current_setting('m41.claim')::jsonb ? 'outcome'),'no eligibility or acceptance oracle');
select set_config('m41.creplay',(public.submit_offline_capture((current_setting('m41.prep')::jsonb->>'preparation_id')::uuid,'b8000000-0000-4000-8000-000000000001','b4000000-0000-4000-8000-000000000001','00000000001',(current_setting('m41.prep')::jsonb->>'issued_at')::timestamptz))::text,true);
select is((select current_setting('m41.creplay')::jsonb-'replayed'),current_setting('m41.claim')::jsonb-'replayed','same capture returns original acknowledgement');
select is((select current_setting('m41.creplay')::jsonb->>'replayed'),'true','capture replay flag');
select throws_ok($test$select public.submit_offline_capture((current_setting('m41.prep')::jsonb->>'preparation_id')::uuid,'b8000000-0000-4000-8000-000000000001','b4000000-0000-4000-8000-000000000001','00000000002',(current_setting('m41.prep')::jsonb->>'issued_at')::timestamptz)$test$,'23505');
select throws_ok($test$select public.submit_offline_capture((current_setting('m41.prep')::jsonb->>'preparation_id')::uuid,'b8000000-0000-4000-8000-000000000001','b4000000-0000-4000-8000-000000000008','00000000001',(current_setting('m41.prep')::jsonb->>'issued_at')::timestamptz)$test$,'23505');
select throws_ok($test$select public.submit_offline_capture((current_setting('m41.prep')::jsonb->>'preparation_id')::uuid,'b8000000-0000-4000-8000-000000000001','b4000000-0000-4000-8000-000000000001','00000000001',(current_setting('m41.prep')::jsonb->>'issued_at')::timestamptz+interval '1 second')$test$,'23505');
select set_config('m41.bad2',(public.submit_offline_capture((current_setting('m41.prep')::jsonb->>'preparation_id')::uuid,'b8000000-0000-4000-8000-000000000002','b4000000-0000-4000-8000-000000000001','00000999999',(current_setting('m41.prep')::jsonb->>'issued_at')::timestamptz))::text,true);
select is((select current_setting('m41.bad2')::jsonb->>'status'),'submitted','non-roster generic acknowledgement');
select ok(not (current_setting('m41.bad2')::jsonb ? 'review_eligible'),'non-roster eligibility hidden');
select set_config('m41.bad3',(public.submit_offline_capture((current_setting('m41.prep')::jsonb->>'preparation_id')::uuid,'b8000000-0000-4000-8000-000000000003','b4000000-0000-4000-8000-000000000001','00000000001',(current_setting('m41.prep')::jsonb->>'issued_at')::timestamptz-interval '1 second'))::text,true);
select is((select current_setting('m41.bad3')::jsonb->>'status'),'submitted','rollback clock generic acknowledgement');
select ok(not (current_setting('m41.bad3')::jsonb ? 'review_eligible'),'rollback clock eligibility hidden');
select set_config('m41.bad4',(public.submit_offline_capture((current_setting('m41.prep')::jsonb->>'preparation_id')::uuid,'b8000000-0000-4000-8000-000000000004','b4000000-0000-4000-8000-000000000001','00000000001',(current_setting('m41.prep')::jsonb->>'issued_at')::timestamptz+interval '7 hours'))::text,true);
select is((select current_setting('m41.bad4')::jsonb->>'status'),'submitted','future clock generic acknowledgement');
select ok(not (current_setting('m41.bad4')::jsonb ? 'review_eligible'),'future clock eligibility hidden');
select set_config('m41.bad5',(public.submit_offline_capture((current_setting('m41.prep')::jsonb->>'preparation_id')::uuid,'b8000000-0000-4000-8000-000000000005','b4000000-0000-4000-8000-000000000001','00000000001',(current_setting('m41.prep')::jsonb->>'expires_at')::timestamptz))::text,true);
select is((select current_setting('m41.bad5')::jsonb->>'status'),'submitted','expiry boundary generic acknowledgement');
select ok(not (current_setting('m41.bad5')::jsonb ? 'review_eligible'),'expiry boundary eligibility hidden');
select is((select public.submit_offline_capture('b7000000-0000-4000-8000-000000000002','b8000000-0000-4000-8000-000000000020','b4000000-0000-4000-8000-000000000002','00000000001',now()-interval '2 hours')->>'status'),'submitted','post-expiry upload before cutoff');
select is((select public.submit_offline_capture('b7000000-0000-4000-8000-000000000003','b8000000-0000-4000-8000-000000000030','b4000000-0000-4000-8000-000000000003','00000000001',now()-interval '26 hours')->>'replayed'),'true','authorized post-cutoff replay');
select throws_ok($test$select public.submit_offline_capture('b7000000-0000-4000-8000-000000000003','b8000000-0000-4000-8000-000000000031','b4000000-0000-4000-8000-000000000003','00000000001',now()-interval '26 hours')$test$,'55000');
select is((select public.ingest_attendance_scan('b8000000-0000-4000-8000-000000000001','b3000000-0000-4000-8000-000000000001','b4000000-0000-4000-8000-000000000001','00000000001')->>'outcome'),'accepted','same UUID in online namespace is independent');
select is((select public.ingest_attendance_scan('b8000000-0000-4000-8000-000000000001','b3000000-0000-4000-8000-000000000001','b4000000-0000-4000-8000-000000000001','00000000001')->>'replayed'),'true','online retry remains online receipt');
reset role;
select ok((select review_eligible from public.offline_capture_claims where capture_id='b8000000-0000-4000-8000-000000000001'),'plausible claim remains private');
select is((select count(*)::int from public.offline_capture_claims where capture_id in ('b8000000-0000-4000-8000-000000000002','b8000000-0000-4000-8000-000000000003','b8000000-0000-4000-8000-000000000004','b8000000-0000-4000-8000-000000000005') and not review_eligible),4,'all ineligible claims retained');
select ok((select review_eligible from public.offline_capture_claims where capture_id='b8000000-0000-4000-8000-000000000020'),'expired preparation valid capture eligible for future review');
select is((select count(*)::int from public.attendance_scans where event_id='b3000000-0000-4000-8000-000000000001'),1,'claims never create canonical receipts');
select is((select count(*)::int from public.attendance_records where event_id='b3000000-0000-4000-8000-000000000001'),0,'claims never create results');
select is((select count(*)::int from public.offline_preparations where event_id='b3000000-0000-4000-8000-000000000001'),1,'no orphan preparation');
select throws_ok($test$update public.offline_capture_claims set review_eligible=false where capture_id='b8000000-0000-4000-8000-000000000001'$test$,'42501');
select throws_ok($test$delete from public.offline_capture_claims where capture_id='b8000000-0000-4000-8000-000000000001'$test$,'42501');
select throws_ok($test$update public.offline_preparations set expires_at=expires_at-interval '1 hour' where id=(current_setting('m41.prep')::jsonb->>'preparation_id')::uuid$test$,'42501');
select throws_ok($test$delete from public.offline_preparations where id=(current_setting('m41.prep')::jsonb->>'preparation_id')::uuid$test$,'42501');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','b2000000-0000-4000-8000-000000000001',true);
select is((select public.close_event('b3000000-0000-4000-8000-000000000002')->>'event_state'),'SYNCING','offline event closure unchanged');
select is((select public.close_event('b3000000-0000-4000-8000-000000000005')->>'event_state'),'SYNCING','zero preparation event closes');
select throws_ok($test$select public.finalize_event('b3000000-0000-4000-8000-000000000002')$test$,'55000');
select throws_ok($test$select public.finalize_event('b3000000-0000-4000-8000-000000000005')$test$,'55000');
select is((select public.close_event('b3000000-0000-4000-8000-000000000004')->>'event_state'),'SYNCING','online-only closure');
select is((select public.finalize_event('b3000000-0000-4000-8000-000000000004')->>'record_count'),'2','online-only finalization');
select is((select public.finalize_event('b3000000-0000-4000-8000-000000000004')->>'replayed'),'true','online finalization replay unchanged');
select is((select count(*)::int from public.get_event_finalized_results('b3000000-0000-4000-8000-000000000004')),2,'existing finalized results readable');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','b2000000-0000-4000-8000-000000000004',true);
select is((select public.submit_offline_capture('b7000000-0000-4000-8000-000000000002','b8000000-0000-4000-8000-000000000021','b4000000-0000-4000-8000-000000000002','00000000002',now()-interval '2 hours')->>'status'),'submitted','SYNCING upload allowed');
select throws_ok($test$select public.prepare_offline_capture('b3000000-0000-4000-8000-000000000002','b6000000-0000-4000-8000-000000000022')$test$,'55000');
select is((select public.prepare_offline_capture('b3000000-0000-4000-8000-000000000002','b6000000-0000-4000-8000-000000000002')->>'preparation_id'),'b7000000-0000-4000-8000-000000000002'::text,'authorized old preparation retry after closure');
select throws_ok($test$select public.ingest_attendance_scan('b8000000-0000-4000-8000-000000000021','b3000000-0000-4000-8000-000000000002','b4000000-0000-4000-8000-000000000002','00000000002')$test$,'55000');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','b2000000-0000-4000-8000-000000000001',true);
select ok(public.revoke_event_staff('b5000000-0000-4000-8000-000000000001') is not null,'revoke exact assignment');
select ok(public.assign_event_staff('b3000000-0000-4000-8000-000000000001','b2000000-0000-4000-8000-000000000004') is not null,'reassign creates new period');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','b2000000-0000-4000-8000-000000000004',true);
select throws_ok($test$select public.submit_offline_capture((current_setting('m41.prep')::jsonb->>'preparation_id')::uuid,'b8000000-0000-4000-8000-000000000001','b4000000-0000-4000-8000-000000000001','00000000001',(current_setting('m41.prep')::jsonb->>'issued_at')::timestamptz)$test$,'42501');
select throws_ok($test$select public.submit_offline_capture((current_setting('m41.prep')::jsonb->>'preparation_id')::uuid,'b8000000-0000-4000-8000-000000000009','b4000000-0000-4000-8000-000000000001','00000000001',(current_setting('m41.prep')::jsonb->>'issued_at')::timestamptz)$test$,'42501');
select throws_ok($test$select public.prepare_offline_capture('b3000000-0000-4000-8000-000000000001','b6000000-0000-4000-8000-000000000001')$test$,'42501');
select set_config('m41.newprep',(public.prepare_offline_capture('b3000000-0000-4000-8000-000000000001','b6000000-0000-4000-8000-000000000012'))::text,true);
select ok((current_setting('m41.newprep')::jsonb->>'assignment_id')::uuid <> 'b5000000-0000-4000-8000-000000000001'::uuid,'fresh preparation belongs to new assignment');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','b2000000-0000-4000-8000-000000000001',true);
select is(public.update_org_member('b1000000-0000-4000-8000-000000000001','b2000000-0000-4000-8000-000000000004','staff',false,1)->>'status','updated','admin deactivation through authoritative membership RPC');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','b2000000-0000-4000-8000-000000000004',true);
select throws_ok($test$select public.submit_offline_capture((current_setting('m41.newprep')::jsonb->>'preparation_id')::uuid,'b8000000-0000-4000-8000-000000000010','b4000000-0000-4000-8000-000000000001','00000000001',(current_setting('m41.newprep')::jsonb->>'issued_at')::timestamptz)$test$,'42501');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','b2000000-0000-4000-8000-000000000001',true);
reset role;
select is((select count(*)::int from public.attendance_records where event_id in ('b3000000-0000-4000-8000-000000000002','b3000000-0000-4000-8000-000000000005')),0,'fail-closed no results');
select is((select count(*)::int from public.offline_capture_claims where capture_id in ('b8000000-0000-4000-8000-000000000009','b8000000-0000-4000-8000-000000000010','b8000000-0000-4000-8000-000000000031','b8000000-0000-4000-8000-000000000099')),0,'denied claims leave no rows');
select * from finish();
rollback;
