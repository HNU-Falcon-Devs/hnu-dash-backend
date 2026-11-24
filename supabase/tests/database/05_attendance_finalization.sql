begin;
-- M3.2A synthetic fixtures; all changes rolled back.
select plan(118);

insert into auth.users(id,instance_id,aud,role,email,email_confirmed_at,created_at,updated_at)
values
 ('92000000-0000-4000-8000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','admin-finalization@hnu.edu.ph',now(),now(),now()),
 ('92000000-0000-4000-8000-000000000002','00000000-0000-0000-0000-000000000000','authenticated','authenticated','leader-finalization@hnu.edu.ph',now(),now(),now()),
 ('92000000-0000-4000-8000-000000000003','00000000-0000-0000-0000-000000000000','authenticated','authenticated','other-leader-finalization@hnu.edu.ph',now(),now(),now()),
 ('92000000-0000-4000-8000-000000000004','00000000-0000-0000-0000-000000000000','authenticated','authenticated','staff-finalization@hnu.edu.ph',now(),now(),now()),
 ('92000000-0000-4000-8000-000000000005','00000000-0000-0000-0000-000000000000','authenticated','authenticated','unverified-finalization@hnu.edu.ph',null,now(),now()),
 ('92000000-0000-4000-8000-000000000006','00000000-0000-0000-0000-000000000000','authenticated','authenticated','wrong-domain@example.org',now(),now(),now()),
 ('92000000-0000-4000-8000-000000000007','00000000-0000-0000-0000-000000000000','authenticated','authenticated','inactive-finalization@hnu.edu.ph',now(),now(),now()),
 ('92000000-0000-4000-8000-000000000008','00000000-0000-0000-0000-000000000000','authenticated','authenticated','student-finalization@hnu.edu.ph',now(),now(),now());
insert into public.platform_admins(user_id)
values ('92000000-0000-4000-8000-000000000001');
insert into public.organizations(id,slug,name) values
 ('91000000-0000-4000-8000-000000000001','finalization-one','Finalization One'),
 ('91000000-0000-4000-8000-000000000002','finalization-two','Finalization Two');
insert into public.organization_memberships(organization_id,user_id,role,active,granted_by) values
 ('91000000-0000-4000-8000-000000000001','92000000-0000-4000-8000-000000000002','leader',true,'92000000-0000-4000-8000-000000000001'),
 ('91000000-0000-4000-8000-000000000002','92000000-0000-4000-8000-000000000003','leader',true,'92000000-0000-4000-8000-000000000001'),
 ('91000000-0000-4000-8000-000000000001','92000000-0000-4000-8000-000000000004','staff',true,'92000000-0000-4000-8000-000000000001'),
 ('91000000-0000-4000-8000-000000000001','92000000-0000-4000-8000-000000000005','leader',true,'92000000-0000-4000-8000-000000000001'),
 ('91000000-0000-4000-8000-000000000001','92000000-0000-4000-8000-000000000006','leader',true,'92000000-0000-4000-8000-000000000001'),
 ('91000000-0000-4000-8000-000000000001','92000000-0000-4000-8000-000000000007','leader',false,'92000000-0000-4000-8000-000000000001');
insert into public.students(student_id,full_name,program_code,year_level)
select lpad(n::text,11,'0'), 'Synthetic Finalization ' || n, 'BSIT', 1
from generate_series(1,600) as n;

insert into public.events(id,organization_id,created_by,title,starts_at,ends_at) values
 ('93000000-0000-4000-8000-000000000001','91000000-0000-4000-8000-000000000001','92000000-0000-4000-8000-000000000001','Synthetic finalization 1',now()-interval '3 hours',now()+interval '3 hours'),
 ('93000000-0000-4000-8000-000000000002','91000000-0000-4000-8000-000000000001','92000000-0000-4000-8000-000000000001','Synthetic finalization 2',now()-interval '3 hours',now()+interval '3 hours'),
 ('93000000-0000-4000-8000-000000000003','91000000-0000-4000-8000-000000000001','92000000-0000-4000-8000-000000000001','Synthetic finalization 3',now()-interval '3 hours',now()+interval '3 hours'),
 ('93000000-0000-4000-8000-000000000004','91000000-0000-4000-8000-000000000002','92000000-0000-4000-8000-000000000001','Synthetic finalization 4',now()-interval '3 hours',now()+interval '3 hours'),
 ('93000000-0000-4000-8000-000000000005','91000000-0000-4000-8000-000000000001','92000000-0000-4000-8000-000000000001','Synthetic finalization 5',now()-interval '3 hours',now()+interval '3 hours'),
 ('93000000-0000-4000-8000-000000000006','91000000-0000-4000-8000-000000000001','92000000-0000-4000-8000-000000000001','Synthetic finalization 6',now()-interval '3 hours',now()+interval '3 hours'),
 ('93000000-0000-4000-8000-000000000007','91000000-0000-4000-8000-000000000001','92000000-0000-4000-8000-000000000001','Synthetic finalization 7',now()-interval '3 hours',now()+interval '3 hours');
select set_config('request.jwt.claim.sub','92000000-0000-4000-8000-000000000001',true);
insert into public.event_checkpoints(id,event_id,label,direction,opens_at,closes_at,sort_order) values
 ('94000000-0000-4000-8000-000000000001','93000000-0000-4000-8000-000000000001','Checkpoint 1','IN',now()-interval '2 hours',now()-interval '1 hour',1),
 ('94000000-0000-4000-8000-000000000002','93000000-0000-4000-8000-000000000001','Checkpoint 2','OUT',now()-interval '2 hours',now()-interval '1 hour',2),
 ('94000000-0000-4000-8000-000000000003','93000000-0000-4000-8000-000000000001','Checkpoint 3','IN',now()-interval '2 hours',now()-interval '1 hour',3),
 ('94000000-0000-4000-8000-000000000004','93000000-0000-4000-8000-000000000001','Checkpoint 4','OUT',now()-interval '2 hours',now()-interval '1 hour',4),
 ('94000000-0000-4000-8000-000000000005','93000000-0000-4000-8000-000000000002','Checkpoint 5','IN',now()-interval '2 hours',now()-interval '1 hour',5),
 ('94000000-0000-4000-8000-000000000006','93000000-0000-4000-8000-000000000003','Checkpoint 6','IN',now()-interval '2 hours',now()-interval '1 hour',6),
 ('94000000-0000-4000-8000-000000000007','93000000-0000-4000-8000-000000000004','Checkpoint 7','IN',now()-interval '2 hours',now()-interval '1 hour',7),
 ('94000000-0000-4000-8000-000000000008','93000000-0000-4000-8000-000000000005','Checkpoint 8','IN',now()-interval '2 hours',now()-interval '1 hour',8),
 ('94000000-0000-4000-8000-000000000009','93000000-0000-4000-8000-000000000005','Checkpoint 9','OUT',now()-interval '2 hours',now()+interval '1 hour',9),
 ('94000000-0000-4000-8000-000000000010','93000000-0000-4000-8000-000000000006','Checkpoint 10','IN',now()-interval '2 hours',now()-interval '1 hour',10);
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','92000000-0000-4000-8000-000000000001',true);
select is((select public.freeze_event_roster('93000000-0000-4000-8000-000000000001')),600,'freeze event 1');
select is((select public.freeze_event_roster('93000000-0000-4000-8000-000000000002')),600,'freeze event 2');
select is((select public.freeze_event_roster('93000000-0000-4000-8000-000000000004')),600,'freeze event 4');
select is((select public.freeze_event_roster('93000000-0000-4000-8000-000000000005')),600,'freeze event 5');
select is((select public.freeze_event_roster('93000000-0000-4000-8000-000000000006')),600,'freeze event 6');
select is((select event_state from public.open_event('93000000-0000-4000-8000-000000000001')),'OPEN','open event 1');
select is((select event_state from public.open_event('93000000-0000-4000-8000-000000000002')),'OPEN','open event 2');
select is((select event_state from public.open_event('93000000-0000-4000-8000-000000000004')),'OPEN','open event 4');
select is((select event_state from public.open_event('93000000-0000-4000-8000-000000000005')),'OPEN','open event 5');
select is((select event_state from public.open_event('93000000-0000-4000-8000-000000000006')),'OPEN','open event 6');
select ok(public.assign_event_staff('93000000-0000-4000-8000-000000000001','92000000-0000-4000-8000-000000000004') is not null,'Staff is genuinely assigned');
reset role;
insert into public.attendance_scans(scan_id,event_id,checkpoint_id,student_id,submitted_by,received_at,outcome) values
 ('95000000-0000-4000-8000-000000000001','93000000-0000-4000-8000-000000000001','94000000-0000-4000-8000-000000000001','00000000001','92000000-0000-4000-8000-000000000004',now()-interval '90 minutes','accepted'),
 ('95000000-0000-4000-8000-000000000002','93000000-0000-4000-8000-000000000001','94000000-0000-4000-8000-000000000002','00000000001','92000000-0000-4000-8000-000000000004',now()-interval '90 minutes','accepted'),
 ('95000000-0000-4000-8000-000000000003','93000000-0000-4000-8000-000000000001','94000000-0000-4000-8000-000000000003','00000000001','92000000-0000-4000-8000-000000000004',now()-interval '90 minutes','accepted'),
 ('95000000-0000-4000-8000-000000000004','93000000-0000-4000-8000-000000000001','94000000-0000-4000-8000-000000000004','00000000001','92000000-0000-4000-8000-000000000004',now()-interval '90 minutes','accepted'),
 ('95000000-0000-4000-8000-000000000005','93000000-0000-4000-8000-000000000001','94000000-0000-4000-8000-000000000001','00000000002','92000000-0000-4000-8000-000000000004',now()-interval '90 minutes','accepted'),
 ('95000000-0000-4000-8000-000000000006','93000000-0000-4000-8000-000000000001','94000000-0000-4000-8000-000000000002','00000000002','92000000-0000-4000-8000-000000000004',now()-interval '90 minutes','duplicate'),
 ('95000000-0000-4000-8000-000000000007','93000000-0000-4000-8000-000000000001','94000000-0000-4000-8000-000000000003','00000000003','92000000-0000-4000-8000-000000000004',now()-interval '90 minutes','rejected'),
 ('95000000-0000-4000-8000-000000000008','93000000-0000-4000-8000-000000000001','94000000-0000-4000-8000-000000000004','00000000004','92000000-0000-4000-8000-000000000004',now()-interval '90 minutes','duplicate'),
 ('95000000-0000-4000-8000-000000000009','93000000-0000-4000-8000-000000000002','94000000-0000-4000-8000-000000000005','00000000001','92000000-0000-4000-8000-000000000004',now()-interval '90 minutes','accepted'),
 ('95000000-0000-4000-8000-000000000010','93000000-0000-4000-8000-000000000002','94000000-0000-4000-8000-000000000005','00000000002','92000000-0000-4000-8000-000000000004',now()-interval '90 minutes','rejected'),
 ('95000000-0000-4000-8000-000000000011','93000000-0000-4000-8000-000000000001','94000000-0000-4000-8000-000000000005','00000000005','92000000-0000-4000-8000-000000000004',now()-interval '90 minutes','accepted'),
 ('95000000-0000-4000-8000-000000000012','93000000-0000-4000-8000-000000000001','94000000-0000-4000-8000-000000000001','00000000999','92000000-0000-4000-8000-000000000004',now()-interval '90 minutes','accepted');
-- Malformed operator-only fixtures prove missing prerequisites fail closed.
update public.events set state='OPEN',opened_at=now() where id='93000000-0000-4000-8000-000000000007';
update public.events set state='OPEN',opened_at=now(),roster_frozen_at=now() where id='93000000-0000-4000-8000-000000000003';
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','92000000-0000-4000-8000-000000000002',true);
select throws_ok($test$select public.finalize_event('93000000-0000-4000-8000-000000000001')$test$,'55000');
select throws_ok($test$select * from public.get_event_finalized_results('93000000-0000-4000-8000-000000000001')$test$,'55000');
select throws_ok($test$select public.close_event('93000000-0000-4000-8000-000000000005')$test$,'55000');
select throws_ok($test$select public.close_event('93000000-0000-4000-8000-000000000003')$test$,'22023');
select throws_ok($test$select public.close_event('93000000-0000-4000-8000-000000000007')$test$,'22023');
select throws_ok($test$select public.close_event('93000000-0000-4000-8000-000000000004')$test$,'42501');
select throws_ok($test$select public.finalize_event('93000000-0000-4000-8000-000000000004')$test$,'42501');
select throws_ok($test$select * from public.get_event_finalized_results('93000000-0000-4000-8000-000000000004')$test$,'42501');
select throws_ok($test$select public.close_event(null)$test$,'22023');
select throws_ok($test$select public.finalize_event(null)$test$,'22023');
select throws_ok($test$select public.get_event_finalized_results(null)$test$,'22023');
select throws_ok($test$select * from public.get_event_finalized_results('93000000-0000-4000-8000-000000000001',0,0)$test$,'22023');
select throws_ok($test$select * from public.get_event_finalized_results('93000000-0000-4000-8000-000000000001',201,0)$test$,'22023');
select throws_ok($test$select * from public.get_event_finalized_results('93000000-0000-4000-8000-000000000001',200,-1)$test$,'22023');
select throws_ok($test$select * from public.get_event_finalized_results('93000000-0000-4000-8000-000000000001',null,0)$test$,'22023');
select throws_ok($test$select * from public.get_event_finalized_results('93000000-0000-4000-8000-000000000001',200,null)$test$,'22023');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','92000000-0000-4000-8000-000000000003',true);
select throws_ok($test$select public.close_event('93000000-0000-4000-8000-000000000001')$test$,'42501');
select throws_ok($test$select public.finalize_event('93000000-0000-4000-8000-000000000001')$test$,'42501');
select throws_ok($test$select public.get_event_finalized_results('93000000-0000-4000-8000-000000000001')$test$,'42501');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','92000000-0000-4000-8000-000000000004',true);
select throws_ok($test$select public.close_event('93000000-0000-4000-8000-000000000001')$test$,'42501');
select throws_ok($test$select public.finalize_event('93000000-0000-4000-8000-000000000001')$test$,'42501');
select throws_ok($test$select public.get_event_finalized_results('93000000-0000-4000-8000-000000000001')$test$,'42501');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','92000000-0000-4000-8000-000000000005',true);
select throws_ok($test$select public.close_event('93000000-0000-4000-8000-000000000001')$test$,'42501');
select throws_ok($test$select public.finalize_event('93000000-0000-4000-8000-000000000001')$test$,'42501');
select throws_ok($test$select public.get_event_finalized_results('93000000-0000-4000-8000-000000000001')$test$,'42501');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','92000000-0000-4000-8000-000000000006',true);
select throws_ok($test$select public.close_event('93000000-0000-4000-8000-000000000001')$test$,'42501');
select throws_ok($test$select public.finalize_event('93000000-0000-4000-8000-000000000001')$test$,'42501');
select throws_ok($test$select public.get_event_finalized_results('93000000-0000-4000-8000-000000000001')$test$,'42501');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','92000000-0000-4000-8000-000000000007',true);
select throws_ok($test$select public.close_event('93000000-0000-4000-8000-000000000001')$test$,'42501');
select throws_ok($test$select public.finalize_event('93000000-0000-4000-8000-000000000001')$test$,'42501');
select throws_ok($test$select public.get_event_finalized_results('93000000-0000-4000-8000-000000000001')$test$,'42501');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','92000000-0000-4000-8000-000000000008',true);
select throws_ok($test$select public.close_event('93000000-0000-4000-8000-000000000001')$test$,'42501');
select throws_ok($test$select public.finalize_event('93000000-0000-4000-8000-000000000001')$test$,'42501');
select throws_ok($test$select public.get_event_finalized_results('93000000-0000-4000-8000-000000000001')$test$,'42501');
reset role;
set local role anon;
select set_config('request.jwt.claim.sub','',true);
select throws_ok($test$select public.close_event('93000000-0000-4000-8000-000000000001')$test$,'42501');
select throws_ok($test$select public.finalize_event('93000000-0000-4000-8000-000000000001')$test$,'42501');
select throws_ok($test$select public.get_event_finalized_results('93000000-0000-4000-8000-000000000001')$test$,'42501');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','92000000-0000-4000-8000-000000000002',true);
select throws_ok($test$select public.close_event('93000000-0000-4000-8000-000000000099')$test$,'42501');
select throws_ok($test$select public.finalize_event('93000000-0000-4000-8000-000000000099')$test$,'42501');
select throws_ok($test$select public.get_event_finalized_results('93000000-0000-4000-8000-000000000099')$test$,'42501');
select is((select public.close_event('93000000-0000-4000-8000-000000000001')->>'event_state'),'SYNCING','leader closes event');
select is((select closed_by from public.events where id='93000000-0000-4000-8000-000000000001'),'92000000-0000-4000-8000-000000000002'::uuid,'closure captures authenticated actor');
select ok((select closed_at >= opened_at from public.events where id='93000000-0000-4000-8000-000000000001'),'closure captures server time');
select throws_ok($test$select public.close_event('93000000-0000-4000-8000-000000000001')$test$,'55000');
select throws_ok($test$select * from public.get_event_finalized_results('93000000-0000-4000-8000-000000000001')$test$,'55000');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','92000000-0000-4000-8000-000000000004',true);
select is((select public.ingest_attendance_scan('95000000-0000-4000-8000-000000000001','93000000-0000-4000-8000-000000000001','94000000-0000-4000-8000-000000000001','00000000001')->>'replayed'),'true','SYNCING permits identical authorized receipt replay');
select throws_ok($test$select public.ingest_attendance_scan('95000000-0000-4000-8000-000000000099','93000000-0000-4000-8000-000000000001','94000000-0000-4000-8000-000000000001','00000000001')$test$,'55000');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','92000000-0000-4000-8000-000000000002',true);
select is((select public.finalize_event('93000000-0000-4000-8000-000000000001')->>'record_count'),'600','one result per frozen student');
select is((select state from public.events where id='93000000-0000-4000-8000-000000000001'),'FINALIZED','event and results finalize together');
select is((select finalized_by from public.events where id='93000000-0000-4000-8000-000000000001'),'92000000-0000-4000-8000-000000000002'::uuid,'finalization actor preserved');
select ok((select finalized_at >= closed_at from public.events where id='93000000-0000-4000-8000-000000000001'),'finalization timestamp follows closure');
select is((select status from public.get_event_finalized_results('93000000-0000-4000-8000-000000000001') where student_id='00000000001'),'PRESENT','student 1 status');
select is((select accepted_checkpoint_count from public.get_event_finalized_results('93000000-0000-4000-8000-000000000001') where student_id='00000000001'),4,'student 1 accepted count');
select is((select status from public.get_event_finalized_results('93000000-0000-4000-8000-000000000001') where student_id='00000000002'),'INCOMPLETE','student 2 status');
select is((select accepted_checkpoint_count from public.get_event_finalized_results('93000000-0000-4000-8000-000000000001') where student_id='00000000002'),1,'student 2 accepted count');
select is((select status from public.get_event_finalized_results('93000000-0000-4000-8000-000000000001') where student_id='00000000003'),'ABSENT','student 3 status');
select is((select accepted_checkpoint_count from public.get_event_finalized_results('93000000-0000-4000-8000-000000000001') where student_id='00000000003'),0,'student 3 accepted count');
select is((select status from public.get_event_finalized_results('93000000-0000-4000-8000-000000000001') where student_id='00000000004'),'ABSENT','student 4 status');
select is((select accepted_checkpoint_count from public.get_event_finalized_results('93000000-0000-4000-8000-000000000001') where student_id='00000000004'),0,'student 4 accepted count');
select is((select status from public.get_event_finalized_results('93000000-0000-4000-8000-000000000001') where student_id='00000000005'),'ABSENT','student 5 status');
select is((select accepted_checkpoint_count from public.get_event_finalized_results('93000000-0000-4000-8000-000000000001') where student_id='00000000005'),0,'student 5 accepted count');
select is((select count(*)::int from public.get_event_finalized_results('93000000-0000-4000-8000-000000000001')),200,'default page bounded');
select is((select student_id from public.get_event_finalized_results('93000000-0000-4000-8000-000000000001',1,200)),'00000000201','stable leading-zero page ordering');
select is((select count(*)::int from public.get_event_finalized_results('93000000-0000-4000-8000-000000000001',200,600)),0,'beyond end returns empty page');
select is((select count(distinct r.student_id)::int from generate_series(0,2) p(n) cross join lateral public.get_event_finalized_results('93000000-0000-4000-8000-000000000001',200,p.n*200) r),600,'three pages cover exactly 600 students');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','92000000-0000-4000-8000-000000000001',true);
select is((select public.finalize_event('93000000-0000-4000-8000-000000000001')->>'replayed'),'true','authorized admin retry replays');
select is((select public.finalize_event('93000000-0000-4000-8000-000000000001')->>'finalized_by'),'92000000-0000-4000-8000-000000000002','retry preserves original actor');
select is((select public.finalize_event('93000000-0000-4000-8000-000000000001')->>'record_count'),'600','retry preserves stored count');
select is((select public.finalize_event('93000000-0000-4000-8000-000000000001')->>'finalized_at'),(select to_jsonb(finalized_at)#>>'{}' from public.events where id='93000000-0000-4000-8000-000000000001'),'retry preserves original timestamp');
select is((select public.close_event('93000000-0000-4000-8000-000000000002')->>'event_state'),'SYNCING','admin closes IN-only event');
select is((select public.finalize_event('93000000-0000-4000-8000-000000000002')->>'record_count'),'600','admin finalizes IN-only event');
select is((select status from public.get_event_finalized_results('93000000-0000-4000-8000-000000000002') where student_id='00000000001'),'PRESENT','IN-only accepted evidence is PRESENT');
select is((select status from public.get_event_finalized_results('93000000-0000-4000-8000-000000000002') where student_id='00000000002'),'ABSENT','IN-only rejected evidence is ABSENT');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','92000000-0000-4000-8000-000000000004',true);
select is((select public.ingest_attendance_scan('95000000-0000-4000-8000-000000000001','93000000-0000-4000-8000-000000000001','94000000-0000-4000-8000-000000000001','00000000001')->>'replayed'),'true','FINALIZED permits identical authorized receipt replay');
select throws_ok($test$select public.ingest_attendance_scan('95000000-0000-4000-8000-000000000099','93000000-0000-4000-8000-000000000001','94000000-0000-4000-8000-000000000001','00000000001')$test$,'55000');
select throws_ok($test$select * from public.get_event_finalized_results('93000000-0000-4000-8000-000000000001')$test$,'42501');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','92000000-0000-4000-8000-000000000002',true);
select throws_ok($test$select * from public.attendance_records$test$,'42501');
select ok(not has_table_privilege('authenticated','public.attendance_records','INSERT'),'no direct record insert');
select ok(not has_table_privilege('authenticated','public.events','UPDATE'),'no direct event update');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','92000000-0000-4000-8000-000000000001',true);
select is((select public.close_event('93000000-0000-4000-8000-000000000006')->>'event_state'),'SYNCING','rollback fixture closes');
reset role;
create function public.synthetic_finalization_fail() returns trigger language plpgsql as $$
begin
  if new.student_id = '00000000002' then
    raise exception 'Synthetic forced failure' using errcode='23514';
  end if;
  return new;
end; $$;
create trigger synthetic_finalization_failure before insert on public.attendance_records
for each row when (new.event_id = '93000000-0000-4000-8000-000000000006'::uuid)
execute function public.synthetic_finalization_fail();
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','92000000-0000-4000-8000-000000000001',true);
select throws_ok($test$select public.finalize_event('93000000-0000-4000-8000-000000000006')$test$,'23514');
reset role;
select is((select count(*)::int from public.attendance_records where event_id='93000000-0000-4000-8000-000000000006'),0,'failure rolls back every result');
select is((select state from public.events where id='93000000-0000-4000-8000-000000000006'),'SYNCING','failure leaves event closed');
select ok((select finalized_at is null and finalized_by is null from public.events where id='93000000-0000-4000-8000-000000000006'),'failure leaves no final audit');
drop trigger synthetic_finalization_failure on public.attendance_records;
drop function public.synthetic_finalization_fail();
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','92000000-0000-4000-8000-000000000001',true);
select is((select public.finalize_event('93000000-0000-4000-8000-000000000006')->>'record_count'),'600','retry after rollback succeeds');
reset role;
select throws_ok($test$update public.attendance_records set status='ABSENT' where event_id='93000000-0000-4000-8000-000000000001'$test$,'42501');
select throws_ok($test$delete from public.attendance_records where event_id='93000000-0000-4000-8000-000000000001'$test$,'42501');
select throws_ok($test$update public.events set finalized_by='92000000-0000-4000-8000-000000000001' where id='93000000-0000-4000-8000-000000000001'$test$,'42501');
select throws_ok($test$update public.events set closed_at=closed_at+interval '1 second' where id='93000000-0000-4000-8000-000000000001'$test$,'42501');
select throws_ok($test$update public.attendance_scans set outcome='rejected' where event_id='93000000-0000-4000-8000-000000000001'$test$,'42501');
select throws_ok($test$delete from public.attendance_scans where event_id='93000000-0000-4000-8000-000000000001'$test$,'42501');
select is((select count(*)::int from public.attendance_scans),12,'all immutable receipts survive finalization');
select is((select count(*)::int from public.attendance_records where event_id='93000000-0000-4000-8000-000000000001'),600,'records remain unique after retries');
-- Exercise an exact two-checkpoint event and separate prerequisite failures.
select set_config('request.jwt.claim.sub','92000000-0000-4000-8000-000000000001',true);
insert into public.events(id,organization_id,created_by,title,starts_at,ends_at) values
 ('93000000-0000-4000-8000-000000000008','91000000-0000-4000-8000-000000000001','92000000-0000-4000-8000-000000000001','Two Checkpoint Event',now()-interval '3 hours',now()+interval '3 hours'),
 ('93000000-0000-4000-8000-000000000009','91000000-0000-4000-8000-000000000001','92000000-0000-4000-8000-000000000001','Draft Event',now()-interval '3 hours',now()+interval '3 hours');
insert into public.event_checkpoints(id,event_id,label,direction,opens_at,closes_at) values
 ('94000000-0000-4000-8000-000000000011','93000000-0000-4000-8000-000000000008','First IN','IN',now()-interval '2 hours',now()-interval '1 hour'),
 ('94000000-0000-4000-8000-000000000012','93000000-0000-4000-8000-000000000008','Second OUT','OUT',now()-interval '2 hours',now()-interval '1 hour');
insert into public.event_roster(event_id,student_id,student_name,program_code,year_level,frozen_at)
values ('93000000-0000-4000-8000-000000000007','00000000001','Synthetic no-checkpoint fixture','BSIT',1,now());
update public.events set roster_frozen_at=now() where id='93000000-0000-4000-8000-000000000007';
set local role authenticated;
select throws_ok($test$select public.close_event('93000000-0000-4000-8000-000000000009')$test$,'55000');
select throws_ok($test$select public.finalize_event('93000000-0000-4000-8000-000000000009')$test$,'55000');
select throws_ok($test$select public.close_event('93000000-0000-4000-8000-000000000007')$test$,'22023');
select is(public.freeze_event_roster('93000000-0000-4000-8000-000000000008'),600,'two checkpoint event freezes');
select is((select event_state from public.open_event('93000000-0000-4000-8000-000000000008')),'OPEN','two checkpoint event opens');
reset role;
insert into public.attendance_scans(scan_id,event_id,checkpoint_id,student_id,submitted_by,received_at,outcome) values
 ('95000000-0000-4000-8000-000000000013','93000000-0000-4000-8000-000000000008','94000000-0000-4000-8000-000000000011','00000000001','92000000-0000-4000-8000-000000000004',now()-interval '90 minutes','accepted'),
 ('95000000-0000-4000-8000-000000000014','93000000-0000-4000-8000-000000000008','94000000-0000-4000-8000-000000000012','00000000001','92000000-0000-4000-8000-000000000004',now()-interval '90 minutes','accepted'),
 ('95000000-0000-4000-8000-000000000015','93000000-0000-4000-8000-000000000008','94000000-0000-4000-8000-000000000012','00000000002','92000000-0000-4000-8000-000000000004',now()-interval '90 minutes','accepted');
set local role authenticated;
select is(public.close_event('93000000-0000-4000-8000-000000000008')->>'event_state','SYNCING','two checkpoint event closes');
select is(public.finalize_event('93000000-0000-4000-8000-000000000008')->>'record_count','600','two checkpoint event finalizes');
select is((select status from public.get_event_finalized_results('93000000-0000-4000-8000-000000000008') where student_id='00000000001'),'PRESENT','both checkpoints accepted');
select is((select status from public.get_event_finalized_results('93000000-0000-4000-8000-000000000008') where student_id='00000000002'),'INCOMPLETE','OUT alone is incomplete for two required checkpoints');
select is((select status from public.get_event_finalized_results('93000000-0000-4000-8000-000000000008') where student_id='00000000003'),'ABSENT','no accepted checkpoints');
select is((select required_checkpoint_count from public.get_event_finalized_results('93000000-0000-4000-8000-000000000008') where student_id='00000000001'),2,'two configured checkpoints required');
reset role;
select throws_ok($test$insert into public.attendance_records values ('93000000-0000-4000-8000-000000000008','00000000001','PRESENT',2,2)$test$,'23505');
select throws_ok($test$insert into public.attendance_records values ('93000000-0000-4000-8000-000000000008','00000000999','ABSENT',2,0)$test$,'23503');
select throws_ok($test$insert into public.attendance_records values ('93000000-0000-4000-8000-000000000009','00000000001','PRESENT',2,0)$test$,'23514');

select * from finish();
rollback;
