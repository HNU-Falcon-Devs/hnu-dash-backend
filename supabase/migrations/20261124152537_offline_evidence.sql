-- M4.1: synthetic-only bounded offline preparation and immutable claims.
-- No reconciliation, claim promotion, or official attendance policy.
alter table public.events
  add column offline_enabled boolean not null default false,
  add column offline_upload_cutoff timestamptz,
  add constraint offline_event_policy_consistent check (
    (not offline_enabled and offline_upload_cutoff is null)
    or (offline_enabled and (
      (state = 'DRAFT' and offline_upload_cutoff is null)
      or (state <> 'DRAFT' and offline_upload_cutoff is not null
          and isfinite(offline_upload_cutoff))
    ))
  );

-- Derive the cutoff only at activation, after the existing roster/checkpoint
-- freeze. Draft edits remain available under the existing rules.
create function public.enforce_offline_event_policy()
returns trigger language plpgsql set search_path = ''
as $$
begin
  if new.offline_enabled is distinct from old.offline_enabled
     and (old.state <> 'DRAFT' or new.state <> 'DRAFT' or old.offline_enabled) then
    raise exception 'Offline policy is immutable after opt-in or activation'
      using errcode = '55000';
  end if;
  if new.offline_upload_cutoff is distinct from old.offline_upload_cutoff then
    raise exception 'Offline cutoff is server-derived and immutable'
      using errcode = '42501';
  end if;
  if old.state = 'DRAFT' and new.state = 'OPEN' and new.offline_enabled then
    select max(c.closes_at) + interval '24 hours'
      into new.offline_upload_cutoff
      from public.event_checkpoints c where c.event_id = old.id;
    if new.offline_upload_cutoff is null or not isfinite(new.offline_upload_cutoff) then
      raise exception 'Offline activation requires finite checkpoint windows'
        using errcode = '22023';
    end if;
  end if;
  return new;
end;
$$;
create trigger events_offline_policy
before update on public.events for each row
execute function public.enforce_offline_event_policy();
revoke all on function public.enforce_offline_event_policy()
from public, anon, authenticated, service_role;

create function public.enable_event_offline(eid uuid)
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
  if ev.state <> 'DRAFT' then
    raise exception 'Offline opt-in requires DRAFT' using errcode = '55000';
  end if;
  update public.events set offline_enabled = true where id = eid;
  return true;
end;
$$;

-- Composite keys tie preparation to the exact immutable assignment identity
-- and claims to their event's actual checkpoint. A revoked assignment remains
-- historical evidence, but never grants upload authority.
alter table public.event_staff
  add constraint event_staff_offline_identity unique (id, event_id, staff_user_id);
alter table public.event_checkpoints
  add constraint event_checkpoint_offline_identity unique (event_id, id);

create table public.offline_preparations (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null unique,
  event_id uuid not null,
  assignment_id uuid not null,
  staff_user_id uuid not null,
  issued_at timestamptz not null,
  expires_at timestamptz not null,
  unique (id, event_id),
  foreign key (assignment_id, event_id, staff_user_id)
    references public.event_staff(id, event_id, staff_user_id) on delete restrict,
  constraint offline_preparation_bounds check (
    isfinite(issued_at) and isfinite(expires_at)
    and expires_at > issued_at and expires_at <= issued_at + interval '8 hours'
  )
);
create index offline_preparations_assignment_expiry
  on public.offline_preparations(assignment_id, expires_at);

create table public.offline_capture_claims (
  capture_id uuid primary key,
  preparation_id uuid not null,
  event_id uuid not null,
  checkpoint_id uuid not null,
  student_id text not null check (student_id ~ '^[A-Za-z0-9-]{1,64}$'),
  claimed_at timestamptz not null check (isfinite(claimed_at)),
  received_at timestamptz not null check (isfinite(received_at)),
  -- Internal plausibility only. Even true is NOT accepted evidence.
  review_eligible boolean not null,
  foreign key (preparation_id, event_id)
    references public.offline_preparations(id, event_id) on delete restrict,
  foreign key (event_id, checkpoint_id)
    references public.event_checkpoints(event_id, id) on delete restrict
);
create index offline_claims_preparation on public.offline_capture_claims(preparation_id);
create index offline_claims_event on public.offline_capture_claims(event_id);
alter table public.offline_preparations enable row level security;
alter table public.offline_capture_claims enable row level security;
revoke all on public.offline_preparations, public.offline_capture_claims
from public, anon, authenticated, service_role;

create function public.prevent_offline_evidence_mutation()
returns trigger language plpgsql set search_path = ''
as $$
begin
  raise exception 'Offline preparation and claim evidence is immutable'
    using errcode = '42501';
end;
$$;
create trigger offline_preparations_immutable
before update or delete on public.offline_preparations for each row
execute function public.prevent_offline_evidence_mutation();
create trigger offline_claims_immutable
before update or delete on public.offline_capture_claims for each row
execute function public.prevent_offline_evidence_mutation();
revoke all on function public.prevent_offline_evidence_mutation()
from public, anon, authenticated, service_role;

-- Called only after locking the parent event. Hold live identity and effective
-- authorization rows through commit. Revocation locks assignment then reads
-- the event without a row lock; it cannot invert the event->assignment order.
create function public.lock_offline_staff(
  p_event_id uuid, p_org_id uuid, p_assignment_id uuid
)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare
  actor uuid := auth.uid();
  assignment uuid;
begin
  perform 1 from auth.users u
    where u.id = actor and u.email_confirmed_at is not null
      and lower(coalesce(u.email,'')) ~ '^[^@[:space:]]+@hnu[.]edu[.]ph$'
    for share;
  if not found then
    raise exception 'Offline evidence not permitted' using errcode = '42501';
  end if;
  select a.id into assignment from public.event_staff a
    join public.organizations o on o.id = p_org_id
    join public.organization_memberships m
      on m.organization_id = o.id and m.user_id = a.staff_user_id
    where a.event_id = p_event_id and a.staff_user_id = actor
      and (p_assignment_id is null or a.id = p_assignment_id)
      and a.revoked_at is null and o.active and m.active and m.role = 'staff'
    for share of a, o, m;
  if not found then
    raise exception 'Offline evidence not permitted' using errcode = '42501';
  end if;
  return assignment;
end;
$$;
revoke all on function public.lock_offline_staff(uuid, uuid, uuid)
from public, anon, authenticated, service_role;

create function public.prepare_offline_capture(p_event_id uuid, p_request_id uuid)
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

create function public.submit_offline_capture(
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

revoke all on function public.enable_event_offline(uuid),
  public.prepare_offline_capture(uuid,uuid),
  public.submit_offline_capture(uuid,uuid,uuid,text,timestamptz)
from public, anon, authenticated, service_role;
grant execute on function public.enable_event_offline(uuid),
  public.prepare_offline_capture(uuid,uuid),
  public.submit_offline_capture(uuid,uuid,uuid,text,timestamptz)
to authenticated;

-- Keep the existing finalizer, including authorized immutable replay, with
-- one additional locked-row guard. No reconciliation bypass exists in M4.1.
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

  -- A retry after commit returns the original actor/time and persisted count.
  -- No second insert or recalculation, even if a different manager retries.
  if ev.state = 'FINALIZED' then
    select count(*)::integer into record_count from public.attendance_records r where r.event_id = eid;
    return jsonb_build_object('event_id',eid,'event_state',ev.state,
      'finalized_at',ev.finalized_at,'finalized_by',ev.finalized_by,
      'record_count',record_count,'replayed',true);
  end if;
  if ev.offline_enabled then
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

