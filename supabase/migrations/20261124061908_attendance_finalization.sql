-- M3.2A: synthetic-only online closure and immutable prototype results.
-- No offline synchronization, institutional policy or correction workflow.
alter table public.events
  add column closed_at timestamptz,
  add column closed_by uuid references auth.users(id) on delete restrict,
  add column finalized_at timestamptz,
  add column finalized_by uuid references auth.users(id) on delete restrict,
  add constraint event_closure_audit_pair check (
    (closed_at is null) = (closed_by is null)
    and (closed_at is null or (state in ('SYNCING','FINALIZED','LOCKED')
      and opened_at is not null and closed_at >= opened_at))
  ),
  add constraint event_finalization_audit_pair check (
    (finalized_at is null) = (finalized_by is null)
    and (finalized_at is null or (state in ('FINALIZED','LOCKED')
      and closed_at is not null and finalized_at >= closed_at))
    and (state <> 'FINALIZED' or finalized_at is not null)
  );

create table public.attendance_records (
  event_id uuid not null,
  student_id text not null,
  status text not null,
  required_checkpoint_count integer not null check (required_checkpoint_count > 0),
  accepted_checkpoint_count integer not null,
  primary key (event_id, student_id),
  foreign key (event_id, student_id)
    references public.event_roster(event_id, student_id) on delete restrict,
  constraint attendance_record_coverage check (
    accepted_checkpoint_count between 0 and required_checkpoint_count
    and status = case
      when accepted_checkpoint_count = required_checkpoint_count then 'PRESENT'
      when accepted_checkpoint_count = 0 then 'ABSENT'
      else 'INCOMPLETE'
    end
  )
);
alter table public.attendance_records enable row level security;
-- Only the bounded manager RPC exposes results, not a direct table endpoint.
revoke all on public.attendance_records from public, anon, authenticated, service_role;

create function public.prevent_attendance_record_mutation()
returns trigger language plpgsql set search_path = ''
as $$
begin
  raise exception 'Finalized attendance records are immutable' using errcode = '42501';
end;
$$;
create trigger attendance_records_immutable
  before update or delete on public.attendance_records
  for each row execute function public.prevent_attendance_record_mutation();
revoke all on function public.prevent_attendance_record_mutation()
  from public, anon, authenticated;

create function public.prevent_event_finalization_audit_mutation()
returns trigger language plpgsql set search_path = ''
as $$
begin
  if (old.closed_at is not null and
       (new.closed_at is distinct from old.closed_at or new.closed_by is distinct from old.closed_by))
     or (old.finalized_at is not null and
       (new.finalized_at is distinct from old.finalized_at or new.finalized_by is distinct from old.finalized_by)) then
    raise exception 'Event closure and finalization audit is immutable' using errcode = '42501';
  end if;
  return new;
end;
$$;
create trigger event_finalization_audit_immutable
  before update on public.events
  for each row execute function public.prevent_event_finalization_audit_mutation();
revoke all on function public.prevent_event_finalization_audit_mutation()
  from public, anon, authenticated;

-- Internal authorization recheck after acquiring the parent-event lock.
-- Hold effective authorization rows until commit; preserve existing platform
-- Administrator scope, including inactive organizations.
create function public.lock_event_finalization_manager(org_id uuid)
returns boolean language plpgsql security definer set search_path = ''
as $$
declare
  actor uuid := auth.uid();
begin
  perform 1 from auth.users u
    where u.id = actor and u.email_confirmed_at is not null
      and lower(coalesce(u.email,'')) ~ '^[^@[:space:]]+@hnu[.]edu[.]ph$'
    for share;
  if not found then return false; end if;
  perform 1 from public.platform_admins a where a.user_id = actor for share;
  if found then return true; end if;
  perform 1 from public.organization_memberships m
    join public.organizations o on o.id = m.organization_id
    where m.organization_id = org_id and m.user_id = actor
      and m.role = 'leader' and m.active and o.active
    for share of m, o;
  return found;
end;
$$;
revoke all on function public.lock_event_finalization_manager(uuid)
  from public, anon, authenticated, service_role;

-- The parent lock conflicts with M2.3's FOR SHARE. Once closure commits,
-- new scan UUIDs are denied by the unchanged ingestion RPC.
create function public.close_event(eid uuid)
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

create function public.finalize_event(eid uuid)
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

-- The underlying results relation grants no client SELECT. This deliberately
-- narrow definer exposes only a bounded, scoped page, never raw receipts.
create function public.get_event_finalized_results(
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

revoke all on function public.close_event(uuid), public.finalize_event(uuid),
  public.get_event_finalized_results(uuid, integer, integer)
  from public, anon, authenticated, service_role;
grant execute on function public.close_event(uuid), public.finalize_event(uuid),
  public.get_event_finalized_results(uuid, integer, integer) to authenticated;
