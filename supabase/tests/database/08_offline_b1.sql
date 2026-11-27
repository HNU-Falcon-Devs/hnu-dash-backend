-- Synthetic fixture-only B1 contract tests. All data rolls back.
begin;
select plan(113);
set local timezone='UTC';
insert into auth.users(id,instance_id,aud,role,email,email_confirmed_at,created_at,updated_at) values
 ('f7200000-0000-4000-8000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','b1-synthetic-0@hnu.edu.ph',now(),now(),now()),
 ('f7200000-0000-4000-8000-000000000002','00000000-0000-0000-0000-000000000000','authenticated','authenticated','b1-synthetic-1@hnu.edu.ph',now(),now(),now()),
 ('f7200000-0000-4000-8000-000000000003','00000000-0000-0000-0000-000000000000','authenticated','authenticated','b1-synthetic-2@hnu.edu.ph',now(),now(),now()),
 ('f7200000-0000-4000-8000-000000000004','00000000-0000-0000-0000-000000000000','authenticated','authenticated','b1-synthetic-3@hnu.edu.ph',now(),now(),now()),
 ('f7200000-0000-4000-8000-000000000005','00000000-0000-0000-0000-000000000000','authenticated','authenticated','b1-synthetic-4@hnu.edu.ph',null,now(),now()),
 ('f7200000-0000-4000-8000-000000000006','00000000-0000-0000-0000-000000000000','authenticated','authenticated','b1-synthetic-5@hnu.edu.ph',now(),now(),now()),
 ('f7200000-0000-4000-8000-000000000007','00000000-0000-0000-0000-000000000000','authenticated','authenticated','b1-synthetic-6@hnu.edu.ph',now(),now(),now());
insert into public.platform_admins(user_id) values ('f7200000-0000-4000-8000-000000000001');
insert into public.organizations(id,slug,name) values ('f7100000-0000-4000-8000-000000000001','b1-synthetic','B1 synthetic'),('f7100000-0000-4000-8000-000000000002','b1-other','B1 other');
insert into public.organization_memberships(organization_id,user_id,role,active,granted_by) values
 ('f7100000-0000-4000-8000-000000000001','f7200000-0000-4000-8000-000000000002','leader',true,'f7200000-0000-4000-8000-000000000001'),
 ('f7100000-0000-4000-8000-000000000001','f7200000-0000-4000-8000-000000000003','staff',true,'f7200000-0000-4000-8000-000000000001'),
 ('f7100000-0000-4000-8000-000000000002','f7200000-0000-4000-8000-000000000004','staff',true,'f7200000-0000-4000-8000-000000000001'),
 ('f7100000-0000-4000-8000-000000000001','f7200000-0000-4000-8000-000000000005','staff',true,'f7200000-0000-4000-8000-000000000001'),
 ('f7100000-0000-4000-8000-000000000001','f7200000-0000-4000-8000-000000000006','staff',true,'f7200000-0000-4000-8000-000000000001'),
 ('f7100000-0000-4000-8000-000000000002','f7200000-0000-4000-8000-000000000007','leader',true,'f7200000-0000-4000-8000-000000000001');
insert into public.students(student_id,full_name,program_code,year_level) values ('B1-SYNTHETIC-001','B1 synthetic student','BSIT',1);
insert into public.events(id,organization_id,created_by,title,starts_at,ends_at,policy_version) values
 ('f7300000-0000-4000-8000-000000000001','f7100000-0000-4000-8000-000000000001','f7200000-0000-4000-8000-000000000001','B1 fixture 1','2090-01-01 09:00Z','2090-01-01 14:00Z',2),
 ('f7300000-0000-4000-8000-000000000002','f7100000-0000-4000-8000-000000000001','f7200000-0000-4000-8000-000000000001','B1 fixture 2','2000-01-01 09:00Z','2000-01-01 14:00Z',2),
 ('f7300000-0000-4000-8000-000000000003','f7100000-0000-4000-8000-000000000001','f7200000-0000-4000-8000-000000000001','B1 fixture 3','2000-01-01 09:00Z','2000-01-01 14:00Z',2),
 ('f7300000-0000-4000-8000-000000000004','f7100000-0000-4000-8000-000000000001','f7200000-0000-4000-8000-000000000001','B1 fixture 4','2000-01-01 09:00Z','2000-01-01 14:00Z',2),
 ('f7300000-0000-4000-8000-000000000005','f7100000-0000-4000-8000-000000000001','f7200000-0000-4000-8000-000000000001','B1 fixture 5','2000-01-01 09:00Z','2000-01-01 14:00Z',1),
 ('f7300000-0000-4000-8000-000000000006','f7100000-0000-4000-8000-000000000001','f7200000-0000-4000-8000-000000000001','B1 fixture 6','2000-01-01 09:00Z','2000-01-01 14:00Z',2),
 ('f7300000-0000-4000-8000-000000000007','f7100000-0000-4000-8000-000000000002','f7200000-0000-4000-8000-000000000001','B1 fixture 7','2000-01-01 09:00Z','2000-01-01 14:00Z',2);
select set_config('request.jwt.claim.sub','f7200000-0000-4000-8000-000000000001',true);
insert into public.event_checkpoints(id,event_id,label,direction,opens_at,closes_at) values
 ('f7400000-0000-4000-8000-000000000001','f7300000-0000-4000-8000-000000000001','Checkpoint 1','IN','2090-01-01T10:00:00Z','2090-01-01T11:00:00Z'),
 ('f7400000-0000-4000-8000-000000000002','f7300000-0000-4000-8000-000000000001','Checkpoint 2','OUT','2090-01-01T12:00:00Z','2090-01-01T13:00:00Z'),
 ('f7400000-0000-4000-8000-000000000003','f7300000-0000-4000-8000-000000000002','Checkpoint 3','IN','2000-01-01T10:00:00Z','2000-01-01T11:00:00Z'),
 ('f7400000-0000-4000-8000-000000000004','f7300000-0000-4000-8000-000000000003','Checkpoint 4','IN','2000-01-01T10:00:00Z','2000-01-01T11:00:00Z'),
 ('f7400000-0000-4000-8000-000000000005','f7300000-0000-4000-8000-000000000004','Checkpoint 5','IN','2000-01-01T10:00:00Z','2000-01-01T11:00:00Z'),
 ('f7400000-0000-4000-8000-000000000006','f7300000-0000-4000-8000-000000000006','Checkpoint 6','IN','2000-01-01T10:00:00Z','2000-01-01T11:00:00Z'),
 ('f7400000-0000-4000-8000-000000000007','f7300000-0000-4000-8000-000000000007','Checkpoint 7','IN','2000-01-01T10:00:00Z','2000-01-01T11:00:00Z');
insert into public.event_roster(event_id,student_id,student_name,program_code,year_level,frozen_at)
select id,'B1-SYNTHETIC-001','B1 synthetic student','BSIT',1,now()-interval '96 hours' from public.events where id in ('f7300000-0000-4000-8000-000000000001','f7300000-0000-4000-8000-000000000002','f7300000-0000-4000-8000-000000000006','f7300000-0000-4000-8000-000000000007');
update public.events set roster_frozen_at=now()-interval '96 hours' where id in ('f7300000-0000-4000-8000-000000000001','f7300000-0000-4000-8000-000000000002','f7300000-0000-4000-8000-000000000004','f7300000-0000-4000-8000-000000000006','f7300000-0000-4000-8000-000000000007');
insert into public.event_staff(id,event_id,staff_user_id,assigned_by,assigned_at) values
 ('f7500000-0000-4000-8000-000000000001','f7300000-0000-4000-8000-000000000001','f7200000-0000-4000-8000-000000000003','f7200000-0000-4000-8000-000000000001',now()-interval '95 hours'),
 ('f7500000-0000-4000-8000-000000000002','f7300000-0000-4000-8000-000000000002','f7200000-0000-4000-8000-000000000003','f7200000-0000-4000-8000-000000000001',now()-interval '95 hours'),
 ('f7500000-0000-4000-8000-000000000003','f7300000-0000-4000-8000-000000000003','f7200000-0000-4000-8000-000000000003','f7200000-0000-4000-8000-000000000001',now()-interval '95 hours'),
 ('f7500000-0000-4000-8000-000000000004','f7300000-0000-4000-8000-000000000004','f7200000-0000-4000-8000-000000000003','f7200000-0000-4000-8000-000000000001',now()-interval '95 hours'),
 ('f7500000-0000-4000-8000-000000000005','f7300000-0000-4000-8000-000000000005','f7200000-0000-4000-8000-000000000003','f7200000-0000-4000-8000-000000000001',now()-interval '95 hours'),
 ('f7500000-0000-4000-8000-000000000006','f7300000-0000-4000-8000-000000000006','f7200000-0000-4000-8000-000000000003','f7200000-0000-4000-8000-000000000001',now()-interval '95 hours'),
 ('f7500000-0000-4000-8000-000000000007','f7300000-0000-4000-8000-000000000007','f7200000-0000-4000-8000-000000000004','f7200000-0000-4000-8000-000000000001',now()-interval '95 hours'),
 ('f7500000-0000-4000-8000-000000000008','f7300000-0000-4000-8000-000000000001','f7200000-0000-4000-8000-000000000005','f7200000-0000-4000-8000-000000000001',now()-interval '95 hours'),
 ('f7500000-0000-4000-8000-000000000009','f7300000-0000-4000-8000-000000000001','f7200000-0000-4000-8000-000000000006','f7200000-0000-4000-8000-000000000001',now()-interval '95 hours');
update public.events set state='OPEN',opened_at=now()-interval '72 hours' where id in ('f7300000-0000-4000-8000-000000000002','f7300000-0000-4000-8000-000000000006');
-- Privileged historical fixture only: seed a closed event with expired initial deadline,
-- not a callable production closure/seal bypass. B1 does not issue seals.
insert into offline_b1_private.closures(event_id,request_id,closed_at,closed_by,reason,overlap_acknowledged,normalized_windows,initial_deadline)
values ('f7300000-0000-4000-8000-000000000006','f7600000-0000-4000-8000-000000000060',now()-interval '48 hours','f7200000-0000-4000-8000-000000000002',null,false,'[{"checkpoint_id":"f7400000-0000-4000-8000-000000000006","opens_at":"2000-01-01T10:00:00Z","closes_at":"2000-01-01T11:00:00Z"}]',now()-interval '24 hours');
insert into offline_b1_private.effective_windows(event_id,checkpoint_id,opens_at,closes_at)
values ('f7300000-0000-4000-8000-000000000006','f7400000-0000-4000-8000-000000000006','2000-01-01T10:00:00Z','2000-01-01T11:00:00Z');
update public.events set state='SYNCING',closed_at=now()-interval '48 hours',closed_by='f7200000-0000-4000-8000-000000000002',sync_deadline=now()-interval '24 hours' where id='f7300000-0000-4000-8000-000000000006';
select ok(not has_column_privilege('authenticated','public.events','policy_version','INSERT') and not has_column_privilege('authenticated','public.events','policy_version','UPDATE'),'ordinary policy selection ACL denied');
select ok(not has_schema_privilege('authenticated','offline_b1_private','USAGE') and not has_schema_privilege('service_role','offline_b1_private','USAGE') and not has_table_privilege('authenticated','offline_b1_private.preparations','SELECT'),'private evidence inaccessible');
select ok(not has_function_privilege('anon','public.prepare_offline_capture_v2(uuid,uuid,uuid)','EXECUTE') and not has_function_privilege('service_role','public.close_event_v2(uuid,uuid,jsonb,boolean,text)','EXECUTE'),'no anon or service role successor execute grant');
select throws_ok($test$update public.events set policy_version=1 where id='f7300000-0000-4000-8000-000000000001'$test$,'42501');
select throws_ok($test$update public.events set policy_version=2 where id='f7300000-0000-4000-8000-000000000005'$test$,'42501');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','f7200000-0000-4000-8000-000000000002',true);
with inserted as (insert into public.events(organization_id,title,starts_at,ends_at) values ('f7100000-0000-4000-8000-000000000001','B1 ordinary v1','2090-01-01','2090-01-02') returning policy_version,sync_deadline)
select ok((select policy_version=1 and sync_deadline is null from inserted),'ordinary creation remains v1');
select throws_ok($test$insert into public.events(organization_id,title,starts_at,ends_at,policy_version) values ('f7100000-0000-4000-8000-000000000001','B1 denied','2090-01-01','2090-01-02',2)$test$,'42501');
select throws_ok($test$update public.events set policy_version=1 where id='f7300000-0000-4000-8000-000000000001'$test$,'42501');
select ok((select count(*) from public.events where id='f7300000-0000-4000-8000-000000000001')=0,'legacy manager cannot see fixture');
select ok(not public.can_edit_draft_event('f7300000-0000-4000-8000-000000000001'),'legacy edit helper fails closed');
select throws_ok($test$select public.update_draft_event('f7300000-0000-4000-8000-000000000001','Changed','2090-01-01','2090-01-02',array[1]::smallint[])$test$,'42501');
select throws_ok($test$select public.freeze_event_roster('f7300000-0000-4000-8000-000000000001')$test$,'42501');
select throws_ok($test$select public.assign_event_staff('f7300000-0000-4000-8000-000000000001','f7200000-0000-4000-8000-000000000006')$test$,'55000');
select throws_ok($test$select public.open_event('f7300000-0000-4000-8000-000000000001')$test$,'55000');
select throws_ok($test$select public.enable_event_offline('f7300000-0000-4000-8000-000000000001')$test$,'55000');
select throws_ok($test$insert into public.event_checkpoints(event_id,label,direction,opens_at,closes_at,sort_order) values ('f7300000-0000-4000-8000-000000000001','Denied','IN','2090-01-01T10:00:00Z','2090-01-01T11:00:00Z',9)$test$,'42501');
select throws_ok($test$select public.get_event_checkpoint_coverage('f7300000-0000-4000-8000-000000000001',10,0)$test$,'42501');
select throws_ok($test$select public.close_event_v2('f7300000-0000-4000-8000-000000000001','f7600000-0000-4000-8000-000000000020','[{"checkpoint_id":"f7400000-0000-4000-8000-000000000001","opens_at":"2090-01-01T10:00:00Z","closes_at":"2090-01-01T11:00:00Z"},{"checkpoint_id":"f7400000-0000-4000-8000-000000000002","opens_at":"2090-01-01T12:00:00Z","closes_at":"2090-01-01T13:00:00Z"}]'::jsonb,false,'DRAFT not open')$test$,'55000');
select throws_ok($test$select public.extend_event_sync_deadline_v2('f7300000-0000-4000-8000-000000000001','f7600000-0000-4000-8000-000000000030','2090-01-01T15:00:00Z','wrong state')$test$,'55000');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','f7200000-0000-4000-8000-000000000003',true);
select ok(not public.can_access_assigned_event('f7300000-0000-4000-8000-000000000001') and (select count(*) from public.event_staff where event_id='f7300000-0000-4000-8000-000000000001')=0 and (select count(*) from public.event_roster where event_id='f7300000-0000-4000-8000-000000000001')=0,'legacy Staff cannot see fixture or roster');
select throws_ok($test$select public.prepare_offline_capture('f7300000-0000-4000-8000-000000000001','f7600000-0000-4000-8000-000000000001')$test$,'55000');
select throws_ok($test$select public.prepare_offline_capture_v2('f7300000-0000-4000-8000-000000000003','f7500000-0000-4000-8000-000000000003','f7600000-0000-4000-8000-000000000003')$test$,'22023');
select throws_ok($test$select public.prepare_offline_capture_v2('f7300000-0000-4000-8000-000000000004','f7500000-0000-4000-8000-000000000004','f7600000-0000-4000-8000-000000000004')$test$,'22023');
select throws_ok($test$select public.prepare_offline_capture_v2('f7300000-0000-4000-8000-000000000005','f7500000-0000-4000-8000-000000000005','f7600000-0000-4000-8000-000000000005')$test$,'55000');
select throws_ok($test$select public.prepare_offline_capture_v2('f7300000-0000-4000-8000-000000000007','f7500000-0000-4000-8000-000000000007','f7600000-0000-4000-8000-000000000007')$test$,'42501');
select throws_ok($test$select public.prepare_offline_capture_v2('f7300000-0000-4000-8000-000000000001','f7500000-0000-4000-8000-000000000009','f7600000-0000-4000-8000-000000000009')$test$,'42501');
select set_config('b1.prep1',(public.prepare_offline_capture_v2('f7300000-0000-4000-8000-000000000001','f7500000-0000-4000-8000-000000000001','f7600000-0000-4000-8000-000000000001'))::text,true);
select ok(current_setting('b1.prep1')::jsonb->>'prepared_event_state'='DRAFT' and current_setting('b1.prep1')::jsonb->>'policy_version'='2' and not (current_setting('b1.prep1')::jsonb ?| array['expires_at','upload_cutoff','roster','upload_token']),'frozen DRAFT anchor without lease roster or token');
select set_config('b1.prep1retry',(public.prepare_offline_capture_v2('f7300000-0000-4000-8000-000000000001','f7500000-0000-4000-8000-000000000001','f7600000-0000-4000-8000-000000000001'))::text,true);
select ok((current_setting('b1.prep1retry')::jsonb->>'replayed')::boolean and (current_setting('b1.prep1retry')::jsonb-'replayed')=(current_setting('b1.prep1')::jsonb-'replayed'),'DRAFT exact replay keeps anchor');
select throws_ok($test$select public.prepare_offline_capture_v2('f7300000-0000-4000-8000-000000000001','f7500000-0000-4000-8000-000000000001','f7600000-0000-4000-8000-000000000002')$test$,'55000');
select throws_ok($test$select public.prepare_offline_capture_v2('f7300000-0000-4000-8000-000000000002','f7500000-0000-4000-8000-000000000002','f7600000-0000-4000-8000-000000000001')$test$,'23505');
select set_config('b1.prep2',(public.prepare_offline_capture_v2('f7300000-0000-4000-8000-000000000002','f7500000-0000-4000-8000-000000000002','f7600000-0000-4000-8000-000000000008'))::text,true);
select ok(current_setting('b1.prep2')::jsonb->>'prepared_event_state'='OPEN' and jsonb_array_length(current_setting('b1.prep2')::jsonb->'checkpoints')=1,'OPEN preparation beyond planned schedule');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','f7200000-0000-4000-8000-000000000006',true);
select throws_ok($test$select public.prepare_offline_capture_v2('f7300000-0000-4000-8000-000000000001','f7500000-0000-4000-8000-000000000001','f7600000-0000-4000-8000-000000000001')$test$,'42501');
select throws_ok($test$select public.prepare_offline_capture_v2('f7300000-0000-4000-8000-000000000001','f7500000-0000-4000-8000-000000000009','f7600000-0000-4000-8000-000000000001')$test$,'42501');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','f7200000-0000-4000-8000-000000000005',true);
select throws_ok($test$select public.prepare_offline_capture_v2('f7300000-0000-4000-8000-000000000001','f7500000-0000-4000-8000-000000000008','f7600000-0000-4000-8000-000000000010')$test$,'42501');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','f7200000-0000-4000-8000-000000000004',true);
select throws_ok($test$select public.prepare_offline_capture_v2('f7300000-0000-4000-8000-000000000001','f7500000-0000-4000-8000-000000000001','f7600000-0000-4000-8000-000000000001')$test$,'42501');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','f7200000-0000-4000-8000-000000000002',true);
select throws_ok($test$select public.prepare_offline_capture_v2('f7300000-0000-4000-8000-000000000001','f7500000-0000-4000-8000-000000000001','f7600000-0000-4000-8000-000000000001')$test$,'42501');
reset role;
set local role anon;
select set_config('request.jwt.claim.sub','',true);
select throws_ok($test$select public.prepare_offline_capture_v2('f7300000-0000-4000-8000-000000000001','f7500000-0000-4000-8000-000000000001','f7600000-0000-4000-8000-000000000001')$test$,'42501');
select throws_ok($test$select public.close_event_v2('f7300000-0000-4000-8000-000000000001','f7600000-0000-4000-8000-000000000020','[{"checkpoint_id":"f7400000-0000-4000-8000-000000000001","opens_at":"2090-01-01T10:00:00Z","closes_at":"2090-01-01T11:00:00Z"},{"checkpoint_id":"f7400000-0000-4000-8000-000000000002","opens_at":"2090-01-01T12:00:00Z","closes_at":"2090-01-01T13:00:00Z"}]'::jsonb,false,'anonymous')$test$,'42501');
reset role;
select ok((select state='DRAFT' and opened_at is null from public.events where id='f7300000-0000-4000-8000-000000000001'),'preparation does not activate event');
update public.events set state='OPEN',opened_at=clock_timestamp() where id='f7300000-0000-4000-8000-000000000001';
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','f7200000-0000-4000-8000-000000000003',true);
select set_config('b1.prep1retry',(public.prepare_offline_capture_v2('f7300000-0000-4000-8000-000000000001','f7500000-0000-4000-8000-000000000001','f7600000-0000-4000-8000-000000000001'))::text,true);
select ok((current_setting('b1.prep1retry')::jsonb->>'replayed')::boolean and (current_setting('b1.prep1retry')::jsonb-'replayed')=(current_setting('b1.prep1')::jsonb-'replayed'),'OPEN retry does not reanchor DRAFT preparation');
select throws_ok($test$select public.ingest_attendance_scan('f7600000-0000-4000-8000-000000000070','f7300000-0000-4000-8000-000000000001','f7400000-0000-4000-8000-000000000001','B1-SYNTHETIC-001')$test$,'55000');
select throws_ok($test$select public.submit_offline_capture((current_setting('b1.prep1')::jsonb->>'preparation_id')::uuid,'f7600000-0000-4000-8000-000000000070','f7400000-0000-4000-8000-000000000001','B1-SYNTHETIC-001',now())$test$,'42501');
select throws_ok($test$select public.complete_offline_preparation((current_setting('b1.prep1')::jsonb->>'preparation_id')::uuid,0)$test$,'42501');
select throws_ok($test$select public.get_offline_preparation_status((current_setting('b1.prep1')::jsonb->>'preparation_id')::uuid)$test$,'42501');
select throws_ok($test$select public.close_event_v2('f7300000-0000-4000-8000-000000000001','f7600000-0000-4000-8000-000000000020','[{"checkpoint_id":"f7400000-0000-4000-8000-000000000001","opens_at":"2090-01-01T10:00:00Z","closes_at":"2090-01-01T11:00:00Z"},{"checkpoint_id":"f7400000-0000-4000-8000-000000000002","opens_at":"2090-01-01T12:00:00Z","closes_at":"2090-01-01T13:00:00Z"}]'::jsonb,false,'staff denial')$test$,'42501');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','f7200000-0000-4000-8000-000000000007',true);
select throws_ok($test$select public.close_event_v2('f7300000-0000-4000-8000-000000000001','f7600000-0000-4000-8000-000000000020','[{"checkpoint_id":"f7400000-0000-4000-8000-000000000001","opens_at":"2090-01-01T10:00:00Z","closes_at":"2090-01-01T11:00:00Z"},{"checkpoint_id":"f7400000-0000-4000-8000-000000000002","opens_at":"2090-01-01T12:00:00Z","closes_at":"2090-01-01T13:00:00Z"}]'::jsonb,false,'scope denial')$test$,'42501');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','f7200000-0000-4000-8000-000000000002',true);
select throws_ok($test$select public.close_event('f7300000-0000-4000-8000-000000000001')$test$,'55000');
select throws_ok($test$select public.close_event_v2('f7300000-0000-4000-8000-000000000001','f7600000-0000-4000-8000-000000000020','[{"checkpoint_id":"f7400000-0000-4000-8000-000000000001","opens_at":"2090-01-01T10:00:00Z","closes_at":"2090-01-01T11:00:00Z"},{"checkpoint_id":"f7400000-0000-4000-8000-000000000002","opens_at":"2090-01-01T12:00:00Z","closes_at":"2090-01-01T13:00:00Z"}]'::jsonb,false,null)$test$,'22023');
select throws_ok($test$select public.close_event_v2('f7300000-0000-4000-8000-000000000001','f7600000-0000-4000-8000-000000000020','[{"checkpoint_id":"f7400000-0000-4000-8000-000000000001","opens_at":"2090-01-01T08:00:00Z","closes_at":"2090-01-01T12:30:00Z"},{"checkpoint_id":"f7400000-0000-4000-8000-000000000002","opens_at":"2090-01-01T12:00:00Z","closes_at":"2090-01-01T13:00:00Z"}]'::jsonb,false,'extend')$test$,'22023');
select throws_ok($test$select public.close_event_v2('f7300000-0000-4000-8000-000000000001','f7600000-0000-4000-8000-000000000020','[{"checkpoint_id":"f7400000-0000-4000-8000-000000000001","opens_at":"2090-01-01T08:00:00Z","closes_at":"2090-01-01T12:30:00Z"},{"checkpoint_id":"f7400000-0000-4000-8000-000000000002","opens_at":"2090-01-01T12:00:00Z","closes_at":"2090-01-01T13:00:00Z"}]'::jsonb,true,null)$test$,'22023');
select throws_ok($test$select public.close_event_v2('f7300000-0000-4000-8000-000000000001','f7600000-0000-4000-8000-000000000020','[{"checkpoint_id":"f7400000-0000-4000-8000-000000000001","opens_at":"2090-01-01T10:00:00Z","closes_at":"2090-01-01T11:00:00Z"}]'::jsonb,false,'missing')$test$,'22023');
select throws_ok($test$select public.close_event_v2('f7300000-0000-4000-8000-000000000001','f7600000-0000-4000-8000-000000000020','[{"checkpoint_id":"f7400000-0000-4000-8000-000000000001","opens_at":"2090-01-01T10:00:00Z","closes_at":"2090-01-01T11:00:00Z"},{"checkpoint_id":"f7400000-0000-4000-8000-000000000001","opens_at":"2090-01-01T10:00:00Z","closes_at":"2090-01-01T11:00:00Z"}]'::jsonb,false,'duplicate')$test$,'22023');
select throws_ok($test$select public.close_event_v2('f7300000-0000-4000-8000-000000000001','f7600000-0000-4000-8000-000000000020','[{"checkpoint_id":"f7400000-0000-4000-8000-000000000001","opens_at":"2090-01-01T10:00:00Z","closes_at":"2090-01-01T11:00:00Z"},{"checkpoint_id":"f7400000-0000-4000-8000-000000000003","opens_at":"2000-01-01T10:00:00Z","closes_at":"2000-01-01T11:00:00Z"}]'::jsonb,false,'foreign')$test$,'22023');
select throws_ok($test$select public.close_event_v2('f7300000-0000-4000-8000-000000000001','f7600000-0000-4000-8000-000000000020','[{"checkpoint_id":"f7400000-0000-4000-8000-000000000001","opens_at":"2090-01-01T10:00:00Z","closes_at":"2090-01-01T11:00:00Z"},{"checkpoint_id":"f7400000-0000-4000-8000-000000000002","opens_at":"2090-01-01T12:00:00Z","closes_at":"2090-01-01T13:00:00Z"},{"checkpoint_id":"f7400000-0000-4000-8000-000000000003","opens_at":"2000-01-01T10:00:00Z","closes_at":"2000-01-01T11:00:00Z"}]'::jsonb,true,'extra')$test$,'22023');
select throws_ok($test$select public.close_event_v2('f7300000-0000-4000-8000-000000000001','f7600000-0000-4000-8000-000000000020','[{"checkpoint_id":"f7400000-0000-4000-8000-000000000001","opens_at":"2090-01-01T10:01:00Z","closes_at":"2090-01-01T11:00:00Z"},{"checkpoint_id":"f7400000-0000-4000-8000-000000000002","opens_at":"2090-01-01T12:00:00Z","closes_at":"2090-01-01T13:00:00Z"}]'::jsonb,false,'shorten start')$test$,'22023');
select throws_ok($test$select public.close_event_v2('f7300000-0000-4000-8000-000000000001','f7600000-0000-4000-8000-000000000020','[{"checkpoint_id":"f7400000-0000-4000-8000-000000000001","opens_at":"2090-01-01T10:00:00Z","closes_at":"2090-01-01T10:59:00Z"},{"checkpoint_id":"f7400000-0000-4000-8000-000000000002","opens_at":"2090-01-01T12:00:00Z","closes_at":"2090-01-01T13:00:00Z"}]'::jsonb,false,'shorten end')$test$,'22023');
select throws_ok($test$select public.close_event_v2('f7300000-0000-4000-8000-000000000001','f7600000-0000-4000-8000-000000000020','[{"checkpoint_id":"f7400000-0000-4000-8000-000000000001","opens_at":"-infinity","closes_at":"2090-01-01T11:00:00Z"},{"checkpoint_id":"f7400000-0000-4000-8000-000000000002","opens_at":"2090-01-01T12:00:00Z","closes_at":"2090-01-01T13:00:00Z"}]'::jsonb,false,'infinity')$test$,'22023');
select throws_ok($test$select public.close_event_v2('f7300000-0000-4000-8000-000000000001','f7600000-0000-4000-8000-000000000020','[{"checkpoint_id":"f7400000-0000-4000-8000-000000000001","opens_at":"2090-01-01T10:00:00","closes_at":"2090-01-01T11:00:00Z"},{"checkpoint_id":"f7400000-0000-4000-8000-000000000002","opens_at":"2090-01-01T12:00:00Z","closes_at":"2090-01-01T13:00:00Z"}]'::jsonb,false,'offset')$test$,'22023');
select throws_ok($test$select public.close_event_v2('f7300000-0000-4000-8000-000000000001','f7600000-0000-4000-8000-000000000020','[{"checkpoint_id":"invalid","opens_at":"2090-01-01T10:00:00Z","closes_at":"2090-01-01T11:00:00Z"},{"checkpoint_id":"f7400000-0000-4000-8000-000000000002","opens_at":"2090-01-01T12:00:00Z","closes_at":"2090-01-01T13:00:00Z"}]'::jsonb,false,'invalid uuid')$test$,'22023');
select throws_ok($test$select public.close_event_v2('f7300000-0000-4000-8000-000000000001','f7600000-0000-4000-8000-000000000020','[{"checkpoint_id":"f7400000-0000-4000-8000-000000000001","opens_at":"2090-99-01T10:00:00Z","closes_at":"2090-01-01T11:00:00Z"},{"checkpoint_id":"f7400000-0000-4000-8000-000000000002","opens_at":"2090-01-01T12:00:00Z","closes_at":"2090-01-01T13:00:00Z"}]'::jsonb,false,'invalid date')$test$,'22023');
select throws_ok($test$select public.close_event_v2('f7300000-0000-4000-8000-000000000001','f7600000-0000-4000-8000-000000000020','[{"checkpoint_id":"f7400000-0000-4000-8000-000000000001","opens_at":"2090-01-01T10:00:00Z","closes_at":"2090-01-01T11:00:00Z","extra":true},{"checkpoint_id":"f7400000-0000-4000-8000-000000000002","opens_at":"2090-01-01T12:00:00Z","closes_at":"2090-01-01T13:00:00Z"}]'::jsonb,false,'extra key')$test$,'22023');
select throws_ok($test$select public.close_event_v2('f7300000-0000-4000-8000-000000000001','f7600000-0000-4000-8000-000000000020','{}'::jsonb,false,'bad type')$test$,'22023');
reset role;
select ok((select state='OPEN' and closed_at is null and sync_deadline is null from public.events where id='f7300000-0000-4000-8000-000000000001') and not exists(select 1 from offline_b1_private.closures where event_id='f7300000-0000-4000-8000-000000000001') and not exists(select 1 from offline_b1_private.effective_windows where event_id='f7300000-0000-4000-8000-000000000001'),'failed closures leave no partial effects');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','f7200000-0000-4000-8000-000000000002',true);
select set_config('b1.close1',(public.close_event_v2('f7300000-0000-4000-8000-000000000001','f7600000-0000-4000-8000-000000000020','[{"checkpoint_id":"f7400000-0000-4000-8000-000000000001","opens_at":"2090-01-01T08:00:00Z","closes_at":"2090-01-01T12:30:00Z"},{"checkpoint_id":"f7400000-0000-4000-8000-000000000002","opens_at":"2090-01-01T12:00:00Z","closes_at":"2090-01-01T13:00:00Z"}]'::jsonb,true,'  early extension  '))::text,true);
select ok(current_setting('b1.close1')::jsonb->>'event_state'='SYNCING' and current_setting('b1.close1')::jsonb->>'reason'='early extension' and (current_setting('b1.close1')::jsonb->>'initial_sync_deadline')::timestamptz-(current_setting('b1.close1')::jsonb->>'closed_at')::timestamptz=interval '24 hours','manual close initial elapsed deadline');
select set_config('b1.close1retry',(public.close_event_v2('f7300000-0000-4000-8000-000000000001','f7600000-0000-4000-8000-000000000020','[{"checkpoint_id":"f7400000-0000-4000-8000-000000000002","opens_at":"2090-01-01T12:00:00Z","closes_at":"2090-01-01T13:00:00Z"},{"checkpoint_id":"f7400000-0000-4000-8000-000000000001","opens_at":"2090-01-01T16:00:00+08:00","closes_at":"2090-01-01T20:30:00+08:00"}]'::jsonb,true,'early extension'))::text,true);
select ok((current_setting('b1.close1retry')::jsonb->>'replayed')::boolean and (current_setting('b1.close1retry')::jsonb-'replayed')=(current_setting('b1.close1')::jsonb-'replayed'),'normalized exact closure replay');
select throws_ok($test$select public.close_event_v2('f7300000-0000-4000-8000-000000000001','f7600000-0000-4000-8000-000000000021','[{"checkpoint_id":"f7400000-0000-4000-8000-000000000001","opens_at":"2090-01-01T08:00:00Z","closes_at":"2090-01-01T12:30:00Z"},{"checkpoint_id":"f7400000-0000-4000-8000-000000000002","opens_at":"2090-01-01T12:00:00Z","closes_at":"2090-01-01T13:00:00Z"}]'::jsonb,true,'early extension')$test$,'23505');
select throws_ok($test$select public.close_event_v2('f7300000-0000-4000-8000-000000000001','f7600000-0000-4000-8000-000000000020','[{"checkpoint_id":"f7400000-0000-4000-8000-000000000001","opens_at":"2090-01-01T08:00:00Z","closes_at":"2090-01-01T12:30:00Z"},{"checkpoint_id":"f7400000-0000-4000-8000-000000000002","opens_at":"2090-01-01T12:00:00Z","closes_at":"2090-01-01T13:00:00Z"}]'::jsonb,true,'changed')$test$,'23505');
reset role;
select ok((select state='SYNCING' and closed_by='f7200000-0000-4000-8000-000000000002' and closed_at<=clock_timestamp() and closed_at>=opened_at and sync_deadline=closed_at+interval '24 hours' from public.events where id='f7300000-0000-4000-8000-000000000001'),'server closure metadata persisted atomically');
select ok((select opens_at='2090-01-01T10:00:00Z' and closes_at='2090-01-01T11:00:00Z' from public.event_checkpoints where id='f7400000-0000-4000-8000-000000000001') and (select opens_at='2090-01-01T08:00:00Z' and closes_at='2090-01-01T12:30:00Z' from offline_b1_private.effective_windows where event_id='f7300000-0000-4000-8000-000000000001' and checkpoint_id='f7400000-0000-4000-8000-000000000001') and (select count(*) from offline_b1_private.effective_windows where event_id='f7300000-0000-4000-8000-000000000001')=2,'original schedule unchanged and complete effective mapping');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','f7200000-0000-4000-8000-000000000001',true);
select set_config('b1.close2',(public.close_event_v2('f7300000-0000-4000-8000-000000000002','f7600000-0000-4000-8000-000000000022','[{"checkpoint_id":"f7400000-0000-4000-8000-000000000003","opens_at":"2000-01-01T10:00:00Z","closes_at":"2000-01-01T11:00:00Z"}]'::jsonb,false,null))::text,true);
select ok(current_setting('b1.close2')::jsonb->>'closed_by'='f7200000-0000-4000-8000-000000000001','authorized platform Admin can close overrun');
select throws_ok($test$select public.extend_event_sync_deadline_v2('f7300000-0000-4000-8000-000000000001','f7600000-0000-4000-8000-000000000030',(current_setting('b1.close1')::jsonb->>'closed_at')::timestamptz+interval '48 hours','admin only')$test$,'42501');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','f7200000-0000-4000-8000-000000000007',true);
select throws_ok($test$select public.extend_event_sync_deadline_v2('f7300000-0000-4000-8000-000000000001','f7600000-0000-4000-8000-000000000030',(current_setting('b1.close1')::jsonb->>'closed_at')::timestamptz+interval '48 hours','scope')$test$,'42501');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','f7200000-0000-4000-8000-000000000003',true);
select throws_ok($test$select public.extend_event_sync_deadline_v2('f7300000-0000-4000-8000-000000000001','f7600000-0000-4000-8000-000000000030',(current_setting('b1.close1')::jsonb->>'closed_at')::timestamptz+interval '48 hours','staff')$test$,'42501');
select set_config('b1.prep1retry',(public.prepare_offline_capture_v2('f7300000-0000-4000-8000-000000000001','f7500000-0000-4000-8000-000000000001','f7600000-0000-4000-8000-000000000001'))::text,true);
select ok((current_setting('b1.prep1retry')::jsonb->>'replayed')::boolean and (current_setting('b1.prep1retry')::jsonb-'replayed')=(current_setting('b1.prep1')::jsonb-'replayed'),'authorized preparation retry after closure keeps original anchor');
select throws_ok($test$select public.prepare_offline_capture_v2('f7300000-0000-4000-8000-000000000001','f7500000-0000-4000-8000-000000000001','f7600000-0000-4000-8000-000000000012')$test$,'55000');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','f7200000-0000-4000-8000-000000000006',true);
select throws_ok($test$select public.prepare_offline_capture_v2('f7300000-0000-4000-8000-000000000001','f7500000-0000-4000-8000-000000000009','f7600000-0000-4000-8000-000000000013')$test$,'55000');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','f7200000-0000-4000-8000-000000000002',true);
select throws_ok($test$select public.extend_event_sync_deadline_v2('f7300000-0000-4000-8000-000000000001','f7600000-0000-4000-8000-000000000030',(current_setting('b1.close1')::jsonb->>'closed_at')::timestamptz+interval '24 hours','not extension')$test$,'22023');
select throws_ok($test$select public.extend_event_sync_deadline_v2('f7300000-0000-4000-8000-000000000001','f7600000-0000-4000-8000-000000000030',(current_setting('b1.close1')::jsonb->>'closed_at')::timestamptz+interval '12 hours','shorten')$test$,'22023');
select throws_ok($test$select public.extend_event_sync_deadline_v2('f7300000-0000-4000-8000-000000000001','f7600000-0000-4000-8000-000000000030',(current_setting('b1.close1')::jsonb->>'closed_at')::timestamptz+interval '169 hours','past cap')$test$,'22023');
select throws_ok($test$select public.extend_event_sync_deadline_v2('f7300000-0000-4000-8000-000000000001','f7600000-0000-4000-8000-000000000030',(current_setting('b1.close1')::jsonb->>'closed_at')::timestamptz+interval '48 hours',null)$test$,'22023');
select throws_ok($test$select public.extend_event_sync_deadline_v2('f7300000-0000-4000-8000-000000000001','f7600000-0000-4000-8000-000000000030',(current_setting('b1.close1')::jsonb->>'closed_at')::timestamptz+interval '48 hours','   ')$test$,'22023');
select throws_ok($test$select public.extend_event_sync_deadline_v2('f7300000-0000-4000-8000-000000000001','f7600000-0000-4000-8000-000000000030','infinity','infinite')$test$,'22023');
select set_config('b1.ext1',(public.extend_event_sync_deadline_v2('f7300000-0000-4000-8000-000000000001','f7600000-0000-4000-8000-000000000030',(current_setting('b1.close1')::jsonb->>'closed_at')::timestamptz+interval '48 hours','extra time'))::text,true);
select set_config('b1.ext2',(public.extend_event_sync_deadline_v2('f7300000-0000-4000-8000-000000000001','f7600000-0000-4000-8000-000000000031',(current_setting('b1.close1')::jsonb->>'closed_at')::timestamptz+interval '168 hours','cap'))::text,true);
select set_config('b1.ext1retry',(public.extend_event_sync_deadline_v2('f7300000-0000-4000-8000-000000000001','f7600000-0000-4000-8000-000000000030',(current_setting('b1.close1')::jsonb->>'closed_at')::timestamptz+interval '48 hours','extra time'))::text,true);
select ok((current_setting('b1.ext1retry')::jsonb->>'replayed')::boolean and (current_setting('b1.ext1retry')::jsonb-'replayed')=(current_setting('b1.ext1')::jsonb-'replayed'),'older extension replays original receipt after later extension');
select throws_ok($test$select public.extend_event_sync_deadline_v2('f7300000-0000-4000-8000-000000000001','f7600000-0000-4000-8000-000000000030',(current_setting('b1.close1')::jsonb->>'closed_at')::timestamptz+interval '49 hours','extra time')$test$,'23505');
select throws_ok($test$select public.extend_event_sync_deadline_v2('f7300000-0000-4000-8000-000000000001','f7600000-0000-4000-8000-000000000032',(current_setting('b1.close1')::jsonb->>'closed_at')::timestamptz+interval '168 hours 1 second','past cap')$test$,'22023');
select set_config('b1.close1retry',(public.close_event_v2('f7300000-0000-4000-8000-000000000001','f7600000-0000-4000-8000-000000000020','[{"checkpoint_id":"f7400000-0000-4000-8000-000000000001","opens_at":"2090-01-01T08:00:00Z","closes_at":"2090-01-01T12:30:00Z"},{"checkpoint_id":"f7400000-0000-4000-8000-000000000002","opens_at":"2090-01-01T12:00:00Z","closes_at":"2090-01-01T13:00:00Z"}]'::jsonb,true,'early extension'))::text,true);
select ok((current_setting('b1.close1retry')::jsonb->>'replayed')::boolean and (current_setting('b1.close1retry')::jsonb-'replayed')=(current_setting('b1.close1')::jsonb-'replayed'),'closure replay retains initial deadline after extension');
select set_config('b1.expired',(public.extend_event_sync_deadline_v2('f7300000-0000-4000-8000-000000000006','f7600000-0000-4000-8000-000000000033',now()+interval '1 hour','expired but unsealed'))::text,true);
select ok((current_setting('b1.expired')::jsonb->>'previous_deadline')::timestamptz<now() and (current_setting('b1.expired')::jsonb->>'new_deadline')::timestamptz>now(),'expired unsealed extension succeeds');
select throws_ok($test$select public.finalize_event('f7300000-0000-4000-8000-000000000001')$test$,'55000');
select throws_ok($test$select public.seal_offline_uploads('f7300000-0000-4000-8000-000000000001')$test$,'55000');
select throws_ok($test$select public.account_offline_preparation_loss('f7300000-0000-4000-8000-000000000001',(current_setting('b1.prep1')::jsonb->>'preparation_id')::uuid,'lost','test')$test$,'55000');
select throws_ok($test$select public.review_offline_capture('f7300000-0000-4000-8000-000000000001','f7600000-0000-4000-8000-000000000070','approve','test')$test$,'55000');
select throws_ok($test$select public.confirm_offline_reconciliation('f7300000-0000-4000-8000-000000000001')$test$,'55000');
select throws_ok($test$select public.get_event_offline_summary('f7300000-0000-4000-8000-000000000001')$test$,'55000');
select throws_ok($test$select public.get_event_offline_preparations('f7300000-0000-4000-8000-000000000001',10,0)$test$,'55000');
select throws_ok($test$select public.get_event_offline_claims('f7300000-0000-4000-8000-000000000001',10,0)$test$,'55000');
select throws_ok($test$select public.get_event_finalized_results('f7300000-0000-4000-8000-000000000001',10,0)$test$,'55000');
select public.revoke_event_staff('f7500000-0000-4000-8000-000000000001');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','f7200000-0000-4000-8000-000000000003',true);
select throws_ok($test$select public.prepare_offline_capture_v2('f7300000-0000-4000-8000-000000000001','f7500000-0000-4000-8000-000000000001','f7600000-0000-4000-8000-000000000001')$test$,'42501');
reset role;
insert into public.event_staff(id,event_id,staff_user_id,assigned_by) values ('f7500000-0000-4000-8000-000000000010','f7300000-0000-4000-8000-000000000001','f7200000-0000-4000-8000-000000000003','f7200000-0000-4000-8000-000000000001');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','f7200000-0000-4000-8000-000000000003',true);
select throws_ok($test$select public.prepare_offline_capture_v2('f7300000-0000-4000-8000-000000000001','f7500000-0000-4000-8000-000000000001','f7600000-0000-4000-8000-000000000001')$test$,'42501');
select throws_ok($test$select public.prepare_offline_capture_v2('f7300000-0000-4000-8000-000000000001','f7500000-0000-4000-8000-000000000010','f7600000-0000-4000-8000-000000000001')$test$,'23505');
select throws_ok($test$select public.prepare_offline_capture_v2('f7300000-0000-4000-8000-000000000001','f7500000-0000-4000-8000-000000000010','f7600000-0000-4000-8000-000000000014')$test$,'55000');
reset role;
select ok((select sync_deadline=closed_at+interval '168 hours' and state='SYNCING' from public.events where id='f7300000-0000-4000-8000-000000000001') and (select count(*) from offline_b1_private.deadline_extensions where event_id='f7300000-0000-4000-8000-000000000001')=2 and not exists(select 1 from public.offline_upload_seals where event_id in ('f7300000-0000-4000-8000-000000000001','f7300000-0000-4000-8000-000000000006')),'extension audit and no automatic seal or finalize');
-- Isolated owner-only seal marker models future sealed-state denial without a B2 RPC.
insert into public.offline_upload_seals(event_id,sealed_at,sealed_by) values ('f7300000-0000-4000-8000-000000000006',now(),'f7200000-0000-4000-8000-000000000002');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','f7200000-0000-4000-8000-000000000002',true);
select throws_ok($test$select public.extend_event_sync_deadline_v2('f7300000-0000-4000-8000-000000000006','f7600000-0000-4000-8000-000000000034',now()+interval '2 hours','sealed')$test$,'55000');
reset role;
select throws_ok($test$update offline_b1_private.deadline_extensions set reason='changed' where request_id='f7600000-0000-4000-8000-000000000030'$test$,'42501');
select throws_ok($test$delete from offline_b1_private.closures where event_id='f7300000-0000-4000-8000-000000000001'$test$,'42501');
select throws_ok($test$update offline_b1_private.effective_windows set closes_at=closes_at+interval '1 hour' where event_id='f7300000-0000-4000-8000-000000000001'$test$,'42501');
select throws_ok($test$update offline_b1_private.preparations set issued_at=now() where event_id='f7300000-0000-4000-8000-000000000001'$test$,'42501');
select throws_ok($test$update public.events set sync_deadline=closed_at+interval '48 hours' where id='f7300000-0000-4000-8000-000000000001'$test$,'55000');
select throws_ok($test$update public.events set state='FINALIZED',finalized_at=now(),finalized_by='f7200000-0000-4000-8000-000000000002' where id='f7300000-0000-4000-8000-000000000001'$test$,'55000');
select throws_ok($test$insert into public.attendance_scans(scan_id,event_id,checkpoint_id,student_id,submitted_by,outcome) values ('f7600000-0000-4000-8000-000000000070','f7300000-0000-4000-8000-000000000001','f7400000-0000-4000-8000-000000000001','B1-SYNTHETIC-001','f7200000-0000-4000-8000-000000000003','accepted')$test$,'55000');
select throws_ok($test$insert into public.attendance_records(event_id,student_id,status,required_checkpoint_count,accepted_checkpoint_count) values ('f7300000-0000-4000-8000-000000000001','B1-SYNTHETIC-001','ABSENT',2,0)$test$,'55000');
select throws_ok($test$insert into public.offline_preparations(request_id,event_id,assignment_id,staff_user_id,issued_at,expires_at) values ('f7600000-0000-4000-8000-000000000071','f7300000-0000-4000-8000-000000000001','f7500000-0000-4000-8000-000000000010','f7200000-0000-4000-8000-000000000003',now(),now()+interval '1 hour')$test$,'55000');
select throws_ok($test$insert into public.offline_capture_claims(capture_id,preparation_id,event_id,checkpoint_id,student_id,claimed_at,received_at,review_eligible) values ('f7600000-0000-4000-8000-000000000072',(current_setting('b1.prep1')::jsonb->>'preparation_id')::uuid,'f7300000-0000-4000-8000-000000000001','f7400000-0000-4000-8000-000000000001','B1-SYNTHETIC-001',now(),now(),true)$test$,'55000');
select ok(not exists(select 1 from public.attendance_scans s join public.events e on e.id=s.event_id where e.policy_version=2) and not exists(select 1 from public.attendance_records s join public.events e on e.id=s.event_id where e.policy_version=2) and not exists(select 1 from public.offline_preparations s join public.events e on e.id=s.event_id where e.policy_version=2),'no canonical receipts results or legacy leases for v2');
select * from finish();
rollback;
