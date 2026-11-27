-- HNU-DASH-OFFLINE-B1-001: fixture-only lifecycle/preparation foundation.
-- Existing v1 history is not reinterpreted. No v2 evidence or finalizer.
alter table public.events
  add column policy_version smallint not null default 1 check (policy_version in (1,2)),
  add column sync_deadline timestamptz,
  add constraint b1_policy_boundary check (
    (policy_version=1 and sync_deadline is null)
    or (policy_version=2 and not offline_enabled and offline_upload_cutoff is null
      and isfinite(starts_at) and isfinite(ends_at)
      and finalized_at is null and finalized_by is null
      and (
        (state='DRAFT' and opened_at is null and closed_at is null and sync_deadline is null)
        or (state='OPEN' and opened_at is not null and isfinite(opened_at)
            and closed_at is null and sync_deadline is null)
        or (state='SYNCING' and opened_at is not null and isfinite(opened_at)
            and closed_at is not null and isfinite(closed_at)
            and sync_deadline is not null and isfinite(sync_deadline)
            and sync_deadline >= closed_at + interval '24 hours'
            and sync_deadline <= closed_at + interval '168 hours')
      ))
  );

create schema offline_b1_private;
revoke all on schema offline_b1_private from public, anon, authenticated, service_role;
create table offline_b1_private.closures (
  event_id uuid primary key references public.events(id) on delete restrict,
  request_id uuid not null unique,
  closed_at timestamptz not null check (isfinite(closed_at)),
  closed_by uuid not null references auth.users(id) on delete restrict,
  reason text check (reason is null or (length(reason) between 1 and 500 and reason ~ '[^[:space:]]')),
  overlap_acknowledged boolean not null,
  normalized_windows jsonb not null check (jsonb_typeof(normalized_windows)='array'),
  initial_deadline timestamptz not null check (isfinite(initial_deadline)
    and initial_deadline=closed_at+interval '24 hours')
);
create table offline_b1_private.effective_windows (
  event_id uuid not null references offline_b1_private.closures(event_id) on delete restrict,
  checkpoint_id uuid not null,
  opens_at timestamptz not null check (isfinite(opens_at)),
  closes_at timestamptz not null check (isfinite(closes_at) and opens_at<closes_at),
  primary key (event_id,checkpoint_id),
  foreign key (event_id,checkpoint_id) references public.event_checkpoints(event_id,id) on delete restrict
);
create table offline_b1_private.deadline_extensions (
  request_id uuid primary key,
  event_id uuid not null references offline_b1_private.closures(event_id) on delete restrict,
  previous_deadline timestamptz not null check (isfinite(previous_deadline)),
  new_deadline timestamptz not null check (isfinite(new_deadline) and new_deadline>previous_deadline),
  reason text not null check (length(reason) between 1 and 500 and reason ~ '[^[:space:]]'),
  adjusted_at timestamptz not null check (isfinite(adjusted_at)),
  adjusted_by uuid not null references auth.users(id) on delete restrict,
  unique(event_id,new_deadline)
);
create table offline_b1_private.preparations (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null unique,
  event_id uuid not null references public.events(id) on delete restrict,
  assignment_id uuid not null unique,
  staff_user_id uuid not null,
  issued_at timestamptz not null check (isfinite(issued_at)),
  context jsonb not null check (jsonb_typeof(context)='object'),
  foreign key (assignment_id,event_id,staff_user_id)
    references public.event_staff(id,event_id,staff_user_id) on delete restrict
);
alter table offline_b1_private.closures enable row level security;
alter table offline_b1_private.effective_windows enable row level security;
alter table offline_b1_private.deadline_extensions enable row level security;
alter table offline_b1_private.preparations enable row level security;
revoke all on all tables in schema offline_b1_private from public, anon, authenticated, service_role;
create trigger b1_closure_immutable before update or delete on offline_b1_private.closures
for each row execute function public.prevent_offline_evidence_mutation();
create trigger b1_window_immutable before update or delete on offline_b1_private.effective_windows
for each row execute function public.prevent_offline_evidence_mutation();
create trigger b1_extension_immutable before update or delete on offline_b1_private.deadline_extensions
for each row execute function public.prevent_offline_evidence_mutation();
create trigger b1_preparation_immutable before update or delete on offline_b1_private.preparations
for each row execute function public.prevent_offline_evidence_mutation();

-- Invoker trigger: ordinary roles cannot select the successor version.
-- Only isolated database-owner fixture construction is used in B1 tests.
create function offline_b1_private.guard_event()
returns trigger language plpgsql security invoker set search_path=''
as $$
declare c record;
begin
  if tg_op='UPDATE' then
    if new.policy_version is distinct from old.policy_version then
      raise exception 'Event policy version is immutable' using errcode='42501';
    end if;
  end if;
  if new.policy_version=1 then return new; end if;
  if current_user <> 'postgres' then
    raise exception 'Successor events are restricted to isolated fixtures' using errcode='42501';
  end if;
  if tg_op='INSERT' then
    if new.state <> 'DRAFT' then
      raise exception 'Successor fixture must begin as DRAFT' using errcode='55000';
    end if;
    return new;
  end if;
  if old.opened_at is not null and new.opened_at is distinct from old.opened_at then
    raise exception 'Successor opening time is immutable' using errcode='42501';
  end if;
  if new.state is distinct from old.state and not (
    (old.state='DRAFT' and new.state='OPEN') or
    (old.state='OPEN' and new.state='SYNCING')
  ) then
    raise exception 'Successor transition is unavailable in B1' using errcode='55000';
  end if;
  if new.state='SYNCING' then
    select * into c from offline_b1_private.closures where event_id=new.id;
    if not found then
      raise exception 'Successor closure requires immutable closure receipt' using errcode='55000';
    end if;
    if new.closed_at is distinct from c.closed_at or new.closed_by is distinct from c.closed_by then
      raise exception 'Successor closure requires immutable closure receipt' using errcode='55000';
    end if;
    if old.state='OPEN' and new.sync_deadline is distinct from c.initial_deadline then
      raise exception 'Successor closure requires initial deadline' using errcode='55000';
    end if;
    if old.state='SYNCING' and new.sync_deadline is distinct from old.sync_deadline
      and not exists (select 1 from offline_b1_private.deadline_extensions x
        where x.event_id=new.id and x.previous_deadline=old.sync_deadline
          and x.new_deadline=new.sync_deadline) then
      raise exception 'Successor deadline requires immutable extension receipt' using errcode='55000';
    end if;
  end if;
  return new;
end;
$$;
create trigger b1_event_policy before insert or update on public.events
for each row execute function offline_b1_private.guard_event();

-- Independent defense against canonical v2 evidence/final records.
create function offline_b1_private.guard_legacy_evidence()
returns trigger language plpgsql security definer set search_path=''
as $$
begin
  if exists (select 1 from public.events e where e.id=new.event_id and e.policy_version=2) then
    raise exception 'Legacy evidence unavailable for successor events' using errcode='55000';
  end if;
  return new;
end;
$$;
create trigger b1_legacy_scan_guard before insert on public.attendance_scans
for each row execute function offline_b1_private.guard_legacy_evidence();
create trigger b1_legacy_result_guard before insert on public.attendance_records
for each row execute function offline_b1_private.guard_legacy_evidence();
create trigger b1_legacy_preparation_guard before insert on public.offline_preparations
for each row execute function offline_b1_private.guard_legacy_evidence();
create trigger b1_legacy_claim_guard before insert on public.offline_capture_claims
for each row execute function offline_b1_private.guard_legacy_evidence();
create trigger b1_legacy_confirmation_guard before insert on public.offline_reconciliation_confirmations
for each row execute function offline_b1_private.guard_legacy_evidence();

-- Hide fixtures from legacy event and dependent scoped reads.
alter policy events_read on public.events using (
  policy_version=1 and (public.can_manage_org(organization_id) or public.can_access_assigned_event(id))
);
alter policy events_insert on public.events with check (
  policy_version=1 and public.can_manage_org(organization_id)
  and created_by=auth.uid() and state='DRAFT' and roster_frozen_at is null
);

create function offline_b1_private.lock_head(org_id uuid)
returns boolean language plpgsql security definer set search_path=''
as $$
declare actor uuid:=auth.uid();
begin
  perform 1 from auth.users u where u.id=actor
    and u.email_confirmed_at is not null
    and lower(coalesce(u.email,'')) ~ '^[^@[:space:]]+@hnu[.]edu[.]ph$'
    for share;
  if not found then return false; end if;
  perform 1 from public.organization_memberships m
    join public.organizations o on o.id=m.organization_id
    where m.organization_id=org_id and m.user_id=actor
      and m.role='leader' and m.active and o.active
    for share of m,o;
  return found;
end;
$$;

create function public.prepare_offline_capture_v2(
  p_event_id uuid,p_assignment_id uuid,p_request_id uuid
)
returns jsonb language plpgsql security definer set search_path='' set timezone='UTC'
as $$
declare
  ev public.events%rowtype;
  prep offline_b1_private.preparations%rowtype;
  a public.event_staff%rowtype;
  actor uuid:=auth.uid();
  issued timestamptz;
  scope_context jsonb;
  replay boolean:=false;
begin
  if p_event_id is null or p_assignment_id is null or p_request_id is null then
    raise exception 'Event, assignment and request identifiers required' using errcode='22023';
  end if;
  select * into ev from public.events e where e.id=p_event_id for update;
  if not found then raise exception 'Preparation not permitted' using errcode='42501'; end if;
  perform public.lock_offline_staff(ev.id,ev.organization_id,p_assignment_id);
  if ev.policy_version<>2 then raise exception 'Successor policy required' using errcode='55000'; end if;
  select * into prep from offline_b1_private.preparations p where p.request_id=p_request_id;
  if found then
    replay:=true;
  else
    if ev.state not in ('DRAFT','OPEN') then
      raise exception 'New preparation requires frozen DRAFT or OPEN' using errcode='55000';
    end if;
    if ev.roster_frozen_at is null or not isfinite(ev.roster_frozen_at)
       or not exists (select 1 from public.event_roster r where r.event_id=ev.id)
       or not exists (select 1 from public.event_checkpoints c where c.event_id=ev.id)
       or exists (select 1 from public.event_checkpoints c where c.event_id=ev.id
          and (not isfinite(c.opens_at) or not isfinite(c.closes_at)
            or c.opens_at<ev.starts_at or c.closes_at>ev.ends_at)) then
      raise exception 'Preparation requires frozen nonempty roster and finite checkpoints' using errcode='22023';
    end if;
    if exists (select 1 from offline_b1_private.preparations p where p.assignment_id=p_assignment_id) then
      raise exception 'An outstanding preparation already exists' using errcode='55000';
    end if;
    select * into a from public.event_staff x where x.id=p_assignment_id;
    issued:=clock_timestamp();
    if not isfinite(a.assigned_at) or a.assigned_at>issued or ev.roster_frozen_at>issued then
      raise exception 'Invalid preparation provenance' using errcode='22023';
    end if;
    scope_context:=jsonb_build_object('policy_version',2,'organization_id',ev.organization_id,
      'event_title',ev.title,'event_starts_at',ev.starts_at,'event_ends_at',ev.ends_at,
      'prepared_event_state',ev.state,'roster_frozen_at',ev.roster_frozen_at,
      'assignment_assigned_at',a.assigned_at,
      'checkpoints',(select jsonb_agg(jsonb_build_object('id',c.id,'label',c.label,
        'direction',c.direction,'opens_at',c.opens_at,'closes_at',c.closes_at)
        order by c.sort_order,c.id) from public.event_checkpoints c where c.event_id=ev.id));
    insert into offline_b1_private.preparations(request_id,event_id,assignment_id,staff_user_id,issued_at,context)
      values(p_request_id,ev.id,p_assignment_id,actor,issued,scope_context)
      on conflict(request_id) do nothing returning * into prep;
    if not found then
      select * into prep from offline_b1_private.preparations p where p.request_id=p_request_id;
      if not found then raise exception 'Preparation receipt unavailable' using errcode='40001'; end if;
      replay:=true;
    end if;
  end if;
  if prep.staff_user_id is distinct from actor then
    raise exception 'Preparation not permitted' using errcode='42501';
  end if;
  if prep.event_id is distinct from ev.id or prep.assignment_id is distinct from p_assignment_id then
    raise exception 'Preparation request identifier conflicts' using errcode='23505';
  end if;
  return prep.context || jsonb_build_object('preparation_id',prep.id,'request_id',prep.request_id,
    'event_id',prep.event_id,'assignment_id',prep.assignment_id,'staff_user_id',prep.staff_user_id,
    'issued_at',prep.issued_at,'replayed',replay);
end;
$$;

create function public.close_event_v2(
  p_event_id uuid,p_request_id uuid,p_windows jsonb,p_overlap_acknowledged boolean,p_reason text
)
returns jsonb language plpgsql security definer set search_path='' set timezone='UTC'
as $$
declare
  ev public.events%rowtype;
  receipt offline_b1_private.closures%rowtype;
  normalized jsonb;
  reason_value text:=btrim(p_reason);
  n integer;
  closed_time timestamptz;
  changed boolean;
  overlapping boolean;
  replay boolean:=false;
begin
  if p_event_id is null or p_request_id is null or p_overlap_acknowledged is null
    or jsonb_typeof(p_windows) is distinct from 'array'
    or (p_reason is not null and (length(reason_value) not between 1 and 500
      or reason_value !~ '[^[:space:]]')) then
    raise exception 'Invalid closure request' using errcode='22023';
  end if;
  select * into ev from public.events e where e.id=p_event_id and public.can_manage_org(e.organization_id) for update;
  if not found or not public.lock_event_finalization_manager(ev.organization_id) then
    raise exception 'Closure not permitted' using errcode='42501';
  end if;
  if ev.policy_version<>2 then raise exception 'Successor policy required' using errcode='55000'; end if;
  select count(*)::integer into n from public.event_checkpoints c where c.event_id=ev.id;
  if n=0 or jsonb_array_length(p_windows)<>n then
    raise exception 'Expected full checkpoint mapping' using errcode='22023';
  end if;
  if exists(select 1 from jsonb_array_elements(p_windows) j(value)
    where jsonb_typeof(j.value)<>'object') then
    raise exception 'Invalid checkpoint mapping object' using errcode='22023';
  end if;
  if exists(select 1 from jsonb_array_elements(p_windows) j(value)
    where j.value-array['checkpoint_id','opens_at','closes_at']::text[] <> '{}'::jsonb
      or jsonb_typeof(j.value->'checkpoint_id') is distinct from 'string'
      or jsonb_typeof(j.value->'opens_at') is distinct from 'string'
      or jsonb_typeof(j.value->'closes_at') is distinct from 'string'
      or (j.value->>'opens_at') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]{1,6})?(Z|[+-][0-9]{2}:[0-9]{2})$'
      or (j.value->>'closes_at') !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]{1,6})?(Z|[+-][0-9]{2}:[0-9]{2})$') then
    raise exception 'Expected exact checkpoint keys and offset-aware timestamps' using errcode='22023';
  end if;
  begin
    select jsonb_agg(jsonb_build_object('checkpoint_id',w.checkpoint_id,
      'opens_at',w.opens_at,'closes_at',w.closes_at) order by w.checkpoint_id)
      into normalized from jsonb_to_recordset(p_windows)
      as w(checkpoint_id uuid,opens_at timestamptz,closes_at timestamptz);
  exception when data_exception then
    raise exception 'Invalid checkpoint identifier or timestamp' using errcode='22023';
  end;
  if (select count(distinct w.checkpoint_id) from jsonb_to_recordset(normalized)
      as w(checkpoint_id uuid,opens_at timestamptz,closes_at timestamptz))<>n
    or exists(select 1 from jsonb_to_recordset(normalized)
      as w(checkpoint_id uuid,opens_at timestamptz,closes_at timestamptz)
      left join public.event_checkpoints c on c.id=w.checkpoint_id and c.event_id=ev.id
      where c.id is null or not isfinite(c.opens_at) or not isfinite(c.closes_at)
        or not isfinite(w.opens_at) or not isfinite(w.closes_at) or w.opens_at>=w.closes_at
        or w.opens_at>c.opens_at or w.closes_at<c.closes_at) then
    raise exception 'Mapping must extend or preserve every exact planned checkpoint' using errcode='22023';
  end if;
  select * into receipt from offline_b1_private.closures x where x.event_id=ev.id;
  if found then
    if receipt.request_id is distinct from p_request_id
      or receipt.normalized_windows is distinct from normalized
      or receipt.reason is distinct from reason_value
      or receipt.overlap_acknowledged is distinct from p_overlap_acknowledged then
      raise exception 'Closure request conflicts' using errcode='23505';
    end if;
    replay:=true;
  else
    if ev.state<>'OPEN' or ev.opened_at is null or ev.closed_at is not null then
      raise exception 'Closure requires OPEN event' using errcode='55000';
    end if;
    if ev.roster_frozen_at is null or not isfinite(ev.roster_frozen_at)
      or not exists(select 1 from public.event_roster r where r.event_id=ev.id) then
      raise exception 'Closure requires frozen nonempty roster' using errcode='22023';
    end if;
    select exists(select 1 from jsonb_to_recordset(normalized)
      as w(checkpoint_id uuid,opens_at timestamptz,closes_at timestamptz)
      join public.event_checkpoints c on c.id=w.checkpoint_id
      where w.opens_at<>c.opens_at or w.closes_at<>c.closes_at) into changed;
    select exists(select 1 from jsonb_to_recordset(normalized)
      as x(checkpoint_id uuid,opens_at timestamptz,closes_at timestamptz)
      join jsonb_to_recordset(normalized)
      as y(checkpoint_id uuid,opens_at timestamptz,closes_at timestamptz)
      on x.checkpoint_id<y.checkpoint_id and x.opens_at<y.closes_at and y.opens_at<x.closes_at)
      into overlapping;
    closed_time:=clock_timestamp();
    if (changed or closed_time<ev.ends_at) and reason_value is null then
      raise exception 'Changed windows or early closure require reason' using errcode='22023';
    end if;
    if overlapping and not p_overlap_acknowledged then
      raise exception 'Overlapping effective windows require acknowledgment' using errcode='22023';
    end if;
    insert into offline_b1_private.closures(event_id,request_id,closed_at,closed_by,reason,
      overlap_acknowledged,normalized_windows,initial_deadline)
      values(ev.id,p_request_id,closed_time,auth.uid(),reason_value,p_overlap_acknowledged,
        normalized,closed_time+interval '24 hours') returning * into receipt;
    insert into offline_b1_private.effective_windows(event_id,checkpoint_id,opens_at,closes_at)
      select ev.id,w.checkpoint_id,w.opens_at,w.closes_at from jsonb_to_recordset(normalized)
      as w(checkpoint_id uuid,opens_at timestamptz,closes_at timestamptz);
    update public.events e set state='SYNCING',closed_at=receipt.closed_at,
      closed_by=receipt.closed_by,sync_deadline=receipt.initial_deadline where e.id=ev.id;
  end if;
  return jsonb_build_object('policy_version',2,'event_id',receipt.event_id,
    'request_id',receipt.request_id,'event_state','SYNCING','closed_at',receipt.closed_at,
    'closed_by',receipt.closed_by,'reason',receipt.reason,
    'overlap_acknowledged',receipt.overlap_acknowledged,'effective_windows',receipt.normalized_windows,
    'initial_sync_deadline',receipt.initial_deadline,'replayed',replay);
end;
$$;

create function public.extend_event_sync_deadline_v2(
  p_event_id uuid,p_request_id uuid,p_new_deadline timestamptz,p_reason text
)
returns jsonb language plpgsql security definer set search_path='' set timezone='UTC'
as $$
declare
  ev public.events%rowtype;
  receipt offline_b1_private.deadline_extensions%rowtype;
  reason_value text:=btrim(p_reason);
  replay boolean:=false;
begin
  if p_event_id is null or p_request_id is null or p_new_deadline is null
    or not isfinite(p_new_deadline) or reason_value is null
    or length(reason_value) not between 1 and 500 or reason_value !~ '[^[:space:]]' then
    raise exception 'Expected finite deadline and bounded nonblank reason' using errcode='22023';
  end if;
  select * into ev from public.events e where e.id=p_event_id and public.can_manage_org(e.organization_id) for update;
  if not found or not offline_b1_private.lock_head(ev.organization_id) then
    raise exception 'Deadline extension requires active owning leader' using errcode='42501';
  end if;
  if ev.policy_version<>2 then raise exception 'Successor policy required' using errcode='55000'; end if;
  select * into receipt from offline_b1_private.deadline_extensions x where x.request_id=p_request_id;
  if found then
    if receipt.event_id is distinct from ev.id or receipt.new_deadline is distinct from p_new_deadline
      or receipt.reason is distinct from reason_value then
      raise exception 'Deadline request conflicts' using errcode='23505';
    end if;
    replay:=true;
  else
    if ev.state<>'SYNCING' or ev.closed_at is null or ev.sync_deadline is null
      or exists(select 1 from public.offline_upload_seals s where s.event_id=ev.id) then
      raise exception 'Deadline extension requires unsealed SYNCING' using errcode='55000';
    end if;
    if p_new_deadline<=ev.sync_deadline or p_new_deadline>ev.closed_at+interval '168 hours' then
      raise exception 'Deadline must extend within 168 elapsed hours of closure' using errcode='22023';
    end if;
    insert into offline_b1_private.deadline_extensions(request_id,event_id,previous_deadline,new_deadline,
      reason,adjusted_at,adjusted_by)
      values(p_request_id,ev.id,ev.sync_deadline,p_new_deadline,reason_value,clock_timestamp(),auth.uid())
      on conflict(request_id) do nothing returning * into receipt;
    if not found then
      raise exception 'Deadline request conflicts' using errcode='23505';
    end if;
    update public.events e set sync_deadline=receipt.new_deadline where e.id=ev.id;
  end if;
  return jsonb_build_object('policy_version',2,'event_id',receipt.event_id,'request_id',receipt.request_id,
    'previous_deadline',receipt.previous_deadline,'new_deadline',receipt.new_deadline,
    'reason',receipt.reason,'adjusted_at',receipt.adjusted_at,'adjusted_by',receipt.adjusted_by,'replayed',replay);
end;
$$;
revoke all on all functions in schema offline_b1_private from public, anon, authenticated, service_role;
revoke all on function public.prepare_offline_capture_v2(uuid,uuid,uuid),
  public.close_event_v2(uuid,uuid,jsonb,boolean,text),
  public.extend_event_sync_deadline_v2(uuid,uuid,timestamptz,text)
  from public,anon,authenticated,service_role;
grant execute on function public.prepare_offline_capture_v2(uuid,uuid,uuid),
  public.close_event_v2(uuid,uuid,jsonb,boolean,text),
  public.extend_event_sync_deadline_v2(uuid,uuid,timestamptz,text) to authenticated;

-- Legacy entry points retain exact bodies and ACLs except the policy guard.

create or replace function public.can_edit_draft_event(eid uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.events e
    where e.id=eid and e.policy_version=1 and e.state='DRAFT' and e.roster_frozen_at is null
      and public.can_manage_org(e.organization_id)
  );
$$;

create or replace function public.can_access_assigned_event(eid uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
  select public.hnu_verified_user() and exists (
    select 1
      from public.event_staff a
      join public.events e on e.id = a.event_id
      join public.organizations o on o.id = e.organization_id
      join public.organization_memberships m
        on m.organization_id = e.organization_id and m.user_id = a.staff_user_id
     where a.event_id = eid and e.policy_version=1 and a.staff_user_id = auth.uid()
       and a.revoked_at is null
       and m.role = 'staff' and m.active and o.active
  );
$$;

create or replace function public.assign_event_staff(eid uuid, staff_uid uuid)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare
  ev public.events%rowtype;
  assigned_id uuid;
begin
  select * into ev from public.events e where e.id = eid for update;
  if not found or not public.can_manage_org(ev.organization_id) then
    raise exception 'Event assignment not permitted in this organization'
      using errcode = '42501';
  end if;
  if ev.policy_version<>1 then
    raise exception 'Legacy operation unavailable for successor events' using errcode='55000';
  end if;
  if ev.state not in ('DRAFT', 'OPEN') then
    raise exception 'Staff assignment closed for this event state'
      using errcode = '55000';
  end if;
  if not exists (
    select 1 from public.organizations o
    where o.id = ev.organization_id and o.active
  ) then
    raise exception 'Organization is inactive' using errcode = '55000';
  end if;
  -- Lock the eligibility row against a simultaneous membership update.
  perform 1
    from public.organization_memberships m
    join auth.users u on u.id = m.user_id
   where m.organization_id = ev.organization_id
     and m.user_id = staff_uid and m.role = 'staff' and m.active
     and u.email_confirmed_at is not null
     and lower(coalesce(u.email, '')) ~ '^[^@[:space:]]+@hnu[.]edu[.]ph$'
   for share of m;
  if not found then
    raise exception 'Target account is not an active verified organization Staff member'
      using errcode = '22023';
  end if;

  insert into public.event_staff(event_id, staff_user_id, assigned_by)
    values (eid, staff_uid, auth.uid())
    returning id into assigned_id;
  return assigned_id;
end;
$$;

create or replace function public.open_event(eid uuid)
returns table(event_id uuid, event_state text, opened_at timestamptz)
language plpgsql security definer set search_path = ''
as $$
declare
  ev public.events%rowtype;
begin
  select * into ev from public.events e where e.id = eid for update;
  if not found or not public.can_manage_org(ev.organization_id) then
    raise exception 'Event activation not permitted'
      using errcode = '42501';
  end if;
  if ev.policy_version<>1 then
    raise exception 'Legacy operation unavailable for successor events' using errcode='55000';
  end if;
  if ev.state <> 'DRAFT' or ev.opened_at is not null then
    raise exception 'Only a DRAFT event can be opened'
      using errcode = '55000';
  end if;
  if not exists (
    select 1 from public.organizations o
     where o.id = ev.organization_id and o.active
  ) then
    raise exception 'Organization is inactive' using errcode = '55000';
  end if;
  if ev.starts_at >= ev.ends_at
     or ev.roster_frozen_at is null
     or not exists (
       select 1 from public.event_roster r where r.event_id = eid
     ) then
    raise exception 'Event requires a valid frozen, nonempty roster'
      using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.event_checkpoints c where c.event_id = eid
  ) or exists (
    select 1 from public.event_checkpoints c
     where c.event_id = eid
       and (c.opens_at < ev.starts_at or c.closes_at > ev.ends_at
            or c.opens_at >= c.closes_at
            or c.direction not in ('IN', 'OUT'))
  ) then
    raise exception 'Event requires valid, in-schedule attendance checkpoints'
      using errcode = '22023';
  end if;

  return query
    update public.events e
       set state = 'OPEN', opened_at = clock_timestamp()
     where e.id = eid
     returning e.id, e.state, e.opened_at;
end;
$$;

create or replace function public.close_event(eid uuid)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  ev public.events%rowtype;
  closed_time timestamptz;
begin
  if eid is null then
    raise exception 'Event identifier is required' using errcode = '22023';
  end if;
  select * into ev from public.events e
    where e.id = eid and public.can_manage_org(e.organization_id) for update;
  if not found or not public.lock_event_finalization_manager(ev.organization_id) then
    raise exception 'Event closure not permitted' using errcode = '42501';
  end if;
  if ev.policy_version<>1 then
    raise exception 'Legacy operation unavailable for successor events' using errcode='55000';
  end if;
  if ev.state <> 'OPEN' or ev.closed_at is not null then
    raise exception 'Only an OPEN event can be closed' using errcode = '55000';
  end if;
  if ev.opened_at is null or ev.roster_frozen_at is null
    or not exists (select 1 from public.event_roster r where r.event_id = eid)
    or not exists (select 1 from public.event_checkpoints c where c.event_id = eid) then
    raise exception 'Event requires a frozen nonempty roster and checkpoints' using errcode = '22023';
  end if;
  closed_time := clock_timestamp();
  if exists (select 1 from public.event_checkpoints c
    where c.event_id = eid and c.closes_at > closed_time) then
    raise exception 'All checkpoint windows must end before closure' using errcode = '55000';
  end if;
  update public.events e
    set state = 'SYNCING', closed_at = closed_time, closed_by = auth.uid()
    where e.id = eid;
  return jsonb_build_object('event_id',eid,'event_state','SYNCING',
    'closed_at',closed_time,'closed_by',auth.uid());
end;
$$;

create or replace function public.get_event_finalized_results(
  eid uuid, p_limit integer default 200, p_offset integer default 0
)
returns table (
  event_id uuid, student_id text, status text,
  required_checkpoint_count integer, accepted_checkpoint_count integer,
  finalized_at timestamptz, finalized_by uuid
)
language plpgsql stable security definer set search_path = ''
as $$
declare
  ev public.events%rowtype;
begin
  if eid is null or p_limit is null or p_limit not between 1 and 200
    or p_offset is null or p_offset < 0 then
    raise exception 'Expected event identifier, page size 1..200 and nonnegative offset'
      using errcode = '22023';
  end if;
  select * into ev from public.events e
    where e.id = eid and public.can_manage_org(e.organization_id);
  if not found then
    raise exception 'Event finalized results not permitted' using errcode = '42501';
  end if;
  if ev.policy_version<>1 then
    raise exception 'Legacy operation unavailable for successor events' using errcode='55000';
  end if;
  if ev.state <> 'FINALIZED' then
    raise exception 'Event must be finalized' using errcode = '55000';
  end if;
  return query
    select r.event_id, r.student_id, r.status, r.required_checkpoint_count,
      r.accepted_checkpoint_count, ev.finalized_at, ev.finalized_by
    from public.attendance_records r where r.event_id = eid
    order by r.student_id collate "C" limit p_limit offset p_offset;
end;
$$;

create or replace function public.enable_event_offline(eid uuid)
returns boolean language plpgsql security definer set search_path = ''
as $$
declare
  ev public.events%rowtype;
begin
  if eid is null then
    raise exception 'Event identifier is required' using errcode = '22023';
  end if;
  select * into ev from public.events e
    where e.id = eid and public.can_manage_org(e.organization_id) for update;
  if not found or not public.lock_event_finalization_manager(ev.organization_id) then
    raise exception 'Offline policy not permitted' using errcode = '42501';
  end if;
  if ev.policy_version<>1 then
    raise exception 'Legacy operation unavailable for successor events' using errcode='55000';
  end if;
  if ev.state <> 'DRAFT' then
    raise exception 'Offline opt-in requires DRAFT' using errcode = '55000';
  end if;
  update public.events set offline_enabled = true where id = eid;
  return true;
end;
$$;

create or replace function public.prepare_offline_capture(p_event_id uuid, p_request_id uuid)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  ev public.events%rowtype;
  prep public.offline_preparations%rowtype;
  assignment uuid;
  actor uuid := auth.uid();
  issued timestamptz;
  expiry timestamptz;
  last_close timestamptz;
  replay boolean := false;
begin
  if p_event_id is null or p_request_id is null then
    raise exception 'Event and preparation request identifiers are required'
      using errcode = '22023';
  end if;
  -- Serialize issuance and active-preparation checks with activation/closure,
  -- other preparation requests, and uploads for this event.
  select * into ev from public.events e where e.id = p_event_id for update;
  if not found then
    raise exception 'Offline evidence not permitted' using errcode = '42501';
  end if;
  assignment := public.lock_offline_staff(ev.id, ev.organization_id, null);
  if ev.policy_version<>1 then
    raise exception 'Legacy operation unavailable for successor events' using errcode='55000';
  end if;
  select * into prep from public.offline_preparations p
    where p.request_id = p_request_id;
  if found then
    replay := true;
  else
    if not ev.offline_enabled or ev.state <> 'OPEN' then
      raise exception 'Offline preparation requires an enabled OPEN event'
        using errcode = '55000';
    end if;
    if ev.opened_at is null or ev.roster_frozen_at is null or
       not exists (select 1 from public.event_roster r where r.event_id = ev.id) then
      raise exception 'Offline preparation requires a frozen nonempty roster'
        using errcode = '22023';
    end if;
    select max(c.closes_at) into last_close from public.event_checkpoints c
      where c.event_id = ev.id;
    issued := clock_timestamp();
    expiry := least(issued + interval '8 hours', last_close);
    if last_close is null or not isfinite(last_close) or expiry <= issued
       or ev.offline_upload_cutoff is distinct from last_close + interval '24 hours' then
      raise exception 'No valid offline capture window remains' using errcode = '55000';
    end if;
    if exists (select 1 from public.offline_preparations p
      where p.assignment_id = assignment and p.expires_at > issued) then
      raise exception 'An active offline preparation already exists'
        using errcode = '55000';
    end if;
    insert into public.offline_preparations
      (request_id,event_id,assignment_id,staff_user_id,issued_at,expires_at)
      values (p_request_id,ev.id,assignment,actor,issued,expiry)
      on conflict (request_id) do nothing returning * into prep;
    if not found then
      -- A UUID collision across events/actors may have committed while waiting.
      select * into prep from public.offline_preparations p
        where p.request_id = p_request_id;
      if not found then
        raise exception 'Preparation storage could not be confirmed' using errcode = '40001';
      end if;
      replay := true;
    end if;
  end if;
  if prep.staff_user_id is distinct from actor
     or prep.assignment_id is distinct from assignment then
    raise exception 'Offline evidence not permitted' using errcode = '42501';
  end if;
  if prep.event_id is distinct from ev.id then
    raise exception 'Preparation request identifier conflicts' using errcode = '23505';
  end if;
  return jsonb_build_object(
    'preparation_id',prep.id,'request_id',prep.request_id,
    'event_id',prep.event_id,'assignment_id',prep.assignment_id,
    'staff_user_id',prep.staff_user_id,'issued_at',prep.issued_at,
    'expires_at',prep.expires_at,'upload_cutoff',ev.offline_upload_cutoff,
    'event_title',ev.title,'event_starts_at',ev.starts_at,'event_ends_at',ev.ends_at,
    'checkpoints',(select jsonb_agg(jsonb_build_object(
      'id',c.id,'label',c.label,'direction',c.direction,
      'opens_at',c.opens_at,'closes_at',c.closes_at)
      order by c.sort_order,c.id) from public.event_checkpoints c where c.event_id = ev.id),
    'replayed',replay);
end;
$$;

create or replace function public.lock_offline_reconciliation_manager(eid uuid, p_write boolean)
returns public.events language plpgsql security definer set search_path = ''
as $$
declare ev public.events%rowtype;
begin
  if eid is null then
    raise exception 'Event identifier is required' using errcode = '22023';
  end if;
  if p_write then
    select * into ev from public.events e
      where e.id = eid and public.can_manage_org(e.organization_id) for update;
  else
    select * into ev from public.events e
      where e.id = eid and public.can_manage_org(e.organization_id) for share;
  end if;
  if not found or not public.lock_event_finalization_manager(ev.organization_id) then
    raise exception 'Offline reconciliation not permitted' using errcode = '42501';
  end if;
  if ev.policy_version<>1 then
    raise exception 'Legacy operation unavailable for successor events' using errcode='55000';
  end if;
  if not ev.offline_enabled then
    raise exception 'Event is not offline-enabled' using errcode = '55000';
  end if;
  return ev;
end;
$$;

create or replace function public.lock_owned_offline_preparation(p_preparation_id uuid, p_write boolean)
returns public.offline_preparations language plpgsql security definer set search_path = ''
as $$
declare
  prep public.offline_preparations%rowtype;
  ev public.events%rowtype;
begin
  if p_preparation_id is null then
    raise exception 'Preparation identifier is required' using errcode = '22023';
  end if;
  select * into prep from public.offline_preparations p
    where p.id = p_preparation_id and p.staff_user_id = auth.uid();
  if not found then
    raise exception 'Offline evidence not permitted' using errcode = '42501';
  end if;
  if p_write then
    select * into ev from public.events e where e.id = prep.event_id for update;
  else
    select * into ev from public.events e where e.id = prep.event_id for share;
  end if;
  if not found then
    raise exception 'Offline evidence not permitted' using errcode = '42501';
  end if;
  perform public.lock_offline_staff(ev.id, ev.organization_id, prep.assignment_id);
  if ev.policy_version<>1 then
    raise exception 'Legacy operation unavailable for successor events' using errcode='55000';
  end if;
  return prep;
end;
$$;

create or replace function public.submit_offline_capture(
  p_preparation_id uuid, p_capture_id uuid, p_checkpoint_id uuid,
  p_student_id text, p_claimed_at timestamptz
)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  ev public.events%rowtype;
  prep public.offline_preparations%rowtype;
  cp public.event_checkpoints%rowtype;
  claim public.offline_capture_claims%rowtype;
  actor uuid := auth.uid();
  received timestamptz;
  eligible boolean;
  replay boolean := false;
begin
  if p_preparation_id is null or p_capture_id is null or p_checkpoint_id is null
     or p_student_id is null or p_student_id !~ '^[A-Za-z0-9-]{1,64}$'
     or p_claimed_at is null or not isfinite(p_claimed_at) then
    raise exception 'Invalid offline capture payload' using errcode = '22023';
  end if;
  select * into prep from public.offline_preparations p
    where p.id = p_preparation_id and p.staff_user_id = actor;
  if not found then
    raise exception 'Offline evidence not permitted' using errcode = '42501';
  end if;
  -- Same parent row order as preparation/closure/finalization. This initial
  -- implementation deliberately serializes offline uploads per event.
  select * into ev from public.events e where e.id = prep.event_id for update;
  if not found then
    raise exception 'Offline evidence not permitted' using errcode = '42501';
  end if;
  perform public.lock_offline_staff(ev.id, ev.organization_id, prep.assignment_id);
  if ev.policy_version<>1 then
    raise exception 'Legacy operation unavailable for successor events' using errcode='55000';
  end if;
  select * into cp from public.event_checkpoints c
    where c.event_id = ev.id and c.id = p_checkpoint_id;
  if not found then
    raise exception 'Offline evidence not permitted' using errcode = '42501';
  end if;
  select * into claim from public.offline_capture_claims c
    where c.capture_id = p_capture_id;
  if found then
    replay := true;
  else
    if exists (select 1 from public.offline_preparation_accounting a
      where a.preparation_id = prep.id)
       or exists (select 1 from public.offline_upload_seals s where s.event_id = ev.id) then
      raise exception 'Offline preparation or upload window is closed' using errcode = '55000';
    end if;
    received := clock_timestamp();
    if not ev.offline_enabled or ev.state not in ('OPEN','SYNCING')
       or ev.offline_upload_cutoff is null or received >= ev.offline_upload_cutoff then
      raise exception 'Offline upload window is closed' using errcode = '55000';
    end if;
    if ev.roster_frozen_at is null or ev.opened_at is null
       or not exists (select 1 from public.event_roster r where r.event_id = ev.id) then
      raise exception 'Offline capture requires a frozen nonempty roster' using errcode = '22023';
    end if;
    eligible := p_claimed_at >= prep.issued_at and p_claimed_at < prep.expires_at
      and p_claimed_at >= cp.opens_at and p_claimed_at < cp.closes_at
      and p_claimed_at <= received
      and exists (select 1 from public.event_roster r
        where r.event_id = ev.id and r.student_id = p_student_id);
    insert into public.offline_capture_claims
      (capture_id,preparation_id,event_id,checkpoint_id,student_id,claimed_at,received_at,review_eligible)
      values (p_capture_id,prep.id,ev.id,cp.id,p_student_id,p_claimed_at,received,eligible)
      on conflict (capture_id) do nothing returning * into claim;
    if not found then
      select * into claim from public.offline_capture_claims c
        where c.capture_id = p_capture_id;
      if not found then
        raise exception 'Offline claim storage could not be confirmed' using errcode = '40001';
      end if;
      replay := true;
    end if;
  end if;
  if claim.preparation_id is distinct from prep.id
     or claim.event_id is distinct from ev.id
     or claim.checkpoint_id is distinct from p_checkpoint_id
     or claim.student_id is distinct from p_student_id
     or claim.claimed_at is distinct from p_claimed_at then
    raise exception 'Offline capture identifier conflicts' using errcode = '23505';
  end if;
  -- Never return eligibility, roster membership or an attendance outcome.
  return jsonb_build_object('capture_id',claim.capture_id,
    'preparation_id',claim.preparation_id,'received_at',claim.received_at,
    'status','submitted','replayed',replay);
end;
$$;

create or replace function public.ingest_attendance_scan(
  p_scan_id uuid, p_event_id uuid, p_checkpoint_id uuid, p_student_id text
)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  ev public.events%rowtype;
  checkpoint public.event_checkpoints%rowtype;
  prior public.attendance_scans%rowtype;
  actor uuid := auth.uid();
  receipt_time timestamptz;
  outcome_value text;
  inserted_id uuid;
begin
  if actor is null or not public.hnu_verified_user() then
    raise exception 'Authorized HNU Staff session required' using errcode = '42501';
  end if;
  if p_scan_id is null or p_event_id is null or p_checkpoint_id is null
     or p_student_id is null or p_student_id !~ '^[A-Za-z0-9-]{1,64}$' then
    raise exception 'Invalid scan identifiers' using errcode = '22023';
  end if;

  -- SHARE on the parent row serializes against event state changes but permits
  -- independent scans in parallel. Verify the event only after the lock.
  select * into ev from public.events e where e.id = p_event_id for share;
  if not found then
    raise exception 'Scan submission not permitted' using errcode = '42501';
  end if;

  -- Lock effective authorization rows for the entire receipt transaction.
  -- In-flight revocation/deactivation waits; later submissions see the change.
  perform 1
    from public.organizations o
    join public.organization_memberships m on m.organization_id = o.id
    join public.event_staff a
      on a.event_id = ev.id and a.staff_user_id = m.user_id
   where o.id = ev.organization_id and o.active
     and m.user_id = actor and m.role = 'staff' and m.active
     and a.revoked_at is null
   for share of o, m, a;
  if not found then
    raise exception 'Scan submission not permitted' using errcode = '42501';
  end if;

  if ev.policy_version<>1 then
    raise exception 'Legacy operation unavailable for successor events' using errcode='55000';
  end if;
  -- After authentication and event authorization, identical retries may replay
  -- the exact original outcome even if the original capture window has closed.
  select * into prior from public.attendance_scans s where s.scan_id = p_scan_id;
  if found then
    if prior.source <> 'online' or prior.event_id is distinct from p_event_id
       or prior.checkpoint_id is distinct from p_checkpoint_id
       or prior.student_id is distinct from p_student_id
       or prior.submitted_by is distinct from actor then
      raise exception 'Scan identifier already used for another submission'
        using errcode = '23505';
    end if;
    return jsonb_build_object(
      'scan_id', prior.scan_id, 'outcome', prior.outcome,
      'received_at', prior.received_at, 'replayed', true
    );
  end if;

  -- New online submissions require OPEN. Check this only after the
  -- authorized identical-UUID replay path; a prior durable receipt may be
  -- replayed even when the event has since left OPEN.
  if ev.state <> 'OPEN' then
    raise exception 'Online scan ingestion requires an OPEN event'
      using errcode = '55000';
  end if;

  -- Bad or cross-event checkpoint identifiers are denied without revealing
  -- whether some other organization's checkpoint exists.
  select * into checkpoint from public.event_checkpoints c
    where c.id = p_checkpoint_id and c.event_id = ev.id;
  if not found then
    raise exception 'Checkpoint unavailable for this event'
      using errcode = '42501';
  end if;

  receipt_time := clock_timestamp();
  outcome_value := 'rejected';
  if receipt_time >= checkpoint.opens_at
    and receipt_time < checkpoint.closes_at
    and exists (
      select 1 from public.event_roster r
      where r.event_id = ev.id and r.student_id = p_student_id
    ) then
    outcome_value := 'accepted';
  end if;

  -- The primary key and partial accepted-capture unique index settle races.
  -- A conflict may be a retry of the UUID, or a different UUID for a capture
  -- already accepted; differentiate after PostgreSQL resolves the conflict.
  insert into public.attendance_scans (
    scan_id, event_id, checkpoint_id, student_id,
    submitted_by, received_at, outcome
  ) values (
    p_scan_id, p_event_id, p_checkpoint_id, p_student_id,
    actor, receipt_time, outcome_value
  ) on conflict do nothing returning scan_id into inserted_id;

  if inserted_id is null then
    select * into prior from public.attendance_scans s where s.scan_id = p_scan_id;
    if not found then
      -- The accepted-capture unique index (not scan_id) prevented insertion.
      -- Keep this new UUID as a distinct, immutable duplicate-attempt receipt.
      outcome_value := 'duplicate';
      insert into public.attendance_scans (
        scan_id, event_id, checkpoint_id, student_id,
        submitted_by, received_at, outcome
      ) values (
        p_scan_id, p_event_id, p_checkpoint_id, p_student_id,
        actor, receipt_time, outcome_value
      ) on conflict (scan_id) do nothing returning scan_id into inserted_id;
      if inserted_id is null then
        select * into prior from public.attendance_scans s where s.scan_id = p_scan_id;
      end if;
    end if;

    if inserted_id is null then
      if not found then
        raise exception 'Could not persist scan receipt' using errcode = '40001';
      end if;
      if prior.source <> 'online' or prior.event_id is distinct from p_event_id
         or prior.checkpoint_id is distinct from p_checkpoint_id
         or prior.student_id is distinct from p_student_id
         or prior.submitted_by is distinct from actor then
        raise exception 'Scan identifier already used for another submission'
          using errcode = '23505';
      end if;
      return jsonb_build_object(
        'scan_id', prior.scan_id, 'outcome', prior.outcome,
        'received_at', prior.received_at, 'replayed', true
      );
    end if;
  end if;

  return jsonb_build_object(
    'scan_id', p_scan_id, 'outcome', outcome_value,
    'received_at', receipt_time, 'replayed', false
  );
end;
$$;

create or replace function public.finalize_event(eid uuid)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  ev public.events%rowtype;
  final_time timestamptz;
  required_count integer;
  record_count integer;
  roster_count integer;
begin
  if eid is null then
    raise exception 'Event identifier is required' using errcode = '22023';
  end if;
  select * into ev from public.events e
    where e.id = eid and public.can_manage_org(e.organization_id) for update;
  if not found or not public.lock_event_finalization_manager(ev.organization_id) then
    raise exception 'Event finalization not permitted' using errcode = '42501';
  end if;

  if ev.policy_version<>1 then
    raise exception 'Legacy operation unavailable for successor events' using errcode='55000';
  end if;
  -- A retry after commit returns the original actor/time and persisted count.
  -- No second insert or recalculation, even if a different manager retries.
  if ev.state = 'FINALIZED' then
    select count(*)::integer into record_count from public.attendance_records r where r.event_id = eid;
    return jsonb_build_object('event_id',eid,'event_state',ev.state,
      'finalized_at',ev.finalized_at,'finalized_by',ev.finalized_by,
      'record_count',record_count,'replayed',true);
  end if;
  if ev.offline_enabled and (
    not public.offline_reconciliation_ready(eid)
    or not exists (select 1 from public.offline_reconciliation_confirmations c
      where c.event_id = eid)
  ) then
    raise exception 'Offline-enabled events require reconciliation before finalization'
      using errcode = '55000';
  end if;
  if ev.state <> 'SYNCING' or ev.closed_at is null or ev.closed_by is null then
    raise exception 'Event must be closed before finalization' using errcode = '55000';
  end if;
  select count(*)::integer into roster_count from public.event_roster r where r.event_id = eid;
  select count(*)::integer into required_count from public.event_checkpoints c where c.event_id = eid;
  if ev.roster_frozen_at is null or ev.opened_at is null
     or roster_count = 0 or required_count = 0 then
    raise exception 'Event requires a frozen nonempty roster and checkpoints' using errcode = '22023';
  end if;
  if exists (select 1 from public.event_checkpoints c
    where c.event_id = eid and c.closes_at > ev.closed_at) then
    raise exception 'All checkpoint windows must end before closure' using errcode = '55000';
  end if;

  -- One set-based write from immutable receipts; no paged preview and no
  -- ON CONFLICT shortcut. A constraint failure rolls back the entire RPC.
  insert into public.attendance_records
    (event_id, student_id, status, required_checkpoint_count, accepted_checkpoint_count)
  select eid, counts.student_id,
    case when counts.accepted = required_count then 'PRESENT'
         when counts.accepted = 0 then 'ABSENT' else 'INCOMPLETE' end,
    required_count, counts.accepted
  from (
    select r.student_id, count(s.scan_id)::integer as accepted
    from public.event_roster r
    join public.event_checkpoints c on c.event_id = r.event_id
    left join public.attendance_scans s
      on s.event_id = r.event_id and s.checkpoint_id = c.id
      and s.student_id = r.student_id and s.outcome = 'accepted'
    where r.event_id = eid
    group by r.student_id
  ) counts;
  get diagnostics record_count = row_count;
  if record_count <> roster_count then
    raise exception 'Finalized record count does not match frozen roster' using errcode = '55000';
  end if;
  final_time := clock_timestamp();
  update public.events e set state = 'FINALIZED',
    finalized_at = final_time, finalized_by = auth.uid() where e.id = eid;
  return jsonb_build_object('event_id',eid,'event_state','FINALIZED',
    'finalized_at',final_time,'finalized_by',auth.uid(),
    'record_count',record_count,'replayed',false);
end;
$$;
