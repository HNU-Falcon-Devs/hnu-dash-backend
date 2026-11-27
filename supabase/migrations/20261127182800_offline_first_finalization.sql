-- HNU-DASH-OFFLINE-B2-001: provisional winners and manual finalization.
-- B1 preparation, closure and extension receipts are unchanged.
create table offline_b1_private.confirmations_v2 (
  event_id uuid primary key references offline_b1_private.seals_v2(event_id) on delete restrict,
  acknowledged_unused boolean not null,
  unused_assignments bigint not null check(unused_assignments>=0),
  reason text check(reason is null or (length(reason) between 1 and 500 and reason ~ '[^[:space:]]')),
  confirmed_at timestamptz not null check(isfinite(confirmed_at)),
  confirmed_by uuid not null references auth.users(id) on delete restrict
);
create table offline_b1_private.finalizations_v2 (
  event_id uuid primary key references offline_b1_private.confirmations_v2(event_id) on delete restrict,
  finalized_at timestamptz not null check(isfinite(finalized_at)),
  finalized_by uuid not null references auth.users(id) on delete restrict,
  winner_count bigint not null check(winner_count>=0),
  record_count bigint not null check(record_count>0)
);
alter table offline_b1_private.confirmations_v2 enable row level security;
alter table offline_b1_private.finalizations_v2 enable row level security;
create trigger b2_confirmation_immutable before update or delete on offline_b1_private.confirmations_v2
  for each row execute function public.prevent_offline_evidence_mutation();
create trigger b2_finalization_immutable before update or delete on offline_b1_private.finalizations_v2
  for each row execute function public.prevent_offline_evidence_mutation();

-- The claim/decision join is private; eligibility is never returned to Staff.
create view offline_b1_private.resolved_v2 with (security_invoker=true) as
  select c.*,r.decision,r.reason as review_reason,r.basis_category,r.basis_reference,
    r.reviewed_at,r.reviewed_by,
    case when r.decision='approve' then 'eligible'
         when r.decision='reject' then 'rejected' else c.initial_disposition end as disposition,
    coalesce(c.validated_capture_at,r.validated_capture_at) as normalized_at
  from offline_b1_private.claims_v2 c
  left join offline_b1_private.reviews_v2 r on r.capture_id=c.capture_id;
create view offline_b1_private.winners_v2 with (security_invoker=true) as
  select distinct on (event_id,student_id,checkpoint_id)
    event_id,student_id,checkpoint_id,capture_id,preparation_id,received_at,normalized_at
  from offline_b1_private.resolved_v2
  where disposition='eligible'
  order by event_id,student_id,checkpoint_id,normalized_at,received_at,capture_id;

create function offline_b1_private.ready_v2(eid uuid)
returns boolean language sql stable set search_path=''
as $$
  select exists(select 1 from offline_b1_private.seals_v2 s where s.event_id=eid)
    and not exists(select 1 from offline_b1_private.preparations p
      left join offline_b1_private.accounting_v2 a on a.preparation_id=p.id
      where p.event_id=eid and (a.preparation_id is null
        or a.uploaded_count<>(select count(*) from offline_b1_private.claims_v2 c where c.preparation_id=p.id)))
    and not exists(select 1 from offline_b1_private.resolved_v2 c where c.event_id=eid and c.disposition='exception');
$$;

create function public.confirm_offline_reconciliation_v2(p_event_id uuid,p_acknowledge_unused boolean,p_reason text)
returns jsonb language plpgsql security definer set search_path='' set timezone='UTC'
as $$
declare ev public.events%rowtype; x offline_b1_private.confirmations_v2%rowtype;
  why text:=btrim(p_reason); n bigint; known bigint; replay boolean:=false;
begin
  if p_acknowledge_unused is null or (why is not null and
    (length(why) not between 1 and 500 or why !~ '[^[:space:]]')) then
    raise exception 'Invalid reconciliation acknowledgement' using errcode='22023';
  end if;
  ev:=offline_b1_private.lock_manager_v2(p_event_id,true);
  select * into x from offline_b1_private.confirmations_v2 a where a.event_id=ev.id;
  if found then
    if x.acknowledged_unused is distinct from p_acknowledge_unused or x.reason is distinct from why then
      raise exception 'Reconciliation confirmation conflicts' using errcode='23505';
    end if;
    replay:=true;
  else
    if ev.state<>'SYNCING' or not offline_b1_private.ready_v2(ev.id) then
      raise exception 'Successor reconciliation is not ready' using errcode='55000';
    end if;
    n:=offline_b1_private.unused_assignments_v2(ev.id);
    select count(*) into known from offline_b1_private.preparations p where p.event_id=ev.id;
    if (n>0 or known=0) and (not p_acknowledge_unused or why is null) then
      raise exception 'Missing preparations require explicit acknowledgement and reason' using errcode='22023';
    end if;
    insert into offline_b1_private.confirmations_v2 values(ev.id,p_acknowledge_unused,n,why,clock_timestamp(),auth.uid())
      returning * into x;
  end if;
  return to_jsonb(x)||jsonb_build_object('policy_version',2,'replayed',replay);
end;
$$;

-- Preserve the existing online/offline receipt namespace and FK. Successor
-- capture identity is separate from scan_id and the original offline FK.
alter table public.attendance_scans
  add column successor_capture_id uuid unique references offline_b1_private.claims_v2(capture_id) on delete restrict;
alter table public.attendance_scans drop constraint attendance_scan_source_valid;
alter table public.attendance_scans add constraint attendance_scan_source_valid check(
  (source='online' and offline_capture_id is null and successor_capture_id is null)
  or (source='offline' and offline_capture_id is not null and successor_capture_id is null
    and outcome in ('accepted','duplicate'))
  or (source='offline_v2' and offline_capture_id is null and successor_capture_id is not null and outcome='accepted')
);

-- Narrow the two B1 canonical insert guards only for a transaction that has
-- a scoped immutable finalization receipt and the exact deterministic winner.
-- No session flag, public token, service-role grant or general bypass.
create function offline_b1_private.guard_scan_v2()
returns trigger language plpgsql security definer set search_path=''
as $$
declare v smallint;
begin
  select e.policy_version into v from public.events e where e.id=new.event_id;
  if v=2 then
    if new.source<>'offline_v2' or not exists(
      select 1 from offline_b1_private.winners_v2 w
      join offline_b1_private.preparations p on p.id=w.preparation_id
      join offline_b1_private.finalizations_v2 f on f.event_id=w.event_id
      join public.events e on e.id=w.event_id
      where w.event_id=new.event_id and w.checkpoint_id=new.checkpoint_id
        and w.student_id=new.student_id and w.capture_id=new.successor_capture_id
        and w.received_at=new.received_at and p.staff_user_id=new.submitted_by
        and e.state='SYNCING' and f.finalized_by=auth.uid()
        and new.outcome='accepted' and new.offline_capture_id is null
    ) then
      raise exception 'Legacy evidence unavailable for successor events' using errcode='55000';
    end if;
  elsif new.source='offline_v2' then
    raise exception 'Successor evidence requires successor event' using errcode='55000';
  end if;
  return new;
end;
$$;
create function offline_b1_private.guard_record_v2()
returns trigger language plpgsql security definer set search_path=''
as $$
begin
  if exists(select 1 from public.events e where e.id=new.event_id and e.policy_version=2) then
    if not exists(select 1 from offline_b1_private.finalizations_v2 f
      join public.events e on e.id=f.event_id where f.event_id=new.event_id
      and e.state='SYNCING' and f.finalized_by=auth.uid())
      or new.required_checkpoint_count<>(select count(*) from public.event_checkpoints c where c.event_id=new.event_id)
      or new.accepted_checkpoint_count<>(select count(*) from offline_b1_private.winners_v2 w
        where w.event_id=new.event_id and w.student_id=new.student_id)
      or new.accepted_checkpoint_count<>(select count(*) from public.attendance_scans s
        where s.event_id=new.event_id and s.student_id=new.student_id and s.source='offline_v2') then
      raise exception 'Legacy evidence unavailable for successor events' using errcode='55000';
    end if;
  end if;
  return new;
end;
$$;
drop trigger b1_legacy_scan_guard on public.attendance_scans;
create trigger b1_legacy_scan_guard before insert on public.attendance_scans
  for each row execute function offline_b1_private.guard_scan_v2();
drop trigger b1_legacy_result_guard on public.attendance_records;
create trigger b1_legacy_result_guard before insert on public.attendance_records
  for each row execute function offline_b1_private.guard_record_v2();

-- Same v1 branch; same B1 DRAFT/OPEN/SYNCING bounds; add FINALIZED only.
alter table public.events drop constraint b1_policy_boundary;
alter table public.events add constraint b1_policy_boundary check (
  (policy_version=1 and sync_deadline is null)
  or (policy_version=2 and not offline_enabled and offline_upload_cutoff is null
    and isfinite(starts_at) and isfinite(ends_at)
    and (
      (state='DRAFT' and opened_at is null and closed_at is null and sync_deadline is null
        and finalized_at is null and finalized_by is null)
      or (state='OPEN' and opened_at is not null and isfinite(opened_at)
        and closed_at is null and sync_deadline is null and finalized_at is null and finalized_by is null)
      or (state in ('SYNCING','FINALIZED') and opened_at is not null and isfinite(opened_at)
        and closed_at is not null and isfinite(closed_at)
        and sync_deadline is not null and isfinite(sync_deadline)
        and sync_deadline>=closed_at+interval '24 hours' and sync_deadline<=closed_at+interval '168 hours'
        and ((state='SYNCING' and finalized_at is null and finalized_by is null)
          or (state='FINALIZED' and finalized_at is not null and isfinite(finalized_at) and finalized_by is not null)))
    ))
);
create or replace function offline_b1_private.guard_event()
returns trigger language plpgsql security invoker set search_path=''
as $$
declare c record; f offline_b1_private.finalizations_v2%rowtype;
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
    (old.state='OPEN' and new.state='SYNCING') or
    (old.state='SYNCING' and new.state='FINALIZED')
  ) then
    raise exception 'Successor transition is unavailable' using errcode='55000';
  end if;
  if old.state='FINALIZED' and new is distinct from old then
    raise exception 'Finalized successor event is immutable' using errcode='42501';
  end if;
  if new.state in ('SYNCING','FINALIZED') then
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
  if new.state='FINALIZED' and old.state<>'FINALIZED' then
    select * into f from offline_b1_private.finalizations_v2 x where x.event_id=new.id;
    if not found or new.finalized_at is distinct from f.finalized_at
      or new.finalized_by is distinct from f.finalized_by or auth.uid() is distinct from f.finalized_by
      or new.sync_deadline is distinct from old.sync_deadline
      or not offline_b1_private.ready_v2(new.id)
      or f.winner_count<>(select count(*) from public.attendance_scans s where s.event_id=new.id and s.source='offline_v2')
      or f.record_count<>(select count(*) from public.attendance_records a where a.event_id=new.id) then
      raise exception 'Successor finalization requires complete materialization' using errcode='55000';
    end if;
  end if;
  return new;
end;
$;

create function public.finalize_event_v2(p_event_id uuid)
returns jsonb language plpgsql security definer set search_path='' set timezone='UTC'
as $$
declare ev public.events%rowtype; f offline_b1_private.finalizations_v2%rowtype;
  n bigint; w bigint; actual bigint; cp_count integer; replay boolean:=false;
begin
  ev:=offline_b1_private.lock_manager_v2(p_event_id,true);
  select * into f from offline_b1_private.finalizations_v2 x where x.event_id=ev.id;
  if found then
    if ev.state<>'FINALIZED' then raise exception 'Incomplete successor finalization' using errcode='55000'; end if;
    replay:=true;
  else
    if ev.state<>'SYNCING' or ev.closed_at is null or ev.roster_frozen_at is null
      or not offline_b1_private.ready_v2(ev.id)
      or not exists(select 1 from offline_b1_private.confirmations_v2 c where c.event_id=ev.id) then
      raise exception 'Successor finalization requires sealed confirmed reconciliation' using errcode='55000';
    end if;
    select count(*) into n from public.event_roster r where r.event_id=ev.id;
    select count(*)::integer into cp_count from public.event_checkpoints c where c.event_id=ev.id;
    select count(*) into w from offline_b1_private.winners_v2 c where c.event_id=ev.id;
    if n=0 or cp_count=0 then raise exception 'Frozen roster and checkpoints required' using errcode='22023'; end if;
    insert into offline_b1_private.finalizations_v2 values(ev.id,clock_timestamp(),auth.uid(),w,n) returning * into f;
    insert into public.attendance_scans(scan_id,event_id,checkpoint_id,student_id,submitted_by,received_at,
      outcome,source,successor_capture_id)
      select gen_random_uuid(),win.event_id,win.checkpoint_id,win.student_id,p.staff_user_id,win.received_at,
        'accepted','offline_v2',win.capture_id
      from offline_b1_private.winners_v2 win join offline_b1_private.preparations p on p.id=win.preparation_id
      where win.event_id=ev.id;
    get diagnostics actual=row_count;
    if actual<>w then raise exception 'Winner materialization count mismatch' using errcode='55000'; end if;
    insert into public.attendance_records(event_id,student_id,status,required_checkpoint_count,accepted_checkpoint_count)
      select ev.id,r.student_id,case when coalesce(s.n,0)=cp_count then 'PRESENT'
        when coalesce(s.n,0)=0 then 'ABSENT' else 'INCOMPLETE' end,
        cp_count,coalesce(s.n,0)::integer
      from public.event_roster r
      left join (select a.student_id,count(*) n from public.attendance_scans a
        where a.event_id=ev.id and a.source='offline_v2' group by a.student_id) s on s.student_id=r.student_id
      where r.event_id=ev.id;
    get diagnostics actual=row_count;
    if actual<>n then raise exception 'Finalized result count mismatch' using errcode='55000'; end if;
    update public.events e set state='FINALIZED',finalized_at=f.finalized_at,finalized_by=f.finalized_by where e.id=ev.id;
  end if;
  return to_jsonb(f)||jsonb_build_object('policy_version',2,'event_state','FINALIZED','replayed',replay);
end;
$$;

create function offline_b1_private.check_page_v2(p_limit integer,p_offset integer)
returns void language plpgsql set search_path=''
as $$
begin
  if p_limit is null or p_limit not between 1 and 200 or p_offset is null or p_offset<0 then
    raise exception 'Expected page size 1..200 and nonnegative offset' using errcode='22023';
  end if;
end;
$$;

create function public.get_event_offline_summary_v2(p_event_id uuid)
returns jsonb language plpgsql security definer set search_path='' set timezone='UTC'
as $$
declare ev public.events%rowtype; known bigint; accounted bigint; completed bigint;
  eligible bigint; rejected bigint; pending bigint; winners bigint; ready boolean; confirmed boolean;
begin
  ev:=offline_b1_private.lock_manager_v2(p_event_id,false);
  select count(*),count(a.preparation_id),count(*) filter(where a.disposition='completed')
    into known,accounted,completed from offline_b1_private.preparations p
    left join offline_b1_private.accounting_v2 a on a.preparation_id=p.id where p.event_id=ev.id;
  select count(*) filter(where disposition='eligible'),count(*) filter(where disposition='rejected'),
    count(*) filter(where disposition='exception') into eligible,rejected,pending
    from offline_b1_private.resolved_v2 c where c.event_id=ev.id;
  select count(*) into winners from offline_b1_private.winners_v2 c where c.event_id=ev.id;
  ready:=offline_b1_private.ready_v2(ev.id);
  confirmed:=exists(select 1 from offline_b1_private.confirmations_v2 c where c.event_id=ev.id);
  return jsonb_build_object('policy_version',2,'event_id',ev.id,'event_state',ev.state,'sync_deadline',ev.sync_deadline,
    'sealed',exists(select 1 from offline_b1_private.seals_v2 s where s.event_id=ev.id),
    'known_preparations',known,'accounted_preparations',accounted,'completed_preparations',completed,
    'loss_accounted_preparations',accounted-completed,'unused_assignments',offline_b1_private.unused_assignments_v2(ev.id),
    'submitted_claims',eligible+rejected+pending,'eligible_claims',eligible,'rejected_claims',rejected,'pending_exceptions',pending,
    'provisional_winners',winners,'evidence_ready',ready,'reconciliation_confirmed',confirmed,
    'can_finalize',ev.state='SYNCING' and ready and confirmed,
    'finalized_at',ev.finalized_at,'finalized_by',ev.finalized_by,
    'finalized_records',(select f.record_count from offline_b1_private.finalizations_v2 f where f.event_id=ev.id));
end;
$$;

-- Stable bounded assignment page; unused assignments are explicit null prep
-- rows, not fabricated zero-count completions.
create function public.get_event_offline_preparations_v2(p_event_id uuid,p_limit integer default 200,p_offset integer default 0)
returns jsonb language plpgsql security definer set search_path='' set timezone='UTC'
as $$
declare ev public.events%rowtype; result jsonb;
begin
  perform offline_b1_private.check_page_v2(p_limit,p_offset);
  ev:=offline_b1_private.lock_manager_v2(p_event_id,false);
  with page as materialized (
    select a.id,a.staff_user_id,a.assigned_at,a.revoked_at from public.event_staff a
    where a.event_id=ev.id order by a.assigned_at,a.id limit p_limit offset p_offset
  )
  select coalesce(jsonb_agg(jsonb_build_object('assignment_id',q.id,'staff_user_id',q.staff_user_id,
    'assigned_at',q.assigned_at,'revoked_at',q.revoked_at,'preparation_id',p.id,'issued_at',p.issued_at,
    'uploaded_count',case when p.id is null then null else (select count(*) from offline_b1_private.claims_v2 c where c.preparation_id=p.id) end,
    'accounting',case when a.preparation_id is null then null else to_jsonb(a) end)
    order by q.assigned_at,q.id),'[]'::jsonb) into result
  from page q left join offline_b1_private.preparations p on p.assignment_id=q.id
  left join offline_b1_private.accounting_v2 a on a.preparation_id=p.id;
  return result;
end;
$$;

create function public.get_event_offline_claims_v2(
  p_event_id uuid,p_limit integer default 200,p_offset integer default 0,p_exceptions_only boolean default false)
returns jsonb language plpgsql security definer set search_path='' set timezone='UTC'
as $$
declare ev public.events%rowtype; result jsonb;
begin
  perform offline_b1_private.check_page_v2(p_limit,p_offset);
  if p_exceptions_only is null then raise exception 'Exception filter required' using errcode='22023'; end if;
  ev:=offline_b1_private.lock_manager_v2(p_event_id,false);
  with page as materialized (
    select c.* from offline_b1_private.resolved_v2 c where c.event_id=ev.id
      and (not p_exceptions_only or c.initial_disposition='exception')
    order by c.received_at,c.capture_id limit p_limit offset p_offset
  )
  select coalesce(jsonb_agg(to_jsonb(q)||jsonb_build_object('provisional_winner',
    coalesce(q.capture_id=w.capture_id,false),'final_receipt_id',s.scan_id)
    order by q.received_at,q.capture_id),'[]'::jsonb) into result
  from page q left join lateral (
    select c.capture_id from offline_b1_private.resolved_v2 c
    where c.event_id=ev.id and c.student_id=q.student_id and c.checkpoint_id=q.checkpoint_id and c.disposition='eligible'
    order by c.normalized_at,c.received_at,c.capture_id limit 1
  ) w on true left join public.attendance_scans s on s.successor_capture_id=q.capture_id;
  return result;
end;
$$;

-- Page roster/checkpoint pairs first; indexed slot probes only for the page.
-- No per-row authorization/RLS recursion: one verified manager lock.
create function public.get_event_checkpoint_coverage_v2(p_event_id uuid,p_limit integer default 200,p_offset integer default 0)
returns jsonb language plpgsql security definer set search_path='' set timezone='UTC'
as $$
declare ev public.events%rowtype; result jsonb;
begin
  perform offline_b1_private.check_page_v2(p_limit,p_offset);
  ev:=offline_b1_private.lock_manager_v2(p_event_id,false);
  if ev.roster_frozen_at is null then raise exception 'Frozen roster required' using errcode='55000'; end if;
  with page as materialized (
    select r.student_id,c.id,c.label,c.direction,c.sort_order from public.event_roster r
      join public.event_checkpoints c on c.event_id=r.event_id where r.event_id=ev.id
      order by r.student_id collate "C",c.sort_order,c.id limit p_limit offset p_offset
  )
  select coalesce(jsonb_agg(jsonb_build_object('student_id',q.student_id,'checkpoint_id',q.id,
    'checkpoint_label',q.label,'checkpoint_direction',q.direction,'checkpoint_sort_order',q.sort_order,
    'provisional_capture_id',w.capture_id,'validated_capture_at',w.normalized_at,'received_at',w.received_at,
    'final_receipt_id',s.scan_id,'finalized',ev.state='FINALIZED')
    order by q.student_id collate "C",q.sort_order,q.id),'[]'::jsonb) into result
  from page q left join lateral (
    select c.capture_id,c.normalized_at,c.received_at from offline_b1_private.resolved_v2 c
    where c.event_id=ev.id and c.student_id=q.student_id and c.checkpoint_id=q.id and c.disposition='eligible'
    order by c.normalized_at,c.received_at,c.capture_id limit 1
  ) w on true left join public.attendance_scans s on s.successor_capture_id=w.capture_id;
  return result;
end;
$$;

create function public.get_event_finalized_results_v2(p_event_id uuid,p_limit integer default 200,p_offset integer default 0)
returns jsonb language plpgsql security definer set search_path='' set timezone='UTC'
as $$
declare ev public.events%rowtype; result jsonb;
begin
  perform offline_b1_private.check_page_v2(p_limit,p_offset);
  ev:=offline_b1_private.lock_manager_v2(p_event_id,false);
  if ev.state<>'FINALIZED' then raise exception 'Successor event is not finalized' using errcode='55000'; end if;
  select coalesce(jsonb_agg(to_jsonb(q) order by q.student_id collate "C"),'[]'::jsonb) into result
    from (select r.* from public.attendance_records r where r.event_id=ev.id
      order by r.student_id collate "C" limit p_limit offset p_offset) q;
  return result;
end;
$$;

revoke all on all tables in schema offline_b1_private from public,anon,authenticated,service_role;
revoke all on all functions in schema offline_b1_private from public,anon,authenticated,service_role;
revoke all on function public.confirm_offline_reconciliation_v2(uuid,boolean,text),public.finalize_event_v2(uuid),
  public.get_event_offline_summary_v2(uuid),public.get_event_offline_preparations_v2(uuid,integer,integer),
  public.get_event_offline_claims_v2(uuid,integer,integer,boolean),
  public.get_event_checkpoint_coverage_v2(uuid,integer,integer),public.get_event_finalized_results_v2(uuid,integer,integer)
  from public,anon,authenticated,service_role;
grant execute on function public.confirm_offline_reconciliation_v2(uuid,boolean,text),public.finalize_event_v2(uuid),
  public.get_event_offline_summary_v2(uuid),public.get_event_offline_preparations_v2(uuid,integer,integer),
  public.get_event_offline_claims_v2(uuid,integer,integer,boolean),
  public.get_event_checkpoint_coverage_v2(uuid,integer,integer),public.get_event_finalized_results_v2(uuid,integer,integer)
  to authenticated;
