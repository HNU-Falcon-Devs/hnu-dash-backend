-- M4.2 synthetic-only reconciliation. Existing receipts/results are retained.
-- Separate immutable terminal records; no mutable reconciliation flag.
create table public.offline_upload_seals (
  event_id uuid primary key references public.events(id) on delete restrict,
  sealed_at timestamptz not null,
  sealed_by uuid not null references auth.users(id) on delete restrict
);
create table public.offline_preparation_accounting (
  preparation_id uuid primary key references public.offline_preparations(id) on delete restrict,
  disposition text not null check (disposition in ('completed','missing','lost','revoked','undrained')),
  uploaded_count bigint not null check (uploaded_count >= 0),
  declared_count bigint,
  reason text,
  accounted_at timestamptz not null,
  accounted_by uuid not null references auth.users(id) on delete restrict,
  check (
    (disposition = 'completed' and declared_count is not null
      and declared_count = uploaded_count and reason is null)
    or (disposition <> 'completed' and declared_count is null
      and reason is not null and length(reason) between 1 and 500
      and reason ~ '[^[:space:]]')
  )
);
alter table public.attendance_scans
  add column source text not null default 'online',
  add column offline_capture_id uuid unique references public.offline_capture_claims(capture_id) on delete restrict,
  add constraint attendance_scan_source_valid check (
    (source = 'online' and offline_capture_id is null)
    or (source = 'offline' and offline_capture_id is not null and outcome in ('accepted','duplicate'))
  ),
  add constraint attendance_scan_provenance_identity unique (scan_id, offline_capture_id);
create table public.offline_claim_reviews (
  capture_id uuid primary key references public.offline_capture_claims(capture_id) on delete restrict,
  decision text not null check (decision in ('approve','reject')),
  reason text not null check (length(reason) between 1 and 500 and reason ~ '[^[:space:]]'),
  receipt_id uuid unique,
  reviewed_at timestamptz not null,
  reviewed_by uuid not null references auth.users(id) on delete restrict,
  check ((decision = 'approve' and receipt_id is not null)
     or (decision = 'reject' and receipt_id is null)),
  foreign key (receipt_id, capture_id)
    references public.attendance_scans(scan_id, offline_capture_id) on delete restrict
);
create table public.offline_reconciliation_confirmations (
  event_id uuid primary key references public.offline_upload_seals(event_id) on delete restrict,
  confirmed_at timestamptz not null,
  confirmed_by uuid not null references auth.users(id) on delete restrict
);
alter table public.offline_upload_seals enable row level security;
revoke all on public.offline_upload_seals from public, anon, authenticated, service_role;
create trigger offline_upload_seals_immutable before update or delete on public.offline_upload_seals
for each row execute function public.prevent_offline_evidence_mutation();
alter table public.offline_preparation_accounting enable row level security;
revoke all on public.offline_preparation_accounting from public, anon, authenticated, service_role;
create trigger offline_preparation_accounting_immutable before update or delete on public.offline_preparation_accounting
for each row execute function public.prevent_offline_evidence_mutation();
alter table public.offline_claim_reviews enable row level security;
revoke all on public.offline_claim_reviews from public, anon, authenticated, service_role;
create trigger offline_claim_reviews_immutable before update or delete on public.offline_claim_reviews
for each row execute function public.prevent_offline_evidence_mutation();
alter table public.offline_reconciliation_confirmations enable row level security;
revoke all on public.offline_reconciliation_confirmations from public, anon, authenticated, service_role;
create trigger offline_reconciliation_confirmations_immutable before update or delete on public.offline_reconciliation_confirmations
for each row execute function public.prevent_offline_evidence_mutation();
-- Existing manager receipt access is unchanged; Staff retain their M2.3 online
-- reads, but do not obtain an offline review/eligibility oracle through SELECT.
drop policy attendance_scans_read on public.attendance_scans;
create policy attendance_scans_read on public.attendance_scans for select to authenticated
using (
  exists (select 1 from public.events e where e.id = event_id
    and public.can_manage_org(e.organization_id))
  or (source = 'online' and submitted_by = auth.uid()
    and public.can_access_assigned_event(event_id))
);

-- All mutators use event FOR UPDATE before authorization rows. Reads use
-- FOR SHARE for a consistent per-event snapshot, not an unbounded export.
create function public.lock_offline_reconciliation_manager(eid uuid, p_write boolean)
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
  if not ev.offline_enabled then
    raise exception 'Event is not offline-enabled' using errcode = '55000';
  end if;
  return ev;
end;
$$;
create function public.lock_owned_offline_preparation(p_preparation_id uuid, p_write boolean)
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
  return prep;
end;
$$;
create function public.offline_reconciliation_ready(eid uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists (select 1 from public.offline_upload_seals s where s.event_id = eid)
    and not exists (select 1 from public.offline_preparations p
      where p.event_id = eid and not exists (
        select 1 from public.offline_preparation_accounting a where a.preparation_id = p.id))
    and not exists (select 1 from public.offline_capture_claims c
      where c.event_id = eid and not exists (
        select 1 from public.offline_claim_reviews r where r.capture_id = c.capture_id));
$$;
revoke all on function public.lock_offline_reconciliation_manager(uuid,boolean),
  public.lock_owned_offline_preparation(uuid,boolean), public.offline_reconciliation_ready(uuid)
from public, anon, authenticated, service_role;

-- The preparation ID is the natural idempotency key for its sole declaration.
-- Even after cutoff/seal, an authorized Staff may account for the durable
-- claims until a terminal disposition exists. This never opens upload again.
create function public.complete_offline_preparation(p_preparation_id uuid, p_acknowledged_count bigint)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  prep public.offline_preparations%rowtype;
  ev public.events%rowtype;
  a public.offline_preparation_accounting%rowtype;
  actual_count bigint;
  replay boolean := false;
begin
  if p_acknowledged_count is null or p_acknowledged_count < 0 then
    raise exception 'Expected a nonnegative acknowledged count' using errcode = '22023';
  end if;
  prep := public.lock_owned_offline_preparation(p_preparation_id,true);
  select * into ev from public.events e where e.id = prep.event_id;
  select * into a from public.offline_preparation_accounting x where x.preparation_id = prep.id;
  if found then
    if a.disposition <> 'completed' or a.declared_count <> p_acknowledged_count then
      raise exception 'Preparation accounting already recorded' using errcode = '23505';
    end if;
    replay := true;
  else
    if ev.state not in ('OPEN','SYNCING') then
      raise exception 'Preparation completion is unavailable' using errcode = '55000';
    end if;
    select count(*) into actual_count from public.offline_capture_claims c where c.preparation_id = prep.id;
    if p_acknowledged_count <> actual_count then
      raise exception 'Acknowledged count does not match durable claims' using errcode = '22023';
    end if;
    insert into public.offline_preparation_accounting
      (preparation_id,disposition,uploaded_count,declared_count,accounted_at,accounted_by)
      values (prep.id,'completed',actual_count,p_acknowledged_count,clock_timestamp(),auth.uid())
      returning * into a;
  end if;
  return jsonb_build_object('preparation_id',a.preparation_id,'disposition',a.disposition,
    'uploaded_count',a.uploaded_count,'declared_count',a.declared_count,
    'accounted_at',a.accounted_at,'accounted_by',a.accounted_by,'replayed',replay);
end;
$$;

create function public.seal_offline_uploads(eid uuid)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  ev public.events%rowtype;
  s public.offline_upload_seals%rowtype;
  replay boolean := false;
begin
  ev := public.lock_offline_reconciliation_manager(eid,true);
  select * into s from public.offline_upload_seals x where x.event_id = eid;
  if found then
    replay := true;
  else
    if ev.state <> 'SYNCING' or ev.closed_at is null or ev.offline_upload_cutoff is null
       or clock_timestamp() < ev.offline_upload_cutoff then
      raise exception 'Seal requires SYNCING after the upload cutoff' using errcode = '55000';
    end if;
    insert into public.offline_upload_seals(event_id,sealed_at,sealed_by)
      values (eid,clock_timestamp(),auth.uid()) returning * into s;
  end if;
  return jsonb_build_object('event_id',eid,'sealed_at',s.sealed_at,'sealed_by',s.sealed_by,'replayed',replay);
end;
$$;

create function public.account_offline_preparation_loss(
  eid uuid, p_preparation_id uuid, p_disposition text, p_reason text
)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  ev public.events%rowtype;
  a public.offline_preparation_accounting%rowtype;
  actual_count bigint;
  replay boolean := false;
begin
  if p_preparation_id is null or p_disposition is null
    or p_disposition not in ('missing','lost','revoked','undrained')
    or p_reason is null or length(p_reason) not between 1 and 500
    or p_reason !~ '[^[:space:]]' then
    raise exception 'Expected loss disposition and nonempty bounded reason' using errcode = '22023';
  end if;
  ev := public.lock_offline_reconciliation_manager(eid,true);
  perform 1 from public.offline_preparations p where p.id = p_preparation_id and p.event_id = eid;
  if not found then
    raise exception 'Offline reconciliation not permitted' using errcode = '42501';
  end if;
  select * into a from public.offline_preparation_accounting x where x.preparation_id = p_preparation_id;
  if found then
    if a.disposition <> p_disposition or a.reason is distinct from p_reason then
      raise exception 'Preparation accounting already recorded' using errcode = '23505';
    end if;
    replay := true;
  else
    if ev.state <> 'SYNCING' or not exists (
      select 1 from public.offline_upload_seals s where s.event_id = eid) then
      raise exception 'Loss accounting requires sealed SYNCING' using errcode = '55000';
    end if;
    select count(*) into actual_count from public.offline_capture_claims c where c.preparation_id = p_preparation_id;
    insert into public.offline_preparation_accounting
      (preparation_id,disposition,uploaded_count,reason,accounted_at,accounted_by)
      values (p_preparation_id,p_disposition,actual_count,p_reason,clock_timestamp(),auth.uid())
      returning * into a;
  end if;
  return jsonb_build_object('preparation_id',a.preparation_id,'disposition',a.disposition,
    'uploaded_count',a.uploaded_count,'declared_count',a.declared_count,'reason',a.reason,
    'accounted_at',a.accounted_at,'accounted_by',a.accounted_by,'replayed',replay);
end;
$$;

create function public.review_offline_capture(eid uuid, p_capture_id uuid, p_decision text, p_reason text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  ev public.events%rowtype;
  c public.offline_capture_claims%rowtype;
  review public.offline_claim_reviews%rowtype;
  receipt uuid;
  outcome_value text;
  staff_actor uuid;
  replay boolean := false;
begin
  if p_capture_id is null or p_decision is null or p_decision not in ('approve','reject')
    or p_reason is null or length(p_reason) not between 1 and 500
    or p_reason !~ '[^[:space:]]' then
    raise exception 'Expected review decision and nonempty bounded reason' using errcode = '22023';
  end if;
  ev := public.lock_offline_reconciliation_manager(eid,true);
  select * into c from public.offline_capture_claims x where x.capture_id = p_capture_id and x.event_id = eid;
  if not found then
    raise exception 'Offline reconciliation not permitted' using errcode = '42501';
  end if;
  select * into review from public.offline_claim_reviews x where x.capture_id = c.capture_id;
  if found then
    if review.decision <> p_decision or review.reason <> p_reason then
      raise exception 'Offline claim review already recorded' using errcode = '23505';
    end if;
    replay := true;
  else
    if ev.state <> 'SYNCING' or not exists (
      select 1 from public.offline_upload_seals s where s.event_id = eid) then
      raise exception 'Review requires sealed SYNCING' using errcode = '55000';
    end if;
    if p_decision = 'approve' then
      if not c.review_eligible then
        raise exception 'Offline claim is not eligible for promotion' using errcode = '55000';
      end if;
      select p.staff_user_id into staff_actor from public.offline_preparations p where p.id = c.preparation_id;
      -- No new online evidence after closure; parent event lock serializes all
      -- promotions. Existing partial unique index remains the final guard.
      outcome_value := case when exists (
        select 1 from public.attendance_scans s where s.event_id = eid
          and s.checkpoint_id = c.checkpoint_id and s.student_id = c.student_id
          and s.outcome = 'accepted') then 'duplicate' else 'accepted' end;
      insert into public.attendance_scans
        (scan_id,event_id,checkpoint_id,student_id,submitted_by,received_at,outcome,source,offline_capture_id)
        values (gen_random_uuid(),eid,c.checkpoint_id,c.student_id,staff_actor,c.received_at,
          outcome_value,'offline',c.capture_id) returning scan_id into receipt;
    end if;
    insert into public.offline_claim_reviews(capture_id,decision,reason,receipt_id,reviewed_at,reviewed_by)
      values (c.capture_id,p_decision,p_reason,receipt,clock_timestamp(),auth.uid())
      returning * into review;
  end if;
  select s.outcome into outcome_value from public.attendance_scans s where s.scan_id = review.receipt_id;
  return jsonb_build_object('capture_id',review.capture_id,'decision',review.decision,'reason',review.reason,
    'receipt_id',review.receipt_id,'receipt_outcome',outcome_value,
    'reviewed_at',review.reviewed_at,'reviewed_by',review.reviewed_by,'replayed',replay);
end;
$$;

create function public.confirm_offline_reconciliation(eid uuid)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  ev public.events%rowtype;
  c public.offline_reconciliation_confirmations%rowtype;
  replay boolean := false;
begin
  ev := public.lock_offline_reconciliation_manager(eid,true);
  select * into c from public.offline_reconciliation_confirmations x where x.event_id = eid;
  if found then
    replay := true;
  else
    if ev.state <> 'SYNCING' or not public.offline_reconciliation_ready(eid) then
      raise exception 'Reconciliation requires seal and all sessions and claims accounted for' using errcode = '55000';
    end if;
    insert into public.offline_reconciliation_confirmations(event_id,confirmed_at,confirmed_by)
      values (eid,clock_timestamp(),auth.uid()) returning * into c;
  end if;
  return jsonb_build_object('event_id',eid,'confirmed_at',c.confirmed_at,'confirmed_by',c.confirmed_by,'replayed',replay);
end;
$$;

create function public.get_offline_preparation_status(p_preparation_id uuid)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  prep public.offline_preparations%rowtype;
  ev public.events%rowtype;
  a public.offline_preparation_accounting%rowtype;
  sealed timestamptz;
  actual_count bigint;
begin
  prep := public.lock_owned_offline_preparation(p_preparation_id,false);
  select * into ev from public.events e where e.id = prep.event_id;
  select * into a from public.offline_preparation_accounting x where x.preparation_id = prep.id;
  select s.sealed_at into sealed from public.offline_upload_seals s where s.event_id = ev.id;
  select count(*) into actual_count from public.offline_capture_claims c where c.preparation_id = prep.id;
  return jsonb_build_object('preparation_id',prep.id,'event_id',ev.id,'event_state',ev.state,
    'expires_at',prep.expires_at,'upload_cutoff',ev.offline_upload_cutoff,'sealed_at',sealed,
    'uploaded_count',actual_count,'disposition',a.disposition,'declared_count',a.declared_count,
    'accounted_at',a.accounted_at,
    'can_upload',a.preparation_id is null and sealed is null
      and ev.state in ('OPEN','SYNCING') and clock_timestamp() < ev.offline_upload_cutoff,
    'can_complete',a.preparation_id is null and ev.state in ('OPEN','SYNCING'));
end;
$$;

create function public.get_event_offline_summary(eid uuid)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  ev public.events%rowtype;
  s public.offline_upload_seals%rowtype;
  conf public.offline_reconciliation_confirmations%rowtype;
  sessions bigint;
  completed bigint;
  losses bigint;
  claims bigint;
  reviewed bigint;
  ready boolean;
begin
  ev := public.lock_offline_reconciliation_manager(eid,false);
  select * into s from public.offline_upload_seals x where x.event_id = eid;
  select * into conf from public.offline_reconciliation_confirmations x where x.event_id = eid;
  select count(*), count(*) filter (where a.disposition = 'completed'),
    count(*) filter (where a.disposition <> 'completed')
    into sessions,completed,losses from public.offline_preparations p
    left join public.offline_preparation_accounting a on a.preparation_id = p.id where p.event_id = eid;
  select count(*),count(r.capture_id) into claims,reviewed from public.offline_capture_claims c
    left join public.offline_claim_reviews r on r.capture_id = c.capture_id where c.event_id = eid;
  ready := public.offline_reconciliation_ready(eid);
  return jsonb_build_object('event_id',eid,'event_state',ev.state,'upload_cutoff',ev.offline_upload_cutoff,
    'sealed_at',s.sealed_at,'sealed_by',s.sealed_by,'confirmed_at',conf.confirmed_at,'confirmed_by',conf.confirmed_by,
    'preparation_count',sessions,'completed_count',completed,'loss_count',losses,
    'unaccounted_count',sessions-completed-losses,'claim_count',claims,'reviewed_count',reviewed,
    'unreviewed_count',claims-reviewed,'can_seal',ev.state = 'SYNCING' and s.event_id is null
      and clock_timestamp() >= ev.offline_upload_cutoff,
    'can_confirm',ev.state = 'SYNCING' and ready and conf.event_id is null,
    'can_finalize',ev.state = 'SYNCING' and ready and conf.event_id is not null);
end;
$$;

create function public.get_event_offline_preparations(eid uuid, p_limit integer default 200, p_offset integer default 0)
returns table (preparation_id uuid, assignment_id uuid, staff_user_id uuid,
  issued_at timestamptz, expires_at timestamptz, revoked_at timestamptz, uploaded_count bigint,
  disposition text, declared_count bigint, reason text, accounted_at timestamptz, accounted_by uuid)
language plpgsql security definer set search_path = ''
as $$
begin
  if p_limit is null or p_limit not between 1 and 200 or p_offset is null or p_offset < 0 then
    raise exception 'Expected page size 1..200 and nonnegative offset' using errcode = '22023';
  end if;
  perform public.lock_offline_reconciliation_manager(eid,false);
  return query select p.id,p.assignment_id,p.staff_user_id,p.issued_at,p.expires_at,es.revoked_at,
    (select count(*) from public.offline_capture_claims c where c.preparation_id = p.id),
    a.disposition,a.declared_count,a.reason,a.accounted_at,a.accounted_by
    from public.offline_preparations p join public.event_staff es on es.id = p.assignment_id
    left join public.offline_preparation_accounting a on a.preparation_id = p.id
    where p.event_id = eid order by p.issued_at,p.id limit p_limit offset p_offset;
end;
$$;
create function public.get_event_offline_claims(eid uuid, p_limit integer default 200, p_offset integer default 0)
returns table (capture_id uuid, preparation_id uuid, checkpoint_id uuid, student_id text,
  staff_user_id uuid, claimed_at timestamptz, received_at timestamptz, review_eligible boolean,
  decision text, reason text, receipt_id uuid, receipt_outcome text, reviewed_at timestamptz, reviewed_by uuid)
language plpgsql security definer set search_path = ''
as $$
begin
  if p_limit is null or p_limit not between 1 and 200 or p_offset is null or p_offset < 0 then
    raise exception 'Expected page size 1..200 and nonnegative offset' using errcode = '22023';
  end if;
  perform public.lock_offline_reconciliation_manager(eid,false);
  return query select c.capture_id,c.preparation_id,c.checkpoint_id,c.student_id,p.staff_user_id,
    c.claimed_at,c.received_at,c.review_eligible,r.decision,r.reason,r.receipt_id,s.outcome,r.reviewed_at,r.reviewed_by
    from public.offline_capture_claims c join public.offline_preparations p on p.id = c.preparation_id
    left join public.offline_claim_reviews r on r.capture_id = c.capture_id
    left join public.attendance_scans s on s.scan_id = r.receipt_id
    where c.event_id = eid order by c.received_at,c.capture_id limit p_limit offset p_offset;
end;
$$;
revoke all on function public.complete_offline_preparation(uuid,bigint),
  public.seal_offline_uploads(uuid),public.account_offline_preparation_loss(uuid,uuid,text,text),
  public.review_offline_capture(uuid,uuid,text,text),public.confirm_offline_reconciliation(uuid),
  public.get_offline_preparation_status(uuid),public.get_event_offline_summary(uuid),
  public.get_event_offline_preparations(uuid,integer,integer),public.get_event_offline_claims(uuid,integer,integer)
from public, anon, authenticated, service_role;
grant execute on function public.complete_offline_preparation(uuid,bigint),
  public.seal_offline_uploads(uuid),public.account_offline_preparation_loss(uuid,uuid,text,text),
  public.review_offline_capture(uuid,uuid,text,text),public.confirm_offline_reconciliation(uuid),
  public.get_offline_preparation_status(uuid),public.get_event_offline_summary(uuid),
  public.get_event_offline_preparations(uuid,integer,integer),public.get_event_offline_claims(uuid,integer,integer)
to authenticated;

-- Preserve M4.1 response and payload; deny only NEW claims after accounting/seal.
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


-- Preserve M2.3 and reject cross-mode replay at both lookup/race paths.
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

-- Keep original finalized replay and all existing classification logic.
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

