-- Milestone 2.3: online, authoritative scan receipts only.
-- No offline upload, attendance reconciliation, or event transitions.
create table public.attendance_scans (
  scan_id uuid primary key,
  event_id uuid not null references public.events(id) on delete restrict,
  checkpoint_id uuid not null references public.event_checkpoints(id) on delete restrict,
  student_id text not null check (student_id ~ '^[A-Za-z0-9-]{1,64}$'),
  submitted_by uuid not null references auth.users(id) on delete restrict,
  received_at timestamptz not null default clock_timestamp(),
  outcome text not null check (outcome in ('accepted', 'rejected', 'duplicate'))
);

-- One accepted capture per event/checkpoint/student; retries and fresh duplicate
-- attempts are separately preserved by scan_id, not upserted over evidence.
create unique index attendance_scans_one_accepted_capture
  on public.attendance_scans(event_id, checkpoint_id, student_id)
  where outcome = 'accepted';
create index attendance_scans_event_receipts
  on public.attendance_scans(event_id, received_at);

alter table public.attendance_scans enable row level security;
revoke all on public.attendance_scans from public, anon, authenticated;
grant select on public.attendance_scans to authenticated;
create policy attendance_scans_read on public.attendance_scans
  for select to authenticated
  using (
    exists (
      select 1 from public.events e
      where e.id = event_id and public.can_manage_org(e.organization_id)
    )
    or (submitted_by = auth.uid() and public.can_access_assigned_event(event_id))
  );

-- No UPDATE or DELETE, even through ordinary operator SQL: receipts are evidence.
create function public.prevent_attendance_scan_mutation()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  raise exception 'Scan evidence is immutable' using errcode = '42501';
end;
$$;
create trigger attendance_scans_immutable
  before update or delete on public.attendance_scans
  for each row execute function public.prevent_attendance_scan_mutation();
revoke all on function public.prevent_attendance_scan_mutation()
  from public, anon, authenticated;

-- The only client write interface. No client-supplied timestamp, outcome or actor.
-- Return a durable receipt; it is NOT an official attendance determination.
create function public.ingest_attendance_scan(
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
    if prior.event_id is distinct from p_event_id
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
  if ev.state = 'OPEN'
    and receipt_time >= checkpoint.opens_at
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
      if prior.event_id is distinct from p_event_id
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
revoke all on function public.ingest_attendance_scan(uuid, uuid, uuid, text)
  from public, anon, authenticated;
grant execute on function public.ingest_attendance_scan(uuid, uuid, uuid, text)
  to authenticated;
