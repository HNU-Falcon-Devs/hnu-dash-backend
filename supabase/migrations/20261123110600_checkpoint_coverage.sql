-- M3.1: provisional evidence coverage only, never official attendance.
-- The caller keeps invoker RLS; no new privilege or write path is introduced.
create function public.get_event_checkpoint_coverage(
  eid uuid,
  p_limit integer default 200,
  p_offset integer default 0
)
returns table (
  student_id text,
  checkpoint_id uuid,
  checkpoint_label text,
  checkpoint_direction text,
  checkpoint_sort_order integer,
  has_accepted_scan boolean,
  accepted_received_at timestamptz
)
language plpgsql stable security invoker set search_path = ''
as $$
declare
  owning_org uuid;
  frozen_at timestamptz;
begin
  if eid is null then
    raise exception 'Event identifier is required' using errcode = '22023';
  end if;
  if p_limit is null or p_limit < 1 or p_limit > 200
     or p_offset is null or p_offset < 0 then
    raise exception 'Expected page size 1..200 and nonnegative offset'
      using errcode = '22023';
  end if;

  -- Lookup uses the caller's existing event RLS. Unknown and out-of-scope
  -- events are indistinguishable, and only verified managers may proceed.
  select e.organization_id, e.roster_frozen_at
    into owning_org, frozen_at
    from public.events e where e.id = eid;
  if not found or not public.can_manage_org(owning_org) then
    raise exception 'Event coverage not permitted' using errcode = '42501';
  end if;
  if frozen_at is null then
    raise exception 'Event roster must be frozen' using errcode = '55000';
  end if;

  -- A stable function observes one statement snapshot. The frozen roster
  -- and checkpoints fix page boundaries; accepted receipts can arrive
  -- between separate preview calls while the event remains OPEN.
  return query
    select r.student_id, c.id, c.label, c.direction, c.sort_order,
           (s.scan_id is not null), s.received_at
      from public.event_roster r
      join public.event_checkpoints c on c.event_id = r.event_id
      left join public.attendance_scans s
        on s.event_id = r.event_id
       and s.checkpoint_id = c.id
       and s.student_id = r.student_id
       and s.outcome = 'accepted'
     where r.event_id = eid
     order by r.student_id collate "C", c.sort_order, c.id
     limit p_limit offset p_offset;
end;
$$;

-- Functions otherwise default to PUBLIC EXECUTE. Only verified manager
-- accounts pass the server-side authorization check above.
revoke all on function public.get_event_checkpoint_coverage(uuid, integer, integer)
  from public, anon, authenticated;
grant execute on function public.get_event_checkpoint_coverage(uuid, integer, integer)
  to authenticated;
