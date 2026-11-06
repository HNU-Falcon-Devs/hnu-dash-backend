-- Milestone 1: one authority for student identity, organizations, draft events and frozen rosters.
-- Intentionally no attendance scans, status transition RPC or automatic role assignment.
create table public.students (
  student_id text primary key check (student_id ~ '^[A-Za-z0-9-]{1,64}$'),
  full_name text not null check (length(btrim(full_name)) between 1 and 160),
  program_code text not null check (program_code ~ '^[A-Z0-9-]{2,32}$'),
  year_level smallint not null check (year_level between 1 and 6),
  active boolean not null default true,
  updated_at timestamptz not null default now()
);

create table public.profiles (
  user_id uuid primary key references auth.users(id) on delete restrict,
  student_id text unique references public.students(student_id) on delete restrict,
  linked_at timestamptz not null default now()
);

-- Bootstrap a platform administrator explicitly using an approved operator SQL action.
-- Signup alone NEVER populates this table, profiles, or memberships.
create table public.platform_admins (
  user_id uuid primary key references auth.users(id) on delete restrict
);

create table public.organizations (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique check (slug ~ '^[a-z0-9-]{2,64}$'),
  name text not null check (length(btrim(name)) between 2 and 160),
  active boolean not null default true
);

create table public.organization_memberships (
  organization_id uuid not null references public.organizations(id) on delete restrict,
  user_id uuid not null references auth.users(id) on delete restrict,
  role text not null check (role in ('leader', 'staff')),
  active boolean not null default true,
  granted_by uuid not null default auth.uid() references auth.users(id),
  primary key (organization_id, user_id)
);

create table public.events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete restrict,
  created_by uuid not null default auth.uid() references auth.users(id),
  title text not null check (length(btrim(title)) between 2 and 160),
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  target_year_levels smallint[] not null default array[1,2,3,4]::smallint[],
  state text not null default 'DRAFT'
    check (state in ('DRAFT','OPEN','SYNCING','FINALIZED','LOCKED')),
  roster_frozen_at timestamptz,
  created_at timestamptz not null default now(),
  constraint event_dates_valid check (starts_at < ends_at),
  constraint event_years_valid check (
    coalesce(array_length(target_year_levels,1),0) between 1 and 6
    and target_year_levels <@ array[1,2,3,4,5,6]::smallint[]
    and array_position(target_year_levels,null) is null
  )
);

create table public.event_checkpoints (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events(id) on delete restrict,
  label text not null check (length(btrim(label)) between 2 and 80),
  direction text not null check (direction in ('IN','OUT')),
  opens_at timestamptz not null,
  closes_at timestamptz not null,
  sort_order integer not null default 0,
  constraint checkpoint_dates_valid check (opens_at < closes_at),
  unique (event_id, label)
);

create table public.event_roster (
  event_id uuid not null references public.events(id) on delete restrict,
  student_id text not null references public.students(student_id) on delete restrict,
  student_name text not null,
  program_code text not null,
  year_level smallint not null,
  frozen_at timestamptz not null,
  primary key (event_id, student_id)
);

create index events_org_schedule on public.events(organization_id,starts_at);
create index checkpoints_event on public.event_checkpoints(event_id,sort_order);
create index roster_student on public.event_roster(student_id);

-- Supabase Auth's before-user-created Postgres hook. Also configure on hosted Auth;
-- deploying this function alone does not activate the hook.
create function public.restrict_hnu_signup(event jsonb)
returns jsonb language sql stable security definer set search_path = ''
as $$
  select case
    when lower(coalesce(event->'user'->>'email','')) ~ '^[^@[:space:]]+@hnu[.]edu[.]ph$'
    then '{}'::jsonb
    else jsonb_build_object('error',
      jsonb_build_object('http_code',403,'message','A verified @hnu.edu.ph email is required'))
  end;
$$;
revoke all on function public.restrict_hnu_signup(jsonb) from public, anon, authenticated;
grant usage on schema public to supabase_auth_admin;
grant execute on function public.restrict_hnu_signup(jsonb) to supabase_auth_admin;

-- Authorization looks up verified auth.users data, NOT user-editable JWT metadata.
create function public.hnu_verified_user()
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from auth.users u where u.id = auth.uid()
      and u.email_confirmed_at is not null
      and lower(coalesce(u.email,'')) ~ '^[^@[:space:]]+@hnu[.]edu[.]ph$'
  );
$$;
create function public.is_platform_admin()
returns boolean language sql stable security definer set search_path = ''
as $$
  select public.hnu_verified_user()
    and exists (select 1 from public.platform_admins a where a.user_id = auth.uid());
$$;
create function public.can_manage_org(org_id uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
  select public.hnu_verified_user() and (
    public.is_platform_admin() or exists (
      select 1 from public.organization_memberships m
      join public.organizations o on o.id=m.organization_id
      where m.organization_id=org_id and m.user_id=auth.uid()
        and m.role='leader' and m.active and o.active
    )
  );
$$;
create function public.can_view_org(org_id uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
  select public.hnu_verified_user() and (
    public.is_platform_admin() or exists (
      select 1 from public.organization_memberships m
      join public.organizations o on o.id=m.organization_id
      where m.organization_id=org_id and m.user_id=auth.uid()
        and m.active and o.active
    )
  );
$$;
create function public.can_edit_draft_event(eid uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.events e
    where e.id=eid and e.state='DRAFT' and e.roster_frozen_at is null
      and public.can_manage_org(e.organization_id)
  );
$$;

-- All new relations are denied by default; explicitly grant only scoped operations.
alter table public.students enable row level security;
alter table public.profiles enable row level security;
alter table public.platform_admins enable row level security;
alter table public.organizations enable row level security;
alter table public.organization_memberships enable row level security;
alter table public.events enable row level security;
alter table public.event_checkpoints enable row level security;
alter table public.event_roster enable row level security;

revoke all on public.students, public.profiles, public.platform_admins,
  public.organizations, public.organization_memberships, public.events,
  public.event_checkpoints, public.event_roster from anon, authenticated;

grant select on public.profiles to authenticated;
create policy profiles_read on public.profiles for select to authenticated
  using (public.hnu_verified_user() and (user_id=auth.uid() or public.is_platform_admin()));

grant select on public.organizations to authenticated;
grant insert (slug,name) on public.organizations to authenticated;
create policy organizations_read on public.organizations for select to authenticated
  using (public.can_view_org(id));
create policy organizations_create on public.organizations for insert to authenticated
  with check (public.is_platform_admin());

grant select on public.organization_memberships to authenticated;
grant insert (organization_id,user_id,role) on public.organization_memberships to authenticated;
grant update (role,active) on public.organization_memberships to authenticated;
create policy memberships_read on public.organization_memberships for select to authenticated
  using (public.hnu_verified_user() and (user_id=auth.uid() or public.can_manage_org(organization_id)));
create policy memberships_insert on public.organization_memberships for insert to authenticated
  with check (public.is_platform_admin() and granted_by=auth.uid());
create policy memberships_update on public.organization_memberships for update to authenticated
  using (public.is_platform_admin()) with check (public.is_platform_admin());

grant select on public.events to authenticated;
grant insert (organization_id,title,starts_at,ends_at,target_year_levels) on public.events to authenticated;
create policy events_read on public.events for select to authenticated
  using (public.can_view_org(organization_id));
create policy events_insert on public.events for insert to authenticated
  with check (
    public.can_manage_org(organization_id)
    and created_by=auth.uid() and state='DRAFT' and roster_frozen_at is null
  );

grant select on public.event_checkpoints to authenticated;
grant insert (event_id,label,direction,opens_at,closes_at,sort_order)
  on public.event_checkpoints to authenticated;
grant update (label,direction,opens_at,closes_at,sort_order)
  on public.event_checkpoints to authenticated;
grant delete on public.event_checkpoints to authenticated;
create policy checkpoint_read on public.event_checkpoints for select to authenticated
  using (exists (select 1 from public.events e
    where e.id=event_id and public.can_view_org(e.organization_id)));
create policy checkpoint_create on public.event_checkpoints for insert to authenticated
  with check (public.can_edit_draft_event(event_id));
create policy checkpoint_update on public.event_checkpoints for update to authenticated
  using (public.can_edit_draft_event(event_id))
  with check (public.can_edit_draft_event(event_id));
create policy checkpoint_delete on public.event_checkpoints for delete to authenticated
  using (public.can_edit_draft_event(event_id));

grant select on public.event_roster to authenticated;
create policy roster_read on public.event_roster for select to authenticated
  using (exists (select 1 from public.events e where e.id=event_id
    and public.can_manage_org(e.organization_id)));

-- Security-definer mutations are deliberately narrow and check their own authority.
create function public.import_students(rows jsonb)
returns integer language plpgsql security definer set search_path = ''
as $$
declare
  rec jsonb;
  seen text[] := array[]::text[];
  sid text;
  n integer := 0;
begin
  if not public.is_platform_admin() then
    raise exception 'Roster import requires a platform administrator' using errcode='42501';
  end if;
  if jsonb_typeof(rows) is distinct from 'array'
     or jsonb_array_length(rows) not between 1 and 1000 then
    raise exception 'Expected an array of 1 to 1000 students' using errcode='22023';
  end if;
  for rec in select value from jsonb_array_elements(rows) loop
    if jsonb_typeof(rec) is distinct from 'object'
      or jsonb_typeof(rec->'student_id') is distinct from 'string'
      or jsonb_typeof(rec->'full_name') is distinct from 'string'
      or jsonb_typeof(rec->'program_code') is distinct from 'string'
      or jsonb_typeof(rec->'year_level') is distinct from 'number'
      or coalesce(rec->>'student_id','') !~ '^[A-Za-z0-9-]{1,64}$'
      or length(btrim(coalesce(rec->>'full_name',''))) not between 1 and 160
      or coalesce(rec->>'program_code','') !~ '^[A-Z0-9-]{2,32}$'
      or coalesce(rec->>'year_level','') !~ '^[1-6]$' then
      raise exception 'Invalid student record in import' using errcode='22023';
    end if;
    sid := rec->>'student_id';
    if sid = any(seen) then
      raise exception 'Duplicate student identifier within import' using errcode='23505';
    end if;
    seen := array_append(seen,sid);
    insert into public.students(student_id,full_name,program_code,year_level)
      values (sid,btrim(rec->>'full_name'),rec->>'program_code',(rec->>'year_level')::smallint)
      on conflict (student_id) do update set
        full_name=excluded.full_name, program_code=excluded.program_code,
        year_level=excluded.year_level, updated_at=now();
    n := n+1;
  end loop;
  return n;
end;
$$;

create function public.bind_student_account(actor_id uuid, sid text)
returns void language plpgsql security definer set search_path = ''
as $$
begin
  if not public.is_platform_admin() then
    raise exception 'Only a platform administrator may bind accounts' using errcode='42501';
  end if;
  if not exists(select 1 from auth.users u where u.id=actor_id
    and u.email_confirmed_at is not null
    and lower(coalesce(u.email,'')) ~ '^[^@[:space:]]+@hnu[.]edu[.]ph$') then
    raise exception 'Account must have a verified HNU email' using errcode='22023';
  end if;
  insert into public.profiles(user_id,student_id) values (actor_id,sid)
    on conflict (user_id) do update set student_id=excluded.student_id, linked_at=now();
end;
$$;

create function public.update_draft_event(eid uuid, new_title text, new_starts_at timestamptz,
  new_ends_at timestamptz, new_target_year_levels smallint[])
returns void language plpgsql security definer set search_path = ''
as $$
begin
  -- Locks the event row during authorization and update, preventing freeze races.
  perform 1 from public.events where id=eid for update;
  if not public.can_edit_draft_event(eid) then
    raise exception 'No editable draft event in scope' using errcode='42501';
  end if;
  update public.events set title=new_title, starts_at=new_starts_at,
    ends_at=new_ends_at, target_year_levels=new_target_year_levels where id=eid;
end;
$$;

create function public.freeze_event_roster(eid uuid)
returns integer language plpgsql security definer set search_path = ''
as $$
declare
  e public.events%rowtype;
  count_frozen integer;
begin
  select * into e from public.events where id=eid for update;
  if not found or not public.can_edit_draft_event(eid) then
    raise exception 'No editable draft event in scope' using errcode='42501';
  end if;
  insert into public.event_roster(event_id,student_id,student_name,program_code,year_level,frozen_at)
    select eid,s.student_id,s.full_name,s.program_code,s.year_level,now()
    from public.students s where s.active and s.program_code='BSIT'
      and s.year_level=any(e.target_year_levels);
  get diagnostics count_frozen = row_count;
  if count_frozen=0 then
    raise exception 'Cannot freeze an empty eligible roster' using errcode='22023';
  end if;
  update public.events set roster_frozen_at=now() where id=eid;
  return count_frozen;
end;
$$;

revoke all on function public.hnu_verified_user(), public.is_platform_admin(),
  public.can_manage_org(uuid), public.can_view_org(uuid),
  public.can_edit_draft_event(uuid), public.import_students(jsonb),
  public.bind_student_account(uuid,text),
  public.update_draft_event(uuid,text,timestamptz,timestamptz,smallint[]),
  public.freeze_event_roster(uuid) from public, anon;
grant execute on function public.hnu_verified_user(), public.is_platform_admin(),
  public.can_manage_org(uuid), public.can_view_org(uuid),
  public.can_edit_draft_event(uuid), public.import_students(jsonb),
  public.bind_student_account(uuid,text),
  public.update_draft_event(uuid,text,timestamptz,timestamptz,smallint[]),
  public.freeze_event_roster(uuid) to authenticated;
