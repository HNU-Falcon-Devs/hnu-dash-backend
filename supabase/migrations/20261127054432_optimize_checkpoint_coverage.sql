-- HNU-DASH-COVERAGE-PERF-002: keep caller RLS and bound repeated work.
-- The existing partial unique index guarantees at most one accepted receipt per pair.
create or replace function public.get_event_checkpoint_coverage(
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
  -- Evaluate each visible roster/checkpoint relation once. A fixed pair has
  -- zero or one accepted receipt, so receipt presence cannot affect pagination.
  -- The final lateral lookup is deliberately non-flattenable (OFFSET 0):
  -- it probes only the bounded page's full event/checkpoint/student keys.
  return query
    with visible_roster as materialized (
      select r.student_id
        from public.event_roster r
       where r.event_id = eid
    ), visible_checkpoints as materialized (
      select c.id, c.label, c.direction, c.sort_order
        from public.event_checkpoints c
       where c.event_id = eid
    ), coverage_page as materialized (
      select r.student_id, c.id, c.label, c.direction, c.sort_order
        from visible_roster r cross join visible_checkpoints c
       order by r.student_id collate "C", c.sort_order, c.id
       limit p_limit offset p_offset
    )
    select p.student_id, p.id, p.label, p.direction, p.sort_order,
           (s.scan_id is not null), s.received_at
      from coverage_page p
      left join lateral (
        select a.scan_id, a.received_at
          from public.attendance_scans a
         where a.event_id = eid
           and a.checkpoint_id = p.id
           and a.student_id = p.student_id
           and a.outcome = 'accepted'
         offset 0
      ) s on true
     order by p.student_id collate "C", p.sort_order, p.id;
end;
$$;
-- CREATE OR REPLACE retains the existing function owner and EXECUTE ACL.
