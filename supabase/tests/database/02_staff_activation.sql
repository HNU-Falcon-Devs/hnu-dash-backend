begin;
-- Isolated pgTAP; no real HNU records. Roles are simulated using Supabase's JWT sub.
select plan(78);

select has_table('public','event_staff','event assignment periods are persisted');
select has_column('public','events','opened_at','events have a server activation timestamp');
select ok(not has_table_privilege('authenticated','public.event_staff','INSERT'),
  'clients cannot create event_staff rows directly');
select ok(not has_table_privilege('authenticated','public.event_staff','UPDATE'),
  'clients cannot change event_staff audit or revocation fields');
select ok(not has_table_privilege('authenticated','public.events','UPDATE'),
  'clients cannot change event lifecycle state directly');
select ok(not has_function_privilege('anon','public.assign_event_staff(uuid,uuid)','EXECUTE'),
  'anonymous users cannot invoke assignment');
select ok(not has_function_privilege('anon','public.open_event(uuid)','EXECUTE'),
  'anonymous users cannot invoke event activation');

insert into auth.users(id,instance_id,aud,role,email,email_confirmed_at,created_at,updated_at)
values
('21000000-0000-4000-8000-000000000001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','admin-m2@hnu.edu.ph',now(),now(),now()),
('21000000-0000-4000-8000-000000000002','00000000-0000-0000-0000-000000000000','authenticated','authenticated','leader-m2@hnu.edu.ph',now(),now(),now()),
('21000000-0000-4000-8000-000000000003','00000000-0000-0000-0000-000000000000','authenticated','authenticated','staff-m2@hnu.edu.ph',now(),now(),now()),
('21000000-0000-4000-8000-000000000004','00000000-0000-0000-0000-000000000000','authenticated','authenticated','other-staff-m2@hnu.edu.ph',now(),now(),now()),
('21000000-0000-4000-8000-000000000005','00000000-0000-0000-0000-000000000000','authenticated','authenticated','other-leader-m2@hnu.edu.ph',now(),now(),now()),
('21000000-0000-4000-8000-000000000006','00000000-0000-0000-0000-000000000000','authenticated','authenticated','outsider-m2@hnu.edu.ph',now(),now(),now()),
('21000000-0000-4000-8000-000000000007','00000000-0000-0000-0000-000000000000','authenticated','authenticated','unverified-staff-m2@hnu.edu.ph',null,now(),now()),
('21000000-0000-4000-8000-000000000008','00000000-0000-0000-0000-000000000000','authenticated','authenticated','inactive-staff-m2@hnu.edu.ph',now(),now(),now()),
('21000000-0000-4000-8000-000000000009','00000000-0000-0000-0000-000000000000','authenticated','authenticated','outside@example.net',now(),now(),now()),
('21000000-0000-4000-8000-000000000010','00000000-0000-0000-0000-000000000000','authenticated','authenticated','unverified-leader-m2@hnu.edu.ph',null,now(),now());

insert into public.platform_admins(user_id) values ('21000000-0000-4000-8000-000000000001');
insert into public.organizations(id,slug,name) values
 ('31000000-0000-4000-8000-000000000001','demo-m2-one','Demo M2 One'),
 ('31000000-0000-4000-8000-000000000002','demo-m2-two','Demo M2 Two');
insert into public.organization_memberships(organization_id,user_id,role,active,granted_by)
values
 ('31000000-0000-4000-8000-000000000001','21000000-0000-4000-8000-000000000002','leader',true,'21000000-0000-4000-8000-000000000001'),
 ('31000000-0000-4000-8000-000000000001','21000000-0000-4000-8000-000000000003','staff',true,'21000000-0000-4000-8000-000000000001'),
 ('31000000-0000-4000-8000-000000000001','21000000-0000-4000-8000-000000000007','staff',true,'21000000-0000-4000-8000-000000000001'),
 ('31000000-0000-4000-8000-000000000001','21000000-0000-4000-8000-000000000008','staff',false,'21000000-0000-4000-8000-000000000001'),
 ('31000000-0000-4000-8000-000000000001','21000000-0000-4000-8000-000000000009','staff',true,'21000000-0000-4000-8000-000000000001'),
 ('31000000-0000-4000-8000-000000000001','21000000-0000-4000-8000-000000000010','leader',true,'21000000-0000-4000-8000-000000000001'),
 ('31000000-0000-4000-8000-000000000002','21000000-0000-4000-8000-000000000004','staff',true,'21000000-0000-4000-8000-000000000001'),
 ('31000000-0000-4000-8000-000000000002','21000000-0000-4000-8000-000000000005','leader',true,'21000000-0000-4000-8000-000000000001');

insert into public.students(student_id,full_name,program_code,year_level)
 values ('00009990001','Synthetic Milestone Two Student','BSIT',1);
insert into public.events(id,organization_id,created_by,title,starts_at,ends_at) values
 ('41000000-0000-4000-8000-000000000001','31000000-0000-4000-8000-000000000001','21000000-0000-4000-8000-000000000001','Milestone 2 Event','2041-01-01 00:00+00','2041-01-02 00:00+00'),
 ('41000000-0000-4000-8000-000000000002','31000000-0000-4000-8000-000000000002','21000000-0000-4000-8000-000000000001','Other Organization Event','2041-01-01 00:00+00','2041-01-02 00:00+00'),
 ('41000000-0000-4000-8000-000000000003','31000000-0000-4000-8000-000000000001','21000000-0000-4000-8000-000000000001','Not Frozen','2041-01-01 00:00+00','2041-01-02 00:00+00'),
 ('41000000-0000-4000-8000-000000000004','31000000-0000-4000-8000-000000000001','21000000-0000-4000-8000-000000000001','Invalid Configuration','2041-01-01 00:00+00','2041-01-02 00:00+00');

set local role authenticated;
select set_config('request.jwt.claim.sub','21000000-0000-4000-8000-000000000001',true);
select lives_ok($test$insert into public.event_checkpoints(event_id,label,direction,opens_at,closes_at)
 values ('41000000-0000-4000-8000-000000000001','One In','IN','2041-01-01 08:00+08','2041-01-01 09:00+08')$test$,
 'admin configures a valid IN-only event');
select lives_ok($test$insert into public.event_checkpoints(event_id,label,direction,opens_at,closes_at)
 values ('41000000-0000-4000-8000-000000000002','Other In','IN','2041-01-01 08:00+08','2041-01-01 09:00+08')$test$,
 'admin configures another organization');
select lives_ok($test$insert into public.event_checkpoints(event_id,label,direction,opens_at,closes_at)
 values ('41000000-0000-4000-8000-000000000003','Draft In','IN','2041-01-01 08:00+08','2041-01-01 09:00+08')$test$,
 'unfrozen draft can have checkpoints');
select is(public.freeze_event_roster('41000000-0000-4000-8000-000000000001'),1,
 'active roster is explicitly frozen before opening');
select is(public.freeze_event_roster('41000000-0000-4000-8000-000000000002'),1,
 'other-organization roster is separately frozen');
select ok(public.assign_event_staff('41000000-0000-4000-8000-000000000002','21000000-0000-4000-8000-000000000004') is not null,
 'platform Admin assigns eligible Staff in other organization');
select is((select count(*)::int from public.event_staff where event_id='41000000-0000-4000-8000-000000000002' and revoked_at is null),
  1,'Admin assignment creates one active record');

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','21000000-0000-4000-8000-000000000002',true);
select ok(public.assign_event_staff('41000000-0000-4000-8000-000000000001','21000000-0000-4000-8000-000000000003') is not null,
 'authorized Leader assigns verified active Staff');
select is((select count(*)::int from public.event_staff where event_id='41000000-0000-4000-8000-000000000001'),1,
 'Leader can list their organization assignment');
select throws_ok($test$select public.assign_event_staff('41000000-0000-4000-8000-000000000001','21000000-0000-4000-8000-000000000003')$test$,'23505');
select throws_ok($test$select public.assign_event_staff('41000000-0000-4000-8000-000000000001','21000000-0000-4000-8000-000000000002')$test$,'22023');
select throws_ok($test$select public.assign_event_staff('41000000-0000-4000-8000-000000000001','21000000-0000-4000-8000-000000000004')$test$,'22023');
select throws_ok($test$select public.assign_event_staff('41000000-0000-4000-8000-000000000001','21000000-0000-4000-8000-000000000006')$test$,'22023');
select throws_ok($test$select public.assign_event_staff('41000000-0000-4000-8000-000000000001','21000000-0000-4000-8000-000000000007')$test$,'22023');
select throws_ok($test$select public.assign_event_staff('41000000-0000-4000-8000-000000000001','21000000-0000-4000-8000-000000000008')$test$,'22023');
select throws_ok($test$select public.assign_event_staff('41000000-0000-4000-8000-000000000001','21000000-0000-4000-8000-000000000009')$test$,'22023');
select throws_ok($test$select public.assign_event_staff('41000000-0000-4000-8000-000000000002','21000000-0000-4000-8000-000000000004')$test$,'42501');
select throws_ok($test$select public.revoke_event_staff(
  (select id from public.event_staff where event_id='41000000-0000-4000-8000-000000000002' limit 1)
)$test$,'42501');
select is((select count(*)::int from public.event_staff where event_id='41000000-0000-4000-8000-000000000002'),0,
 'RLS hides foreign organization assignment rows');
select ok(not public.can_access_assigned_event('41000000-0000-4000-8000-000000000001'),
 'Leader privileges are not derived from event_staff assignment');

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','21000000-0000-4000-8000-000000000003',true);
select ok(public.can_access_assigned_event('41000000-0000-4000-8000-000000000001'),
 'eligible assigned Staff has effective event access');
select is((select count(*)::int from public.events where id='41000000-0000-4000-8000-000000000001'),1,
 'assigned Staff can read its assigned event');
select is((select count(*)::int from public.events where id='41000000-0000-4000-8000-000000000003'),0,
 'Staff membership alone does not reveal unrelated same-org events');
select is((select count(*)::int from public.event_checkpoints where event_id='41000000-0000-4000-8000-000000000001'),1,
 'assigned Staff sees its event checkpoints');
select is((select count(*)::int from public.event_roster where event_id='41000000-0000-4000-8000-000000000001'),1,
 'assigned Staff sees only its frozen event roster');
select is((select count(*)::int from public.event_staff),1,
 'assigned Staff sees only own active assignment');
select ok(not public.can_manage_org('31000000-0000-4000-8000-000000000001'),
 'Staff assignment does not confer management rights');
select throws_ok($test$select public.assign_event_staff('41000000-0000-4000-8000-000000000001','21000000-0000-4000-8000-000000000006')$test$,'42501');
select throws_ok($test$select * from public.open_event('41000000-0000-4000-8000-000000000001')$test$,'42501');
select throws_ok($test$insert into public.events(organization_id,title,starts_at,ends_at)
 values ('31000000-0000-4000-8000-000000000001','Forbidden Staff Event','2041-01-01 00:00+00','2041-01-02 00:00+00')
 $test$,'42501');

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','21000000-0000-4000-8000-000000000001',true);
select lives_ok($test$update public.organization_memberships set active=false
 where organization_id='31000000-0000-4000-8000-000000000001' and user_id='21000000-0000-4000-8000-000000000003'$test$,
 'platform Admin suspends Staff membership');
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','21000000-0000-4000-8000-000000000003',true);
select ok(not public.can_access_assigned_event('41000000-0000-4000-8000-000000000001'),
 'inactive organization Staff membership immediately invalidates assignment access');
select is((select count(*)::int from public.event_roster where event_id='41000000-0000-4000-8000-000000000001'),0,
 'membership deactivation removes online roster visibility');
select is((select count(*)::int from public.event_staff),0,
 'inactive staff cannot see their own former active assignment');

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','21000000-0000-4000-8000-000000000001',true);
select lives_ok($test$update public.organization_memberships set active=true
 where organization_id='31000000-0000-4000-8000-000000000001' and user_id='21000000-0000-4000-8000-000000000003'$test$,
 'admin restores membership for explicit event-revocation coverage');

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','21000000-0000-4000-8000-000000000002',true);
select ok(public.revoke_event_staff(
  (select id from public.event_staff where event_id='41000000-0000-4000-8000-000000000001' and revoked_at is null)
) is not null,'Leader revokes Staff assignment');
select is((select count(*)::int from public.event_staff
 where event_id='41000000-0000-4000-8000-000000000001' and revoked_at is null),0,
 'revocation leaves no active assignment');
select is((select count(*)::int from public.event_staff
 where event_id='41000000-0000-4000-8000-000000000001' and revoked_by='21000000-0000-4000-8000-000000000002' and revoked_at is not null),1,
 'revocation preserves actor and time');
select throws_ok($test$select public.revoke_event_staff(
 (select id from public.event_staff where event_id='41000000-0000-4000-8000-000000000001' and revoked_at is not null limit 1)
)$test$,'55000');

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','21000000-0000-4000-8000-000000000003',true);
select ok(not public.can_access_assigned_event('41000000-0000-4000-8000-000000000001'),
 'explicit revocation immediately invalidates effective event access');
select is((select count(*)::int from public.events where id='41000000-0000-4000-8000-000000000001'),0,
 'revoked Staff cannot read event metadata');
select is((select count(*)::int from public.event_checkpoints where event_id='41000000-0000-4000-8000-000000000001'),0,
 'revoked Staff cannot read event checkpoints');
select is((select count(*)::int from public.event_roster where event_id='41000000-0000-4000-8000-000000000001'),0,
 'revoked Staff cannot read student roster');

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','21000000-0000-4000-8000-000000000001',true);
select ok(public.assign_event_staff('41000000-0000-4000-8000-000000000001','21000000-0000-4000-8000-000000000003') is not null,
 'Admin can reassign previously revoked eligible Staff');
select is((select count(*)::int from public.event_staff where event_id='41000000-0000-4000-8000-000000000001'),2,
 'reassignment preserves the historical revoked period');
select is((select count(*)::int from public.event_staff where event_id='41000000-0000-4000-8000-000000000001' and revoked_at is null),1,
 'reassignment creates exactly one active period');
select is((select count(*)::int from public.event_staff
 where event_id='41000000-0000-4000-8000-000000000001' and assigned_by='21000000-0000-4000-8000-000000000001'),1,
 'reassignment records actual assigning Admin');

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','21000000-0000-4000-8000-000000000006',true);
select throws_ok($test$select public.assign_event_staff('41000000-0000-4000-8000-000000000001','21000000-0000-4000-8000-000000000003')$test$,'42501');
select throws_ok($test$select * from public.open_event('41000000-0000-4000-8000-000000000001')$test$,'42501');
select is((select count(*)::int from public.event_staff),0,
 'unassigned verified outsider sees no Staff rows');

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','21000000-0000-4000-8000-000000000010',true);
select ok(not public.can_manage_org('31000000-0000-4000-8000-000000000001'),
 'unverified organization Leader has no management rights');
select throws_ok($test$select public.assign_event_staff('41000000-0000-4000-8000-000000000001','21000000-0000-4000-8000-000000000003')$test$,'42501');
select throws_ok($test$select * from public.open_event('41000000-0000-4000-8000-000000000001')$test$,'42501');

reset role;
set local role anon;
select set_config('request.jwt.claim.sub','',true);
select throws_ok($test$select public.assign_event_staff('41000000-0000-4000-8000-000000000001','21000000-0000-4000-8000-000000000003')$test$,'42501');
select throws_ok($test$select * from public.open_event('41000000-0000-4000-8000-000000000001')$test$,'42501');
select ok(not has_table_privilege('anon','public.event_staff','SELECT'),
 'anonymous user has no assignment-table SELECT grant');

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','21000000-0000-4000-8000-000000000002',true);
select throws_ok($test$select * from public.open_event('41000000-0000-4000-8000-000000000003')$test$,'22023');
select is((select state from public.events where id='41000000-0000-4000-8000-000000000003'),
 'DRAFT','unfrozen activation failure leaves event unchanged');
select is((select opened_at from public.events where id='41000000-0000-4000-8000-000000000003'),
 null::timestamptz,'unfrozen activation has no false timestamp');
select is((select event_state from public.open_event('41000000-0000-4000-8000-000000000001')),
 'OPEN','authorized Leader opens a valid frozen event');
select ok((select opened_at is not null from public.events where id='41000000-0000-4000-8000-000000000001'),
 'activation persisted a server timestamp');
select throws_ok($test$select * from public.open_event('41000000-0000-4000-8000-000000000001')$test$,'55000');
select is((select count(*)::int from public.event_roster where event_id='41000000-0000-4000-8000-000000000001'),1,
 'opening preserves frozen roster entries');
select is((select count(*)::int from public.event_checkpoints where event_id='41000000-0000-4000-8000-000000000001'),1,
 'opening preserves configured checkpoints');
select throws_ok($test$insert into public.event_checkpoints(event_id,label,direction,opens_at,closes_at)
 values ('41000000-0000-4000-8000-000000000001','Late Mutation','OUT','2041-01-01 09:00+08','2041-01-01 10:00+08')
 $test$,'42501');
select throws_ok($test$select public.update_draft_event(
 '41000000-0000-4000-8000-000000000001','Mutated after activation','2041-01-01 00:00+00',
 '2041-01-02 00:00+00',array[1]::smallint[])$test$,'42501');

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','21000000-0000-4000-8000-000000000001',true);
select is((select event_state from public.open_event('41000000-0000-4000-8000-000000000002')),
 'OPEN','platform Admin may activate another organization valid event');
select is((select count(*)::int from public.events where state='OPEN'),2,
 'only intentionally activated events became OPEN');

-- Fabricate an inconsistent event under the isolated operator to verify that
-- opening independently checks checkpoint requirements even if metadata is forged.
reset role;
update public.events set roster_frozen_at=clock_timestamp()
 where id='41000000-0000-4000-8000-000000000004';
insert into public.event_roster(event_id,student_id,student_name,program_code,year_level,frozen_at)
 values ('41000000-0000-4000-8000-000000000004','00009990001','Synthetic Milestone Two Student','BSIT',1,now());
set local role authenticated;
select set_config('request.jwt.claim.sub','21000000-0000-4000-8000-000000000002',true);
select throws_ok($test$select * from public.open_event('41000000-0000-4000-8000-000000000004')$test$,'22023');
select is((select state from public.events where id='41000000-0000-4000-8000-000000000004'),
 'DRAFT','invalid checkpoint configuration cannot partially activate event');
select is((select opened_at from public.events where id='41000000-0000-4000-8000-000000000004'),
 null::timestamptz,'invalid activation leaves server timestamp unset');

select * from finish();
rollback;
