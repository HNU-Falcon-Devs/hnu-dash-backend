-- HNU-DASH-OFFLINE-B2-001: private evidence, timing and synchronization.
-- No operational v2 creation/activation, no legacy evidence mutation.
alter table offline_b1_private.preparations add unique(id,event_id);

create table offline_b1_private.claims_v2 (
  capture_id uuid primary key,
  preparation_id uuid not null,
  event_id uuid not null,
  checkpoint_id uuid not null,
  student_id text not null check (student_id ~ '^[A-Za-z0-9-]{1,64}$'),
  clock_payload jsonb not null,
  received_at timestamptz not null check (isfinite(received_at)),
  hard_start timestamptz not null,
  hard_end timestamptz not null,
  plausible_start timestamptz,
  plausible_end timestamptz,
  initial_disposition text not null check (initial_disposition in ('eligible','rejected','exception')),
  timing_basis text not null,
  validated_capture_at timestamptz,
  check ((plausible_start is null)=(plausible_end is null)),
  check (plausible_start is null or plausible_start<=plausible_end),
  check ((initial_disposition='eligible')=(validated_capture_at is not null)),
  check (validated_capture_at is null or
    (validated_capture_at>=hard_start and validated_capture_at<hard_end
     and validated_capture_at<=received_at and validated_capture_at between plausible_start and plausible_end)),
  foreign key(preparation_id,event_id) references offline_b1_private.preparations(id,event_id) on delete restrict,
  foreign key(event_id,checkpoint_id) references offline_b1_private.effective_windows(event_id,checkpoint_id) on delete restrict
);
create index b2_claims_preparation on offline_b1_private.claims_v2(preparation_id);
create index b2_claims_slot on offline_b1_private.claims_v2
  (event_id,student_id,checkpoint_id,validated_capture_at,received_at,capture_id);

create table offline_b1_private.accounting_v2 (
  preparation_id uuid primary key references offline_b1_private.preparations(id) on delete restrict,
  disposition text not null check(disposition in ('completed','missing','lost','revoked','undrained')),
  uploaded_count bigint not null check(uploaded_count>=0),
  declared_count bigint,
  reason text,
  accounted_at timestamptz not null check(isfinite(accounted_at)),
  accounted_by uuid not null references auth.users(id) on delete restrict,
  check ((disposition='completed' and declared_count is not null and declared_count=uploaded_count and reason is null)
    or (disposition<>'completed' and declared_count is null and reason is not null
      and length(reason) between 1 and 500 and reason ~ '[^[:space:]]'))
);

-- Reuse the existing immutable seal marker so B1 deadline extension retains
-- its exact post-seal guard. Extra v2 acknowledgement metadata is private.
create table offline_b1_private.seals_v2 (
  event_id uuid primary key references public.offline_upload_seals(event_id) on delete restrict,
  early boolean not null,
  unused_assignments bigint not null check(unused_assignments>=0),
  acknowledged_unused boolean not null,
  reason text not null check(length(reason) between 1 and 500 and reason ~ '[^[:space:]]')
);
create table offline_b1_private.reviews_v2 (
  capture_id uuid primary key references offline_b1_private.claims_v2(capture_id) on delete restrict,
  decision text not null check(decision in ('approve','reject')),
  reason text not null check(length(reason) between 1 and 500 and reason ~ '[^[:space:]]'),
  basis_category text,
  basis_reference text,
  validated_capture_at timestamptz,
  reviewed_at timestamptz not null check(isfinite(reviewed_at)),
  reviewed_by uuid not null references auth.users(id) on delete restrict,
  check ((decision='approve' and basis_category is not null
    and basis_category in ('synthetic_organizer_observation','synthetic_event_record')
    and basis_reference is not null and basis_reference ~ '^synthetic:[A-Za-z0-9_-]{1,128}$'
    and validated_capture_at is not null and isfinite(validated_capture_at))
    or (decision='reject' and basis_category is null and basis_reference is null and validated_capture_at is null))
);
alter table offline_b1_private.claims_v2 enable row level security;
alter table offline_b1_private.accounting_v2 enable row level security;
alter table offline_b1_private.seals_v2 enable row level security;
alter table offline_b1_private.reviews_v2 enable row level security;
revoke all on all tables in schema offline_b1_private from public,anon,authenticated,service_role;
create trigger b2_claim_immutable before update or delete on offline_b1_private.claims_v2
  for each row execute function public.prevent_offline_evidence_mutation();
create trigger b2_accounting_immutable before update or delete on offline_b1_private.accounting_v2
  for each row execute function public.prevent_offline_evidence_mutation();
create trigger b2_seal_immutable before update or delete on offline_b1_private.seals_v2
  for each row execute function public.prevent_offline_evidence_mutation();
create trigger b2_review_immutable before update or delete on offline_b1_private.reviews_v2
  for each row execute function public.prevent_offline_evidence_mutation();

create function offline_b1_private.lock_manager_v2(eid uuid,p_write boolean)
returns public.events language plpgsql security definer set search_path=''
as $$
declare ev public.events%rowtype;
begin
  if eid is null then raise exception 'Event identifier required' using errcode='22023'; end if;
  if p_write then
    select * into ev from public.events e where e.id=eid and public.can_manage_org(e.organization_id) for update;
  else
    select * into ev from public.events e where e.id=eid and public.can_manage_org(e.organization_id) for share;
  end if;
  if not found or not public.lock_event_finalization_manager(ev.organization_id) then
    raise exception 'Successor reconciliation not permitted' using errcode='42501';
  end if;
  if ev.policy_version<>2 then raise exception 'Successor policy required' using errcode='55000'; end if;
  return ev;
end;
$$;
create function offline_b1_private.lock_preparation_v2(pid uuid)
returns offline_b1_private.preparations language plpgsql security definer set search_path=''
as $$
declare p offline_b1_private.preparations%rowtype; ev public.events%rowtype;
begin
  if pid is null then raise exception 'Preparation identifier required' using errcode='22023'; end if;
  select * into p from offline_b1_private.preparations x where x.id=pid and x.staff_user_id=auth.uid();
  if not found then raise exception 'Offline evidence not permitted' using errcode='42501'; end if;
  select * into ev from public.events e where e.id=p.event_id for update;
  if not found then raise exception 'Offline evidence not permitted' using errcode='42501'; end if;
  perform public.lock_offline_staff(ev.id,ev.organization_id,p.assignment_id);
  if ev.policy_version<>2 then raise exception 'Successor policy required' using errcode='55000'; end if;
  return p;
end;
$$;

-- Finite, integer, JSON-safe elapsed milliseconds; negative values within the
-- representation range are retained as anomalies rather than trusted.
create function offline_b1_private.validate_clock_v2(p_clock jsonb)
returns void language plpgsql set search_path='' set timezone='UTC'
as $$
declare k text; v text; instant timestamptz;
  fields text[]:=array['anchor_request_elapsed_ms','anchor_response_elapsed_ms','qr_elapsed_ms',
    'confirmation_elapsed_ms','qr_wall_at','confirmation_wall_at','anchor_boot_marker',
    'capture_boot_marker','anchor_provenance','anomaly'];
begin
  if jsonb_typeof(p_clock) is distinct from 'object' or octet_length(p_clock::text)>4096
    or not (p_clock ?& fields) or p_clock-fields<>'{}'::jsonb then
    raise exception 'Expected exact bounded clock evidence object' using errcode='22023';
  end if;
  foreach k in array fields[1:4] loop
    if jsonb_typeof(p_clock->k)='null' then continue; end if;
    v:=p_clock->>k;
    if jsonb_typeof(p_clock->k)<>'number' or v !~ '^-?(0|[1-9][0-9]{0,15})$' then
      raise exception 'Invalid elapsed millisecond value' using errcode='22023';
    end if;
    if abs(v::numeric)>9007199254740991 then
      raise exception 'Invalid elapsed millisecond value' using errcode='22023';
    end if;
  end loop;
  foreach k in array fields[5:6] loop
    if jsonb_typeof(p_clock->k)='null' then continue; end if;
    v:=p_clock->>k;
    if jsonb_typeof(p_clock->k)<>'string'
      or v !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]{1,6})?(Z|[+-][0-9]{2}:[0-9]{2})$' then
      raise exception 'Expected offset-aware wall instant' using errcode='22023';
    end if;
    begin
      instant:=v::timestamptz;
    exception when data_exception then
      raise exception 'Invalid wall instant' using errcode='22023';
    end;
    if not isfinite(instant) then raise exception 'Invalid wall instant' using errcode='22023'; end if;
  end loop;
  foreach k in array fields[7:8] loop
    if jsonb_typeof(p_clock->k)='null' then continue; end if;
    if jsonb_typeof(p_clock->k)<>'string' or (p_clock->>k) !~ '^[A-Za-z0-9_-]{1,128}$' then
      raise exception 'Invalid boot marker' using errcode='22023';
    end if;
  end loop;
  if jsonb_typeof(p_clock->'anchor_provenance') is distinct from 'string'
    or (p_clock->>'anchor_provenance') not in ('original','replayed','missing','unknown')
    or jsonb_typeof(p_clock->'anomaly') is distinct from 'string'
    or (p_clock->>'anomaly') not in ('none','missing','reboot','clock_jump','inconsistent','other') then
    raise exception 'Invalid clock provenance or anomaly category' using errcode='22023';
  end if;
end;
$$;

-- Exact whole days plus sub-day integer microseconds (below IEEE 754's
-- exact integer limit). UTC day arithmetic is elapsed time here.
create function offline_b1_private.add_us_v2(t timestamptz,us numeric)
returns timestamptz language sql immutable strict set search_path='' set timezone='UTC'
as $$
  select t + make_interval(days=>trunc(us/86400000000)::integer)
    + (mod(us,86400000000)::double precision * interval '1 microsecond');
$$;

create function offline_b1_private.classify_clock_v2(
  anchor timestamptz,p_clock jsonb,hard_lo timestamptz,hard_hi timestamptz,receipt timestamptz
)
returns table(disposition text,basis text,lo timestamptz,hi timestamptz,normalized timestamptz)
language plpgsql set search_path='' set timezone='UTC'
as $$
declare
  req numeric:=(p_clock->>'anchor_request_elapsed_ms')::numeric;
  resp numeric:=(p_clock->>'anchor_response_elapsed_ms')::numeric;
  qr numeric:=(p_clock->>'qr_elapsed_ms')::numeric;
  conf numeric:=(p_clock->>'confirmation_elapsed_ms')::numeric;
  qw timestamptz:=(p_clock->>'qr_wall_at')::timestamptz;
  cw timestamptz:=(p_clock->>'confirmation_wall_at')::timestamptz;
  eps numeric; ceps numeric; clo timestamptz; chi timestamptz;
begin
  disposition:='exception'; basis:='uncertain_provenance';
  if hard_lo>=hard_hi or hard_lo>receipt then
    disposition:='rejected'; basis:='empty_hard_interval'; return next; return;
  end if;
  if req is null or resp is null or qr is null or conf is null or qw is null or cw is null
    or (p_clock->>'anchor_boot_marker') is null or (p_clock->>'capture_boot_marker') is null
    or (p_clock->>'anchor_boot_marker')<>(p_clock->>'capture_boot_marker')
    or (p_clock->>'anchor_provenance')<>'original' or (p_clock->>'anomaly')<>'none' then
    return next; return;
  end if;
  if req<0 or resp<req or resp-req>5000 or qr<resp or conf<qr or conf-qr>30000 then
    basis:='invalid_elapsed_sequence'; return next; return;
  end if;
  -- 100 ppm of the maximum elapsed duration from request, rounded outward
  -- in microseconds; two seconds fixed uncertainty.
  eps:=2000000+ceil((qr-req)/10);
  ceps:=2000000+ceil((conf-req)/10);
  begin
    lo:=offline_b1_private.add_us_v2(anchor,(qr-resp)*1000-eps);
    hi:=offline_b1_private.add_us_v2(anchor,(qr-req)*1000+eps);
    clo:=offline_b1_private.add_us_v2(anchor,(conf-resp)*1000-ceps);
    chi:=offline_b1_private.add_us_v2(anchor,(conf-req)*1000+ceps);
    if not isfinite(lo) or not isfinite(hi) or not isfinite(clo) or not isfinite(chi) then
      lo:=null; hi:=null; basis:='timestamp_overflow'; return next; return;
    end if;
    if qw<lo or qw>hi or cw<clo or cw>chi
      or abs(extract(epoch from (cw-qw))*1000000-(conf-qr)*1000)>ceps then
      lo:=null; hi:=null; basis:='wall_elapsed_inconsistent'; return next; return;
    end if;
  exception when data_exception then
    lo:=null; hi:=null; basis:='timestamp_overflow'; return next; return;
  end;
  -- A reliable interval entirely outside any hard boundary is terminal;
  -- a partial OPEN/checkpoint overlap is an exception, never clipped into
  -- eligibility. Server receipt is an independent inclusive upper bound.
  if lo>receipt or hi<hard_lo or lo>=hard_hi then
    disposition:='rejected'; basis:='reliable_outside_bounds'; return next; return;
  end if;
  hi:=least(hi,receipt);
  if lo<hard_lo or hi>=hard_hi then
    basis:='partial_boundary_overlap'; return next; return;
  end if;
  normalized:=offline_b1_private.add_us_v2(lo,floor(extract(epoch from (hi-lo))*500000));
  disposition:='eligible'; basis:='ordinary_interval'; return next;
end;
$$;

create function public.submit_offline_capture_v2(
  p_preparation_id uuid,p_capture_id uuid,p_checkpoint_id uuid,p_student_id text,p_clock jsonb
)
returns jsonb language plpgsql security definer set search_path='' set timezone='UTC'
as $$
declare p offline_b1_private.preparations%rowtype; ev public.events%rowtype;
  w offline_b1_private.effective_windows%rowtype; a public.event_staff%rowtype;
  c offline_b1_private.claims_v2%rowtype; t timestamptz; lower_bound timestamptz; upper_bound timestamptz;
  assessment record; replay boolean:=false;
begin
  if p_capture_id is null or p_checkpoint_id is null or p_student_id is null
    or p_student_id !~ '^[A-Za-z0-9-]{1,64}$' then
    raise exception 'Invalid capture identifiers' using errcode='22023';
  end if;
  perform offline_b1_private.validate_clock_v2(p_clock);
  p:=offline_b1_private.lock_preparation_v2(p_preparation_id);
  select * into ev from public.events e where e.id=p.event_id;
  -- Check exact original checkpoint scope even on replay, before UUID lookup.
  if not exists(select 1 from public.event_checkpoints cp where cp.event_id=ev.id and cp.id=p_checkpoint_id) then
    raise exception 'Offline evidence not permitted' using errcode='42501';
  end if;
  select * into c from offline_b1_private.claims_v2 x where x.capture_id=p_capture_id;
  if found then replay:=true;
  else
    t:=clock_timestamp();
    if ev.state<>'SYNCING' or ev.sync_deadline is null or t>=ev.sync_deadline
      or exists(select 1 from public.offline_upload_seals x where x.event_id=ev.id)
      or exists(select 1 from offline_b1_private.accounting_v2 x where x.preparation_id=p.id) then
      raise exception 'Successor upload window or preparation closed' using errcode='55000';
    end if;
    select * into w from offline_b1_private.effective_windows x where x.event_id=ev.id and x.checkpoint_id=p_checkpoint_id;
    if not found or ev.roster_frozen_at is null or ev.opened_at is null or ev.closed_at is null then
      raise exception 'Missing successor closure or roster context' using errcode='55000';
    end if;
    select * into a from public.event_staff x where x.id=p.assignment_id;
    lower_bound:=greatest(ev.opened_at,w.opens_at,p.issued_at,a.assigned_at);
    upper_bound:=least(ev.closed_at,w.closes_at);
    select * into assessment from offline_b1_private.classify_clock_v2(p.issued_at,p_clock,lower_bound,upper_bound,t);
    -- No membership oracle: scoped non-roster IDs receive the same durable
    -- acknowledgement, but are terminally rejected and never reviewed.
    if not exists(select 1 from public.event_roster rr where rr.event_id=ev.id and rr.student_id=p_student_id) then
      assessment.disposition:='rejected'; assessment.basis:='outside_frozen_roster'; assessment.normalized:=null;
    end if;
    insert into offline_b1_private.claims_v2(capture_id,preparation_id,event_id,checkpoint_id,student_id,clock_payload,
      received_at,hard_start,hard_end,plausible_start,plausible_end,initial_disposition,timing_basis,validated_capture_at)
    values(p_capture_id,p.id,ev.id,p_checkpoint_id,p_student_id,p_clock,t,lower_bound,upper_bound,
      assessment.lo,assessment.hi,assessment.disposition,assessment.basis,assessment.normalized)
    on conflict(capture_id) do nothing returning * into c;
    if not found then
      select * into c from offline_b1_private.claims_v2 x where x.capture_id=p_capture_id;
      if not found then raise exception 'Capture persistence unconfirmed' using errcode='40001'; end if;
      replay:=true;
    end if;
  end if;
  if c.preparation_id is distinct from p.id or c.event_id is distinct from ev.id
    or c.checkpoint_id is distinct from p_checkpoint_id or c.student_id is distinct from p_student_id
    or c.clock_payload is distinct from p_clock then
    raise exception 'Successor capture identifier conflicts' using errcode='23505';
  end if;
  return jsonb_build_object('policy_version',2,'capture_id',c.capture_id,'preparation_id',c.preparation_id,
    'received_at',c.received_at,'status','submitted','replayed',replay);
end;
$$;

create function public.complete_offline_preparation_v2(p_preparation_id uuid,p_acknowledged_count bigint)
returns jsonb language plpgsql security definer set search_path='' set timezone='UTC'
as $$
declare p offline_b1_private.preparations%rowtype; ev public.events%rowtype;
  x offline_b1_private.accounting_v2%rowtype; n bigint; replay boolean:=false;
begin
  if p_acknowledged_count is null or p_acknowledged_count<0 then
    raise exception 'Expected nonnegative durable count' using errcode='22023';
  end if;
  p:=offline_b1_private.lock_preparation_v2(p_preparation_id);
  select * into ev from public.events e where e.id=p.event_id;
  select * into x from offline_b1_private.accounting_v2 a where a.preparation_id=p.id;
  if found then
    if x.disposition<>'completed' or x.declared_count is distinct from p_acknowledged_count then
      raise exception 'Preparation accounting conflicts' using errcode='23505';
    end if;
    replay:=true;
  else
    if ev.state<>'SYNCING' then raise exception 'Completion requires SYNCING' using errcode='55000'; end if;
    select count(*) into n from offline_b1_private.claims_v2 c where c.preparation_id=p.id;
    if n<>p_acknowledged_count then raise exception 'Durable count mismatch' using errcode='22023'; end if;
    insert into offline_b1_private.accounting_v2 values(p.id,'completed',n,n,null,clock_timestamp(),auth.uid()) returning * into x;
  end if;
  return to_jsonb(x)||jsonb_build_object('policy_version',2,'replayed',replay);
end;
$$;

create function public.get_offline_preparation_status_v2(p_preparation_id uuid)
returns jsonb language plpgsql security definer set search_path='' set timezone='UTC'
as $$
declare p offline_b1_private.preparations%rowtype; ev public.events%rowtype;
begin
  p:=offline_b1_private.lock_preparation_v2(p_preparation_id);
  select * into ev from public.events e where e.id=p.event_id;
  return jsonb_build_object('policy_version',2,'preparation_id',p.id,'event_state',ev.state,
    'sync_deadline',ev.sync_deadline,'sealed',exists(select 1 from public.offline_upload_seals s where s.event_id=ev.id),
    'uploaded_count',(select count(*) from offline_b1_private.claims_v2 c where c.preparation_id=p.id),
    'disposition',(select a.disposition from offline_b1_private.accounting_v2 a where a.preparation_id=p.id));
end;
$$;

create function offline_b1_private.unused_assignments_v2(eid uuid)
returns bigint language sql stable set search_path=''
as $$
  select count(*) from public.event_staff a where a.event_id=eid
    and not exists(select 1 from offline_b1_private.preparations p where p.assignment_id=a.id);
$$;

create function public.seal_offline_uploads_v2(p_event_id uuid,p_confirm boolean,p_acknowledge_unused boolean,p_reason text)
returns jsonb language plpgsql security definer set search_path='' set timezone='UTC'
as $$
declare ev public.events%rowtype; s public.offline_upload_seals%rowtype;
  d offline_b1_private.seals_v2%rowtype; why text:=btrim(p_reason);
  n bigint; known bigint; t timestamptz; early_seal boolean; replay boolean:=false;
begin
  if p_confirm is distinct from true or p_acknowledge_unused is null or why is null
    or length(why) not between 1 and 500 or why !~ '[^[:space:]]' then
    raise exception 'Explicit seal confirmation and reason required' using errcode='22023';
  end if;
  ev:=offline_b1_private.lock_manager_v2(p_event_id,true);
  select * into d from offline_b1_private.seals_v2 x where x.event_id=ev.id;
  if found then
    if d.reason is distinct from why or d.acknowledged_unused is distinct from p_acknowledge_unused then
      raise exception 'Seal request conflicts' using errcode='23505';
    end if;
    select * into s from public.offline_upload_seals x where x.event_id=ev.id;
    replay:=true;
  else
    if ev.state<>'SYNCING' or ev.sync_deadline is null then
      raise exception 'Seal requires closed SYNCING' using errcode='55000';
    end if;
    n:=offline_b1_private.unused_assignments_v2(ev.id);
    select count(*) into known from offline_b1_private.preparations p where p.event_id=ev.id;
    t:=clock_timestamp(); early_seal:=t<ev.sync_deadline;
    if early_seal and exists(select 1 from offline_b1_private.preparations p
      left join offline_b1_private.accounting_v2 a on a.preparation_id=p.id
      where p.event_id=ev.id and a.disposition is distinct from 'completed') then
      raise exception 'Early seal requires every known preparation completed' using errcode='55000';
    end if;
    if (n>0 or known=0) and not p_acknowledge_unused then
      raise exception 'Acknowledge unused assignments or no preparations' using errcode='22023';
    end if;
    insert into public.offline_upload_seals values(ev.id,t,auth.uid()) returning * into s;
    insert into offline_b1_private.seals_v2 values(ev.id,early_seal,n,p_acknowledge_unused,why) returning * into d;
  end if;
  return to_jsonb(s)||to_jsonb(d)||jsonb_build_object('policy_version',2,'replayed',replay);
end;
$$;

create function public.account_offline_preparation_loss_v2(
  p_event_id uuid,p_preparation_id uuid,p_disposition text,p_reason text
)
returns jsonb language plpgsql security definer set search_path='' set timezone='UTC'
as $$
declare ev public.events%rowtype; x offline_b1_private.accounting_v2%rowtype;
  why text:=btrim(p_reason); n bigint; replay boolean:=false;
begin
  if p_preparation_id is null or p_disposition is null or p_disposition not in ('missing','lost','revoked','undrained')
    or why is null or length(why) not between 1 and 500 or why !~ '[^[:space:]]' then
    raise exception 'Invalid loss accounting payload' using errcode='22023';
  end if;
  ev:=offline_b1_private.lock_manager_v2(p_event_id,true);
  if not exists(select 1 from offline_b1_private.preparations p where p.id=p_preparation_id and p.event_id=ev.id) then
    raise exception 'Preparation not permitted' using errcode='42501';
  end if;
  select * into x from offline_b1_private.accounting_v2 a where a.preparation_id=p_preparation_id;
  if found then
    if x.disposition is distinct from p_disposition or x.reason is distinct from why then
      raise exception 'Preparation accounting conflicts' using errcode='23505';
    end if;
    replay:=true;
  else
    if ev.state<>'SYNCING' or not exists(select 1 from offline_b1_private.seals_v2 s where s.event_id=ev.id and not s.early) then
      raise exception 'Loss accounting requires deadline-based seal' using errcode='55000';
    end if;
    select count(*) into n from offline_b1_private.claims_v2 c where c.preparation_id=p_preparation_id;
    insert into offline_b1_private.accounting_v2 values(p_preparation_id,p_disposition,n,null,why,clock_timestamp(),auth.uid()) returning * into x;
  end if;
  return to_jsonb(x)||jsonb_build_object('policy_version',2,'replayed',replay);
end;
$$;

create function public.review_offline_capture_v2(
  p_event_id uuid,p_capture_id uuid,p_decision text,p_reason text,
  p_basis_category text,p_basis_reference text,p_validated_capture_at timestamptz
)
returns jsonb language plpgsql security definer set search_path='' set timezone='UTC'
as $$
declare ev public.events%rowtype; c offline_b1_private.claims_v2%rowtype;
  x offline_b1_private.reviews_v2%rowtype; why text:=btrim(p_reason); replay boolean:=false;
begin
  if p_capture_id is null or p_decision is null or p_decision not in ('approve','reject')
    or why is null or length(why) not between 1 and 500 or why !~ '[^[:space:]]'
    or (p_decision='approve' and (p_basis_category is null
      or p_basis_category not in ('synthetic_organizer_observation','synthetic_event_record')
      or p_basis_reference is null or p_basis_reference !~ '^synthetic:[A-Za-z0-9_-]{1,128}$'
      or p_validated_capture_at is null or not isfinite(p_validated_capture_at)))
    or (p_decision='reject' and (p_basis_category is not null or p_basis_reference is not null or p_validated_capture_at is not null)) then
    raise exception 'Expected bounded decision and synthetic corroboration for approval' using errcode='22023';
  end if;
  ev:=offline_b1_private.lock_manager_v2(p_event_id,true);
  select * into c from offline_b1_private.claims_v2 x where x.event_id=ev.id and x.capture_id=p_capture_id;
  if not found then raise exception 'Capture not permitted' using errcode='42501'; end if;
  select * into x from offline_b1_private.reviews_v2 a where a.capture_id=c.capture_id;
  if found then
    if x.decision is distinct from p_decision or x.reason is distinct from why
      or x.basis_category is distinct from p_basis_category or x.basis_reference is distinct from p_basis_reference
      or x.validated_capture_at is distinct from p_validated_capture_at then
      raise exception 'Exception decision conflicts' using errcode='23505';
    end if;
    replay:=true;
  else
    if ev.state<>'SYNCING' or not exists(select 1 from offline_b1_private.seals_v2 s where s.event_id=ev.id)
      or c.initial_disposition<>'exception' then
      raise exception 'Only sealed unresolved exceptions may be adjudicated' using errcode='55000';
    end if;
    if p_decision='approve' and (p_validated_capture_at<c.hard_start or p_validated_capture_at>=c.hard_end
      or p_validated_capture_at>c.received_at or (c.plausible_start is not null
        and p_validated_capture_at not between c.plausible_start and c.plausible_end)
      or not exists(select 1 from public.event_roster r where r.event_id=ev.id and r.student_id=c.student_id)) then
      raise exception 'Adjudication cannot override hard bounds' using errcode='22023';
    end if;
    insert into offline_b1_private.reviews_v2 values(c.capture_id,p_decision,why,p_basis_category,p_basis_reference,
      p_validated_capture_at,clock_timestamp(),auth.uid()) returning * into x;
  end if;
  return to_jsonb(x)||jsonb_build_object('policy_version',2,'replayed',replay);
end;
$$;

revoke all on all functions in schema offline_b1_private from public,anon,authenticated,service_role;
revoke all on function public.submit_offline_capture_v2(uuid,uuid,uuid,text,jsonb),
  public.complete_offline_preparation_v2(uuid,bigint),public.get_offline_preparation_status_v2(uuid),
  public.seal_offline_uploads_v2(uuid,boolean,boolean,text),
  public.account_offline_preparation_loss_v2(uuid,uuid,text,text),
  public.review_offline_capture_v2(uuid,uuid,text,text,text,text,timestamptz)
  from public,anon,authenticated,service_role;
grant execute on function public.submit_offline_capture_v2(uuid,uuid,uuid,text,jsonb),
  public.complete_offline_preparation_v2(uuid,bigint),public.get_offline_preparation_status_v2(uuid),
  public.seal_offline_uploads_v2(uuid,boolean,boolean,text),
  public.account_offline_preparation_loss_v2(uuid,uuid,text,text),
  public.review_offline_capture_v2(uuid,uuid,text,text,text,text,timestamptz) to authenticated;
