begin;
-- M4.2 synthetic fixture; historical windows use real server time, no clock override.
select plan(141);

insert into auth.users(id,instance_id,aud,role,email,email_confirmed_at,created_at,updated_at) values
 ('d2000000-0000-4000-8000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','m42-synthetic-1@hnu.edu.ph',now(),now(),now()),
 ('d2000000-0000-4000-8000-000000000002','00000000-0000-0000-0000-000000000000','authenticated','authenticated','m42-synthetic-2@hnu.edu.ph',now(),now(),now()),
 ('d2000000-0000-4000-8000-000000000003','00000000-0000-0000-0000-000000000000','authenticated','authenticated','m42-synthetic-3@hnu.edu.ph',now(),now(),now()),
 ('d2000000-0000-4000-8000-000000000004','00000000-0000-0000-0000-000000000000','authenticated','authenticated','m42-synthetic-4@hnu.edu.ph',now(),now(),now()),
 ('d2000000-0000-4000-8000-000000000005','00000000-0000-0000-0000-000000000000','authenticated','authenticated','m42-synthetic-5@hnu.edu.ph',now(),now(),now()),
 ('d2000000-0000-4000-8000-000000000006','00000000-0000-0000-0000-000000000000','authenticated','authenticated','m42-synthetic-6@hnu.edu.ph',now(),now(),now()),
 ('d2000000-0000-4000-8000-000000000007','00000000-0000-0000-0000-000000000000','authenticated','authenticated','m42-synthetic-7@hnu.edu.ph',null,now(),now()),
 ('d2000000-0000-4000-8000-000000000008','00000000-0000-0000-0000-000000000000','authenticated','authenticated','m42-synthetic-8@hnu.edu.ph',now(),now(),now());
insert into public.platform_admins(user_id) values ('d2000000-0000-4000-8000-000000000001');
insert into public.organizations(id,slug,name) values ('d1000000-0000-4000-8000-000000000001','reconcile-one','Reconcile One'),('d1000000-0000-4000-8000-000000000002','reconcile-two','Reconcile Two');
insert into public.organization_memberships(organization_id,user_id,role,active,granted_by) values
 ('d1000000-0000-4000-8000-000000000001','d2000000-0000-4000-8000-000000000002','leader',true,'d2000000-0000-4000-8000-000000000001'),
 ('d1000000-0000-4000-8000-000000000002','d2000000-0000-4000-8000-000000000003','leader',true,'d2000000-0000-4000-8000-000000000001'),
 ('d1000000-0000-4000-8000-000000000001','d2000000-0000-4000-8000-000000000004','staff',true,'d2000000-0000-4000-8000-000000000001'),
 ('d1000000-0000-4000-8000-000000000001','d2000000-0000-4000-8000-000000000005','staff',true,'d2000000-0000-4000-8000-000000000001'),
 ('d1000000-0000-4000-8000-000000000001','d2000000-0000-4000-8000-000000000006','staff',true,'d2000000-0000-4000-8000-000000000001'),
 ('d1000000-0000-4000-8000-000000000001','d2000000-0000-4000-8000-000000000007','leader',true,'d2000000-0000-4000-8000-000000000001'),
 ('d1000000-0000-4000-8000-000000000001','d2000000-0000-4000-8000-000000000008','leader',false,'d2000000-0000-4000-8000-000000000001');
insert into public.students(student_id,full_name,program_code,year_level) values
 ('00000000001','Synthetic Reconcile One','BSIT',1),('00000000002','Synthetic Reconcile Two','BSIT',1),('00000000003','Synthetic Reconcile Three','BSIT',1);
insert into public.events(id,organization_id,created_by,title,starts_at,ends_at) values
 ('d3000000-0000-4000-8000-000000000001','d1000000-0000-4000-8000-000000000001','d2000000-0000-4000-8000-000000000001','Synthetic Reconcile Event 1',now()-interval '32 hours',now()+interval '15 hours'),
 ('d3000000-0000-4000-8000-000000000002','d1000000-0000-4000-8000-000000000001','d2000000-0000-4000-8000-000000000001','Synthetic Reconcile Event 2',now()-interval '32 hours',now()+interval '15 hours'),
 ('d3000000-0000-4000-8000-000000000003','d1000000-0000-4000-8000-000000000001','d2000000-0000-4000-8000-000000000001','Synthetic Reconcile Event 3',now()-interval '32 hours',now()+interval '15 hours'),
 ('d3000000-0000-4000-8000-000000000004','d1000000-0000-4000-8000-000000000001','d2000000-0000-4000-8000-000000000001','Synthetic Reconcile Event 4',now()-interval '32 hours',now()+interval '15 hours'),
 ('d3000000-0000-4000-8000-000000000005','d1000000-0000-4000-8000-000000000001','d2000000-0000-4000-8000-000000000001','Synthetic Reconcile Event 5',now()-interval '32 hours',now()+interval '15 hours'),
 ('d3000000-0000-4000-8000-000000000006','d1000000-0000-4000-8000-000000000002','d2000000-0000-4000-8000-000000000001','Synthetic Reconcile Event 6',now()-interval '32 hours',now()+interval '15 hours');
select set_config('request.jwt.claim.sub','d2000000-0000-4000-8000-000000000001',true);
insert into public.event_checkpoints(id,event_id,label,direction,opens_at,closes_at) values
 ('d4000000-0000-4000-8000-000000000001','d3000000-0000-4000-8000-000000000001','Checkpoint 1','IN',now()-interval '29 hours',now()+interval '-25 hours'),
 ('d4000000-0000-4000-8000-000000000002','d3000000-0000-4000-8000-000000000001','Checkpoint 2','IN',now()-interval '29 hours',now()+interval '-25 hours'),
 ('d4000000-0000-4000-8000-000000000003','d3000000-0000-4000-8000-000000000002','Checkpoint 3','IN',now()-interval '29 hours',now()+interval '1 hours'),
 ('d4000000-0000-4000-8000-000000000004','d3000000-0000-4000-8000-000000000003','Checkpoint 4','IN',now()-interval '29 hours',now()+interval '-1 hours'),
 ('d4000000-0000-4000-8000-000000000005','d3000000-0000-4000-8000-000000000004','Checkpoint 5','IN',now()-interval '29 hours',now()+interval '-25 hours'),
 ('d4000000-0000-4000-8000-000000000006','d3000000-0000-4000-8000-000000000005','Checkpoint 6','IN',now()-interval '29 hours',now()+interval '-25 hours'),
 ('d4000000-0000-4000-8000-000000000007','d3000000-0000-4000-8000-000000000006','Checkpoint 7','IN',now()-interval '29 hours',now()+interval '-25 hours');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','d2000000-0000-4000-8000-000000000001',true);
select is((select public.enable_event_offline('d3000000-0000-4000-8000-000000000001')),true,'opt in 1');
select is((select public.enable_event_offline('d3000000-0000-4000-8000-000000000002')),true,'opt in 2');
select is((select public.enable_event_offline('d3000000-0000-4000-8000-000000000003')),true,'opt in 3');
select is((select public.enable_event_offline('d3000000-0000-4000-8000-000000000004')),true,'opt in 4');
select is((select public.enable_event_offline('d3000000-0000-4000-8000-000000000006')),true,'opt in 6');
select is((select public.freeze_event_roster('d3000000-0000-4000-8000-000000000001')),3,'freeze 1');
select is((select public.freeze_event_roster('d3000000-0000-4000-8000-000000000002')),3,'freeze 2');
select is((select public.freeze_event_roster('d3000000-0000-4000-8000-000000000003')),3,'freeze 3');
select is((select public.freeze_event_roster('d3000000-0000-4000-8000-000000000004')),3,'freeze 4');
select is((select public.freeze_event_roster('d3000000-0000-4000-8000-000000000005')),3,'freeze 5');
select is((select public.freeze_event_roster('d3000000-0000-4000-8000-000000000006')),3,'freeze 6');
reset role;
-- Historical operator fixtures: actual server clock is not altered.
update public.events set state='OPEN',opened_at=now()-interval '30 hours'
where id in ('d3000000-0000-4000-8000-000000000001','d3000000-0000-4000-8000-000000000002','d3000000-0000-4000-8000-000000000003','d3000000-0000-4000-8000-000000000004','d3000000-0000-4000-8000-000000000005','d3000000-0000-4000-8000-000000000006');
insert into public.event_staff(id,event_id,staff_user_id,assigned_at,assigned_by) values
 ('d5000000-0000-4000-8000-000000000001','d3000000-0000-4000-8000-000000000001','d2000000-0000-4000-8000-000000000004',now()-interval '30 hours','d2000000-0000-4000-8000-000000000001'),
 ('d5000000-0000-4000-8000-000000000002','d3000000-0000-4000-8000-000000000001','d2000000-0000-4000-8000-000000000005',now()-interval '30 hours','d2000000-0000-4000-8000-000000000001'),
 ('d5000000-0000-4000-8000-000000000003','d3000000-0000-4000-8000-000000000001','d2000000-0000-4000-8000-000000000006',now()-interval '30 hours','d2000000-0000-4000-8000-000000000001'),
 ('d5000000-0000-4000-8000-000000000004','d3000000-0000-4000-8000-000000000002','d2000000-0000-4000-8000-000000000004',now()-interval '30 hours','d2000000-0000-4000-8000-000000000001'),
 ('d5000000-0000-4000-8000-000000000005','d3000000-0000-4000-8000-000000000003','d2000000-0000-4000-8000-000000000004',now()-interval '30 hours','d2000000-0000-4000-8000-000000000001'),
 ('d5000000-0000-4000-8000-000000000006','d3000000-0000-4000-8000-000000000005','d2000000-0000-4000-8000-000000000004',now()-interval '30 hours','d2000000-0000-4000-8000-000000000001');
insert into public.offline_preparations(id,request_id,event_id,assignment_id,staff_user_id,issued_at,expires_at) values
 ('d7000000-0000-4000-8000-000000000001','d6000000-0000-4000-8000-000000000001','d3000000-0000-4000-8000-000000000001','d5000000-0000-4000-8000-000000000001','d2000000-0000-4000-8000-000000000004',now()-interval '28 hours',now()-interval '25 hours'),
 ('d7000000-0000-4000-8000-000000000002','d6000000-0000-4000-8000-000000000002','d3000000-0000-4000-8000-000000000001','d5000000-0000-4000-8000-000000000002','d2000000-0000-4000-8000-000000000005',now()-interval '28 hours',now()-interval '25 hours'),
 ('d7000000-0000-4000-8000-000000000003','d6000000-0000-4000-8000-000000000003','d3000000-0000-4000-8000-000000000001','d5000000-0000-4000-8000-000000000003','d2000000-0000-4000-8000-000000000006',now()-interval '28 hours',now()-interval '25 hours');
insert into public.offline_capture_claims(capture_id,preparation_id,event_id,checkpoint_id,student_id,claimed_at,received_at,review_eligible) values
 ('d8000000-0000-4000-8000-000000000001','d7000000-0000-4000-8000-000000000001','d3000000-0000-4000-8000-000000000001','d4000000-0000-4000-8000-000000000001','00000000001',now()-interval '27 hours',now()-interval '24 hours',true),
 ('d8000000-0000-4000-8000-000000000002','d7000000-0000-4000-8000-000000000001','d3000000-0000-4000-8000-000000000001','d4000000-0000-4000-8000-000000000002','00000000001',now()-interval '27 hours',now()-interval '24 hours',true),
 ('d8000000-0000-4000-8000-000000000003','d7000000-0000-4000-8000-000000000002','d3000000-0000-4000-8000-000000000001','d4000000-0000-4000-8000-000000000001','00000000002',now()-interval '27 hours',now()-interval '24 hours',true),
 ('d8000000-0000-4000-8000-000000000004','d7000000-0000-4000-8000-000000000001','d3000000-0000-4000-8000-000000000001','d4000000-0000-4000-8000-000000000001','00000999999',now()-interval '27 hours',now()-interval '24 hours',false),
 ('d8000000-0000-4000-8000-000000000005','d7000000-0000-4000-8000-000000000002','d3000000-0000-4000-8000-000000000001','d4000000-0000-4000-8000-000000000002','00000000003',now()-interval '29 hours',now()-interval '24 hours',false);
insert into public.attendance_scans(scan_id,event_id,checkpoint_id,student_id,submitted_by,received_at,outcome) values
 ('d8000000-0000-4000-8000-000000000010','d3000000-0000-4000-8000-000000000001','d4000000-0000-4000-8000-000000000001','00000000001','d2000000-0000-4000-8000-000000000004',now()-interval '27 hours','accepted'),
 ('d8000000-0000-4000-8000-000000000011','d3000000-0000-4000-8000-000000000005','d4000000-0000-4000-8000-000000000006','00000000001','d2000000-0000-4000-8000-000000000004',now()-interval '27 hours','accepted');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','d2000000-0000-4000-8000-000000000004',true);
select set_config('m42.live',(public.prepare_offline_capture('d3000000-0000-4000-8000-000000000002','d6000000-0000-4000-8000-000000000020'))::text,true);
select set_config('m42.upload',(public.submit_offline_capture((current_setting('m42.live')::jsonb->>'preparation_id')::uuid,'d8000000-0000-4000-8000-000000000020','d4000000-0000-4000-8000-000000000003','00000000001',(current_setting('m42.live')::jsonb->>'issued_at')::timestamptz))::text,true);
select ok(public.get_offline_preparation_status((current_setting('m42.live')::jsonb->>'preparation_id')::uuid)->>'can_upload' = 'true','new upload available');
select is((select public.get_offline_preparation_status((current_setting('m42.live')::jsonb->>'preparation_id')::uuid)->>'uploaded_count'),'1','staff scoped durable count');
select ok(not (public.get_offline_preparation_status((current_setting('m42.live')::jsonb->>'preparation_id')::uuid) ? 'review_eligible') and not (public.get_offline_preparation_status((current_setting('m42.live')::jsonb->>'preparation_id')::uuid) ? 'decision'),'status no review oracle');
select throws_ok($test$select public.complete_offline_preparation((current_setting('m42.live')::jsonb->>'preparation_id')::uuid,0)$test$,'22023');
select throws_ok($test$select public.complete_offline_preparation((current_setting('m42.live')::jsonb->>'preparation_id')::uuid,-1)$test$,'22023');
select throws_ok($test$select public.complete_offline_preparation((current_setting('m42.live')::jsonb->>'preparation_id')::uuid,null)$test$,'22023');
select throws_ok($test$select public.get_offline_preparation_status(null)$test$,'22023');
select set_config('m42.done',(public.complete_offline_preparation((current_setting('m42.live')::jsonb->>'preparation_id')::uuid,1))::text,true);
select is((select current_setting('m42.done')::jsonb->>'disposition'),'completed','staff completion persisted');
select is((select current_setting('m42.done')::jsonb->>'declared_count'),'1','declared count retained');
select set_config('m42.done_replay',(public.complete_offline_preparation((current_setting('m42.live')::jsonb->>'preparation_id')::uuid,1))::text,true);
select is((select current_setting('m42.done_replay')::jsonb-'replayed'),current_setting('m42.done')::jsonb-'replayed','completion replay unchanged');
select is((select current_setting('m42.done_replay')::jsonb->>'replayed'),'true','completion replay flag');
select throws_ok($test$select public.complete_offline_preparation((current_setting('m42.live')::jsonb->>'preparation_id')::uuid,2)$test$,'23505');
select ok(public.get_offline_preparation_status((current_setting('m42.live')::jsonb->>'preparation_id')::uuid)->>'can_upload' = 'false' and public.get_offline_preparation_status((current_setting('m42.live')::jsonb->>'preparation_id')::uuid)->>'can_complete' = 'false','completion ends new uploads');
select throws_ok($test$select public.submit_offline_capture((current_setting('m42.live')::jsonb->>'preparation_id')::uuid,'d8000000-0000-4000-8000-000000000021','d4000000-0000-4000-8000-000000000003','00000000002',(current_setting('m42.live')::jsonb->>'issued_at')::timestamptz)$test$,'55000');
select set_config('m42.upload_replay',(public.submit_offline_capture((current_setting('m42.live')::jsonb->>'preparation_id')::uuid,'d8000000-0000-4000-8000-000000000020','d4000000-0000-4000-8000-000000000003','00000000001',(current_setting('m42.live')::jsonb->>'issued_at')::timestamptz))::text,true);
select is((select current_setting('m42.upload_replay')::jsonb-'replayed'),current_setting('m42.upload')::jsonb-'replayed','original upload replay after completion');
select throws_ok($test$select public.prepare_offline_capture('d3000000-0000-4000-8000-000000000002','d6000000-0000-4000-8000-000000000021')$test$,'55000');
select is((select public.prepare_offline_capture('d3000000-0000-4000-8000-000000000002','d6000000-0000-4000-8000-000000000020')->>'preparation_id'),(current_setting('m42.live')::jsonb->>'preparation_id')::uuid::text,'same prepare metadata retained');
select throws_ok($test$select public.get_event_offline_summary('d3000000-0000-4000-8000-000000000001')$test$,'42501');
select throws_ok($test$select public.review_offline_capture('d3000000-0000-4000-8000-000000000001','d8000000-0000-4000-8000-000000000001','approve','Synthetic review evidence')$test$,'42501');
select throws_ok($test$select public.seal_offline_uploads('d3000000-0000-4000-8000-000000000001')$test$,'42501');
select throws_ok($test$select public.account_offline_preparation_loss('d3000000-0000-4000-8000-000000000001','d7000000-0000-4000-8000-000000000003','missing','Synthetic device unavailable')$test$,'42501');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','d2000000-0000-4000-8000-000000000005',true);
select throws_ok($test$select public.get_offline_preparation_status((current_setting('m42.live')::jsonb->>'preparation_id')::uuid)$test$,'42501');
select throws_ok($test$select public.complete_offline_preparation((current_setting('m42.live')::jsonb->>'preparation_id')::uuid,1)$test$,'42501');
reset role;
set local role anon;
select set_config('request.jwt.claim.sub','',true);
select throws_ok($test$select public.get_offline_preparation_status('d7000000-0000-4000-8000-000000000001')$test$,'42501');
select throws_ok($test$select public.complete_offline_preparation('d7000000-0000-4000-8000-000000000001',3)$test$,'42501');
select throws_ok($test$select public.get_event_offline_summary('d3000000-0000-4000-8000-000000000001')$test$,'42501');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','d2000000-0000-4000-8000-000000000003',true);
select throws_ok($test$select public.get_event_offline_summary('d3000000-0000-4000-8000-000000000001')$test$,'42501');
select throws_ok($test$select public.seal_offline_uploads('d3000000-0000-4000-8000-000000000001')$test$,'42501');
select throws_ok($test$select public.review_offline_capture('d3000000-0000-4000-8000-000000000001','d8000000-0000-4000-8000-000000000001','approve','Synthetic review evidence')$test$,'42501');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','d2000000-0000-4000-8000-000000000007',true);
select throws_ok($test$select public.get_event_offline_summary('d3000000-0000-4000-8000-000000000001')$test$,'42501');
select throws_ok($test$select public.seal_offline_uploads('d3000000-0000-4000-8000-000000000001')$test$,'42501');
select throws_ok($test$select public.review_offline_capture('d3000000-0000-4000-8000-000000000001','d8000000-0000-4000-8000-000000000001','approve','Synthetic review evidence')$test$,'42501');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','d2000000-0000-4000-8000-000000000008',true);
select throws_ok($test$select public.get_event_offline_summary('d3000000-0000-4000-8000-000000000001')$test$,'42501');
select throws_ok($test$select public.seal_offline_uploads('d3000000-0000-4000-8000-000000000001')$test$,'42501');
select throws_ok($test$select public.review_offline_capture('d3000000-0000-4000-8000-000000000001','d8000000-0000-4000-8000-000000000001','approve','Synthetic review evidence')$test$,'42501');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','d2000000-0000-4000-8000-000000000002',true);
select throws_ok($test$select public.seal_offline_uploads('d3000000-0000-4000-8000-000000000001')$test$,'55000');
select throws_ok($test$select public.review_offline_capture('d3000000-0000-4000-8000-000000000001','d8000000-0000-4000-8000-000000000001','approve','Synthetic review evidence')$test$,'55000');
select throws_ok($test$select public.account_offline_preparation_loss('d3000000-0000-4000-8000-000000000001','d7000000-0000-4000-8000-000000000003','missing','Synthetic device unavailable')$test$,'55000');
select throws_ok($test$select public.confirm_offline_reconciliation('d3000000-0000-4000-8000-000000000001')$test$,'55000');
select throws_ok($test$select public.finalize_event('d3000000-0000-4000-8000-000000000001')$test$,'55000');
select throws_ok($test$select public.get_event_offline_summary('d3000000-0000-4000-8000-000000000006')$test$,'42501');
select throws_ok($test$select * from public.get_event_offline_claims('d3000000-0000-4000-8000-000000000001',201,0)$test$,'22023');
select throws_ok($test$select * from public.get_event_offline_preparations('d3000000-0000-4000-8000-000000000001',1,-1)$test$,'22023');
select throws_ok($test$select * from public.offline_claim_reviews$test$,'42501');
select throws_ok($test$select * from public.offline_preparation_accounting$test$,'42501');
select throws_ok($test$select * from public.offline_upload_seals$test$,'42501');
select throws_ok($test$select * from public.offline_reconciliation_confirmations$test$,'42501');
select throws_ok($test$select public.review_offline_capture('d3000000-0000-4000-8000-000000000001','d8000000-0000-4000-8000-000000000001','approve','   ')$test$,'22023');
select throws_ok($test$select public.account_offline_preparation_loss('d3000000-0000-4000-8000-000000000001','d7000000-0000-4000-8000-000000000003','missing',repeat('x',501))$test$,'22023');
select throws_ok($test$select public.account_offline_preparation_loss('d3000000-0000-4000-8000-000000000001','d7000000-0000-4000-8000-000000000003','completed','Synthetic device unavailable')$test$,'22023');
select is((select public.close_event('d3000000-0000-4000-8000-000000000001')->>'event_state'),'SYNCING','close 1');
select is((select public.close_event('d3000000-0000-4000-8000-000000000003')->>'event_state'),'SYNCING','close 3');
select is((select public.close_event('d3000000-0000-4000-8000-000000000004')->>'event_state'),'SYNCING','close 4');
select is((select public.close_event('d3000000-0000-4000-8000-000000000005')->>'event_state'),'SYNCING','close 5');
select throws_ok($test$select public.seal_offline_uploads('d3000000-0000-4000-8000-000000000003')$test$,'55000');
select throws_ok($test$select public.seal_offline_uploads('d3000000-0000-4000-8000-000000000005')$test$,'55000');
select is((select public.finalize_event('d3000000-0000-4000-8000-000000000005')->>'record_count'),'3','online-only finalization preserved');
select set_config('m42.online_final',(public.finalize_event('d3000000-0000-4000-8000-000000000005'))::text,true);
select is((select current_setting('m42.online_final')::jsonb->>'replayed'),'true','online-only finalized replay');
select throws_ok($test$select public.finalize_event('d3000000-0000-4000-8000-000000000004')$test$,'55000');
select set_config('m42.zero_seal',(public.seal_offline_uploads('d3000000-0000-4000-8000-000000000004'))::text,true);
select throws_ok($test$select public.finalize_event('d3000000-0000-4000-8000-000000000004')$test$,'55000');
select ok(public.get_event_offline_summary('d3000000-0000-4000-8000-000000000004')->>'can_confirm' = 'true','zero sessions ready to confirm only after seal');
select set_config('m42.zero_confirm',(public.confirm_offline_reconciliation('d3000000-0000-4000-8000-000000000004'))::text,true);
select is((select public.finalize_event('d3000000-0000-4000-8000-000000000004')->>'record_count'),'3','zero sessions still need explicit confirmation');
select set_config('m42.seal',(public.seal_offline_uploads('d3000000-0000-4000-8000-000000000001'))::text,true);
select is((select current_setting('m42.seal')::jsonb->>'replayed'),'false','cutoff seal');
select set_config('m42.seal_replay',(public.seal_offline_uploads('d3000000-0000-4000-8000-000000000001'))::text,true);
select is((select current_setting('m42.seal_replay')::jsonb-'replayed'),current_setting('m42.seal')::jsonb-'replayed','seal original audit');
select throws_ok($test$select public.confirm_offline_reconciliation('d3000000-0000-4000-8000-000000000001')$test$,'55000');
select throws_ok($test$select public.finalize_event('d3000000-0000-4000-8000-000000000001')$test$,'55000');
select is((select public.get_event_offline_summary('d3000000-0000-4000-8000-000000000001')->>'unaccounted_count'),'3','all known sessions require accounting');
select is((select public.get_event_offline_summary('d3000000-0000-4000-8000-000000000001')->>'unreviewed_count'),'5','all submitted claims require review');
select is((select count(*)::int from public.get_event_offline_preparations('d3000000-0000-4000-8000-000000000001',2,0)),2,'session page one');
select is((select count(*)::int from public.get_event_offline_preparations('d3000000-0000-4000-8000-000000000001',2,2)),1,'session page two');
select is((select count(*)::int from public.get_event_offline_claims('d3000000-0000-4000-8000-000000000001',2,4)),1,'claim final page');
select throws_ok($test$select public.review_offline_capture('d3000000-0000-4000-8000-000000000001','d8000000-0000-4000-8000-000000000099','approve','Synthetic review evidence')$test$,'42501');
select throws_ok($test$select public.account_offline_preparation_loss('d3000000-0000-4000-8000-000000000001',(current_setting('m42.live')::jsonb->>'preparation_id')::uuid,'missing','Synthetic device unavailable')$test$,'42501');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','d2000000-0000-4000-8000-000000000004',true);
select set_config('m42.historical_replay',(public.submit_offline_capture('d7000000-0000-4000-8000-000000000001','d8000000-0000-4000-8000-000000000001','d4000000-0000-4000-8000-000000000001','00000000001',now()-interval '27 hours'))::text,true);
select is((select current_setting('m42.historical_replay')::jsonb->>'replayed'),'true','authorized identical replay after seal');
select throws_ok($test$select public.submit_offline_capture('d7000000-0000-4000-8000-000000000001','d8000000-0000-4000-8000-000000000022','d4000000-0000-4000-8000-000000000001','00000000001',now()-interval '27 hours')$test$,'55000');
select set_config('m42.historic_done',(public.complete_offline_preparation('d7000000-0000-4000-8000-000000000001',3))::text,true);
select is((select current_setting('m42.historic_done')::jsonb->>'uploaded_count'),'3','completion after seal accounts actual durable claims');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','d2000000-0000-4000-8000-000000000002',true);
select throws_ok($test$select public.account_offline_preparation_loss('d3000000-0000-4000-8000-000000000001','d7000000-0000-4000-8000-000000000001','missing','Synthetic device unavailable')$test$,'23505');
select ok(public.revoke_event_staff('d5000000-0000-4000-8000-000000000002') is not null,'revoke before review');
select set_config('m42.loss',(public.account_offline_preparation_loss('d3000000-0000-4000-8000-000000000001','d7000000-0000-4000-8000-000000000002','revoked','Synthetic revoked session'))::text,true);
select is((select current_setting('m42.loss')::jsonb->>'uploaded_count'),'2','loss preserves observed upload count');
select ok(current_setting('m42.loss')::jsonb->'declared_count' = 'null'::jsonb,'loss never fabricates declaration');
select set_config('m42.loss_replay',(public.account_offline_preparation_loss('d3000000-0000-4000-8000-000000000001','d7000000-0000-4000-8000-000000000002','revoked','Synthetic revoked session'))::text,true);
select is((select current_setting('m42.loss_replay')::jsonb-'replayed'),current_setting('m42.loss')::jsonb-'replayed','loss replay original audit');
select throws_ok($test$select public.account_offline_preparation_loss('d3000000-0000-4000-8000-000000000001','d7000000-0000-4000-8000-000000000002','lost','Synthetic device unavailable')$test$,'23505');
select set_config('m42.missing',(public.account_offline_preparation_loss('d3000000-0000-4000-8000-000000000001','d7000000-0000-4000-8000-000000000003','missing','Synthetic device unavailable'))::text,true);
select is((select current_setting('m42.missing')::jsonb->>'uploaded_count'),'0','missing zero uploads explicit');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','d2000000-0000-4000-8000-000000000006',true);
select throws_ok($test$select public.complete_offline_preparation('d7000000-0000-4000-8000-000000000003',0)$test$,'23505');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','d2000000-0000-4000-8000-000000000005',true);
select throws_ok($test$select public.complete_offline_preparation('d7000000-0000-4000-8000-000000000002',2)$test$,'42501');
select throws_ok($test$select public.get_offline_preparation_status('d7000000-0000-4000-8000-000000000002')$test$,'42501');
select throws_ok($test$select public.submit_offline_capture('d7000000-0000-4000-8000-000000000002','d8000000-0000-4000-8000-000000000003','d4000000-0000-4000-8000-000000000001','00000000002',now()-interval '27 hours')$test$,'42501');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','d2000000-0000-4000-8000-000000000002',true);
select throws_ok($test$select public.confirm_offline_reconciliation('d3000000-0000-4000-8000-000000000001')$test$,'55000');
select throws_ok($test$select public.review_offline_capture('d3000000-0000-4000-8000-000000000001','d8000000-0000-4000-8000-000000000004','approve','Synthetic review evidence')$test$,'55000');
select throws_ok($test$select public.review_offline_capture('d3000000-0000-4000-8000-000000000001','d8000000-0000-4000-8000-000000000005','approve','Synthetic review evidence')$test$,'55000');
select set_config('m42.duplicate',(public.review_offline_capture('d3000000-0000-4000-8000-000000000001','d8000000-0000-4000-8000-000000000001','approve','Synthetic review evidence'))::text,true);
select is((select current_setting('m42.duplicate')::jsonb->>'receipt_outcome'),'duplicate','existing online accepted slot duplicate');
select set_config('m42.duplicate_replay',(public.review_offline_capture('d3000000-0000-4000-8000-000000000001','d8000000-0000-4000-8000-000000000001','approve','Synthetic review evidence'))::text,true);
select is((select current_setting('m42.duplicate_replay')::jsonb-'replayed'),current_setting('m42.duplicate')::jsonb-'replayed','review replay unchanged');
select throws_ok($test$select public.review_offline_capture('d3000000-0000-4000-8000-000000000001','d8000000-0000-4000-8000-000000000001','reject','Synthetic review evidence')$test$,'23505');
select throws_ok($test$select public.review_offline_capture('d3000000-0000-4000-8000-000000000001','d8000000-0000-4000-8000-000000000001','approve','Different reason')$test$,'23505');
reset role;
create function public.m42_test_reject_review() returns trigger language plpgsql as $$
begin raise exception 'Synthetic forced review failure' using errcode='22023'; end;
$$;
create trigger m42_test_review_rollback before insert on public.offline_claim_reviews
for each row execute function public.m42_test_reject_review();
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','d2000000-0000-4000-8000-000000000002',true);
select throws_ok($test$select public.review_offline_capture('d3000000-0000-4000-8000-000000000001','d8000000-0000-4000-8000-000000000002','approve','Synthetic review evidence')$test$,'22023');
reset role;
select is((select count(*)::int from public.attendance_scans where offline_capture_id='d8000000-0000-4000-8000-000000000002'),0,'failed review rolls back promoted receipt');
select is((select count(*)::int from public.offline_claim_reviews where capture_id='d8000000-0000-4000-8000-000000000002'),0,'failed review leaves no decision');
drop trigger m42_test_review_rollback on public.offline_claim_reviews;
drop function public.m42_test_reject_review();
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','d2000000-0000-4000-8000-000000000002',true);
select set_config('m42.accepted',(public.review_offline_capture('d3000000-0000-4000-8000-000000000001','d8000000-0000-4000-8000-000000000002','approve','Synthetic review evidence'))::text,true);
select is((select current_setting('m42.accepted')::jsonb->>'receipt_outcome'),'accepted','eligible claim promoted');
select set_config('m42.revoked_review',(public.review_offline_capture('d3000000-0000-4000-8000-000000000001','d8000000-0000-4000-8000-000000000003','approve','Synthetic review evidence'))::text,true);
select is((select current_setting('m42.revoked_review')::jsonb->>'receipt_outcome'),'accepted','submitted revoked claim reviewable');
select set_config('m42.reject',(public.review_offline_capture('d3000000-0000-4000-8000-000000000001','d8000000-0000-4000-8000-000000000004','reject','Synthetic non-roster claim'))::text,true);
select ok(current_setting('m42.reject')::jsonb->'receipt_id' = 'null'::jsonb,'rejection creates no receipt');
select throws_ok($test$select public.confirm_offline_reconciliation('d3000000-0000-4000-8000-000000000001')$test$,'55000');
select throws_ok($test$select public.finalize_event('d3000000-0000-4000-8000-000000000001')$test$,'55000');
select set_config('m42.reject2',(public.review_offline_capture('d3000000-0000-4000-8000-000000000001','d8000000-0000-4000-8000-000000000005','reject','Synthetic untrusted capture time'))::text,true);
select ok(public.get_event_offline_summary('d3000000-0000-4000-8000-000000000001')->>'can_confirm' = 'true' and public.get_event_offline_summary('d3000000-0000-4000-8000-000000000001')->>'can_finalize' = 'false','all accounted still requires confirmation');
select throws_ok($test$select public.finalize_event('d3000000-0000-4000-8000-000000000001')$test$,'55000');
reset role;
select is((select count(*)::int from public.attendance_scans where event_id='d3000000-0000-4000-8000-000000000001' and source='offline'),3,'one receipt per approved claim');
select is((select count(*)::int from public.attendance_scans where event_id='d3000000-0000-4000-8000-000000000001' and outcome='accepted'),3,'single canonical accepted slot');
select is((select count(*)::int from public.attendance_scans where event_id='d3000000-0000-4000-8000-000000000001' and source='online'),1,'original online row unchanged');
select ok((select s.scan_id<>c.capture_id and s.received_at=c.received_at and s.submitted_by=p.staff_user_id from public.attendance_scans s join public.offline_capture_claims c on c.capture_id=s.offline_capture_id join public.offline_preparations p on p.id=c.preparation_id where s.scan_id=(current_setting('m42.accepted')::jsonb->>'receipt_id')::uuid),'promotion provenance original staff and trusted upload time');
select throws_ok($test$update public.offline_claim_reviews set reason='changed' where capture_id='d8000000-0000-4000-8000-000000000001'$test$,'42501');
select throws_ok($test$delete from public.offline_preparation_accounting where preparation_id='d7000000-0000-4000-8000-000000000001'$test$,'42501');
select throws_ok($test$update public.offline_upload_seals set sealed_at=now() where event_id='d3000000-0000-4000-8000-000000000001'$test$,'42501');
select throws_ok($test$update public.attendance_scans set source='online' where scan_id=(current_setting('m42.accepted')::jsonb->>'receipt_id')::uuid$test$,'42501');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','d2000000-0000-4000-8000-000000000004',true);
select is((select count(*)::int from public.attendance_scans where event_id='d3000000-0000-4000-8000-000000000001' and source='offline'),0,'staff cannot read promoted offline raw receipts');
select throws_ok($test$select public.ingest_attendance_scan((current_setting('m42.accepted')::jsonb->>'receipt_id')::uuid,'d3000000-0000-4000-8000-000000000001','d4000000-0000-4000-8000-000000000002','00000000001')$test$,'23505');
select is((select public.ingest_attendance_scan('d8000000-0000-4000-8000-000000000010','d3000000-0000-4000-8000-000000000001','d4000000-0000-4000-8000-000000000001','00000000001')->>'replayed'),'true','old online receipt replay unaffected');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','d2000000-0000-4000-8000-000000000002',true);
select is((select count(*)::int from public.get_event_checkpoint_coverage('d3000000-0000-4000-8000-000000000001') where has_accepted_scan),3,'coverage canonical accepted only');
select set_config('m42.confirm',(public.confirm_offline_reconciliation('d3000000-0000-4000-8000-000000000001'))::text,true);
select ok(public.get_event_offline_summary('d3000000-0000-4000-8000-000000000001')->>'can_finalize' = 'true','explicit confirmation opens finalization gate');
select set_config('m42.final',(public.finalize_event('d3000000-0000-4000-8000-000000000001'))::text,true);
select is((select current_setting('m42.final')::jsonb->>'record_count'),'3','one immutable result per roster');
select is((select status from public.get_event_finalized_results('d3000000-0000-4000-8000-000000000001') where student_id='00000000001'),'PRESENT','online and approved offline all checkpoints');
select is((select status from public.get_event_finalized_results('d3000000-0000-4000-8000-000000000001') where student_id='00000000002'),'INCOMPLETE','one approved checkpoint');
select is((select status from public.get_event_finalized_results('d3000000-0000-4000-8000-000000000001') where student_id='00000000003'),'ABSENT','rejected and missing evidence do not count');
select set_config('m42.final_replay',(public.finalize_event('d3000000-0000-4000-8000-000000000001'))::text,true);
select is((select current_setting('m42.final_replay')::jsonb-'replayed'),current_setting('m42.final')::jsonb-'replayed','final replay original metadata');
select set_config('m42.confirm_replay',(public.confirm_offline_reconciliation('d3000000-0000-4000-8000-000000000001'))::text,true);
select is((select current_setting('m42.confirm_replay')::jsonb-'replayed'),current_setting('m42.confirm')::jsonb-'replayed','confirmation replay after finalized');
select set_config('m42.review_final_replay',(public.review_offline_capture('d3000000-0000-4000-8000-000000000001','d8000000-0000-4000-8000-000000000002','approve','Synthetic review evidence'))::text,true);
select is((select current_setting('m42.review_final_replay')::jsonb-'replayed'),current_setting('m42.accepted')::jsonb-'replayed','review replay after finalized');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','d2000000-0000-4000-8000-000000000004',true);
select is((select public.submit_offline_capture('d7000000-0000-4000-8000-000000000001','d8000000-0000-4000-8000-000000000001','d4000000-0000-4000-8000-000000000001','00000000001',now()-interval '27 hours')->>'replayed'),'true','original upload replay after finalization');
select throws_ok($test$select public.submit_offline_capture('d7000000-0000-4000-8000-000000000001','d8000000-0000-4000-8000-000000000099','d4000000-0000-4000-8000-000000000001','00000000001',now()-interval '27 hours')$test$,'55000');
select is((select public.complete_offline_preparation('d7000000-0000-4000-8000-000000000001',3)->>'replayed'),'true','completion replay after finalized');
reset role;
select throws_ok($test$delete from public.offline_reconciliation_confirmations where event_id='d3000000-0000-4000-8000-000000000001'$test$,'42501');
select is((select count(*)::int from public.offline_capture_claims where event_id='d3000000-0000-4000-8000-000000000001'),5,'claim history unchanged');
select is((select count(*)::int from public.offline_claim_reviews r join public.offline_capture_claims c on c.capture_id=r.capture_id where c.event_id='d3000000-0000-4000-8000-000000000001'),5,'one immutable decision per claim');
select * from finish();
rollback;
