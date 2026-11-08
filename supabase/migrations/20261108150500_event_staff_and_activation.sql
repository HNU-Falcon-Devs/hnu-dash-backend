-- Milestone 2, Part 1: scoped Staff assignment and the sole DRAFT -> OPEN transition.
-- No scan processing, sync, reconciliation, or later lifecycle transitions.
alter table public.events
  add column opened_at timestamptz;

-- One row represents one assignment period. Revoked rows remain as attribution
-- evidence, including the assigning/revoking accounts and server timestamps.
create table public.event_staff (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events(id) on delete restrict,
  staff_user_id uuid not null references auth.users(id) on delete restrict,
  assigned_at timestamptz not null default clock_timestamp(),
  assigned_by uuid not null references auth.users(id) on delete restrict,
  revoked_at timestamptz,
  revoked_by uuid references auth.users(id) on delete restrict,
  constraint event_staff_revoke_pair check (
    (revoked_at is null and revoked_by is null)
    or (revoked_at is not null and revoked_by is not null)
  ),
  constraint event_staff_revoke_time check (
    revoked_at is null or revoked_at >= assigned_at
  )
);
create unique index event_staff_one_active_per_user
  on public.event_staff(event_id, staff_user_id) where revoked_at is null;
create index event_staff_active_actor
  on public.event_staff(staff_user_id, event_id) where revoked_at is null;

alter table public.event_staff enable row level security;
revoke all on public.event_staff from public, anon, authenticated;

-- SECURITY DEFINER prevents mutual recursion between events/event_staff RLS.
-- This is an effective-authorization check: revoked event assignments, revoked
-- organization Staff memberships, inactive organizations and unverified accounts
-- immediately lose new online access even when the JWT is still valid.
create function public.can_access_assigned_event(eid uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
  select public.hnu_verified_user() and exists (
    select 1
      from public.event_staff a
      join public.events e on e.id = a.event_id
      join public.organizations o on o.id = e.organization_id
      join public.organization_memberships m
        on m.organization_id = e.organization_id and m.user_id = a.staff_user_id
     where a.event_id = eid and a.staff_user_id = auth.uid()
       and a.revoked_at is null
       and m.role = 'staff' and m.active and o.active
  );
$$;
revoke all on function public.can_access_assigned_event(uuid)
  from public, anon, authenticated;
grant execute on function public.can_access_assigned_event(uuid) to authenticated;

-- Managers see all assignment periods in their organization. Staff can see
-- only their own currently effective assignment, never another Staff's rows.
grant select on public.event_staff to authenticated;
create policy event_staff_read on public.event_staff
for select to authenticated
using (
  exists (
    select 1 from public.events e where e.id = event_id
      and public.can_manage_org(e.organization_id)
  )
  or (
    staff_user_id = auth.uid() and revoked_at is null
    and public.can_access_assigned_event(event_id)
  )
);

-- An organization Staff membership by itself previously exposed all of the
-- organization's events/checkpoints. That would defeat event revocation.
-- Keep Leader/Admin management access and limit Staff to assigned events.
drop policy events_read on public.events;
create policy events_read on public.events
for select to authenticated
using (
  public.can_manage_org(organization_id)
  or public.can_access_assigned_event(id)
);

drop policy checkpoint_read on public.event_checkpoints;
create policy checkpoint_read on public.event_checkpoints
for select to authenticated
using (
  exists (
    select 1 from public.events e where e.id = event_id
      and (public.can_manage_org(e.organization_id)
           or public.can_access_assigned_event(event_id))
  )
);

drop policy roster_read on public.event_roster;
create policy roster_read on public.event_roster
for select to authenticated
using (
  exists (
    select 1 from public.events e where e.id = event_id
      and (public.can_manage_org(e.organization_id)
           or public.can_access_assigned_event(event_id))
  )
);

-- All assignment mutations go through tightly scoped RPCs, never direct
-- table writes. The event row serializes assignment with event activation.
create function public.assign_event_staff(eid uuid, staff_uid uuid)
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

create function public.revoke_event_staff(assignment_id uuid)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare
  assignment public.event_staff%rowtype;
  owning_org uuid;
begin
  select * into assignment
    from public.event_staff a where a.id = assignment_id for update;
  if not found then
    raise exception 'Assignment not found or not permitted'
      using errcode = '42501';
  end if;
  select e.organization_id into owning_org
    from public.events e where e.id = assignment.event_id;
  if not public.can_manage_org(owning_org) then
    raise exception 'Assignment not permitted in this organization'
      using errcode = '42501';
  end if;
  if assignment.revoked_at is not null then
    raise exception 'Assignment already revoked' using errcode = '55000';
  end if;
  update public.event_staff
     set revoked_at = clock_timestamp(), revoked_by = auth.uid()
   where id = assignment_id;
  return assignment_id;
end;
$$;

-- The parent-row lock is shared with checkpoint writes and roster freezing.
-- No implicit roster freeze and no later state transition are introduced.
create function public.open_event(eid uuid)
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

revoke all on function public.assign_event_staff(uuid, uuid),
  public.revoke_event_staff(uuid), public.open_event(uuid)
  from public, anon, authenticated;
grant execute on function public.assign_event_staff(uuid, uuid),
  public.revoke_event_staff(uuid), public.open_event(uuid) to authenticated;
