# Milestone 1 — Web integration (approved foundation only)

The backend is **Supabase Auth + PostgreSQL/PostgREST**. No Express server.
This milestone implements draft-event and roster operations, **not** scan upload,
attendance finalization, public student search, or production deployment.
See PR #2 for an **unapproved** future integration proposal; this file records
only operations actually implemented here.

## Authentication and permissions

- Clients use Supabase Auth (the public anon/publishable key, NEVER service_role).
- Signup must use a verified `@hnu.edu.ph` address. Local CLI config enables
  email confirmations and the `before_user_created` Postgres Auth hook.
  **A hosted Supabase project must have both manually configured and verified
  prior to accepting signups**: Authentication > Hooks > Before User Created >
  Postgres function `public.restrict_hnu_signup`; and email confirmation ON.
  Local Inbucket supports development without external SMTP; hosted email delivery
  may require an approved SMTP provider. No SMTP account is provisioned here.
- An HNU email proves only control of an email address, **not** a student ID or
  privilege. Account/student linkage is administrator-only with human verified
  institutional evidence. There is no student self-claim.
- Platform administrators are provisioned by an authorized database operator,
  never from signup or user-editable metadata. Example (after independently
  verifying the user's HNU account and permission):
  `insert into public.platform_admins(user_id) values ('<verified-auth-uuid>');`
  This privileged bootstrap is an operator action, not a browser API.
- A platform admin may create organizations and assign `leader` or `staff`
  memberships; only a verified, active leader in an organization (or platform
  admin) can manage its drafts, checkpoints, or roster.
- Student information isn't generally selectable by browser clients. Event roster
  snapshots are visible only to the owning organization's leader/admin.
- All event-facing times are `timestamptz` (ISO/RFC3339 offsets when sent).
  Display these in `Asia/Manila`.

## Supported Web operations

Call Supabase PostgREST with an authenticated user session. All table operations
are governed by RLS and narrow column privileges.

| Operation | Supabase call / table | Permissions and behavior |
| --- | --- | --- |
| My organizations | `from('organizations').select(...)` | Scoped member or admin |
| My organization memberships | `from('organization_memberships').select(...)` | Own entries or authorized leader/admin |
| Create organization | `from('organizations').insert({slug,name})` | Platform admin only |
| Assign/update org member | `from('organization_memberships').insert({organization_id,user_id,role})`, or update `role,active` | Platform admin only; no user self-promotion |
| Create event | `from('events').insert({organization_id,title,starts_at,ends_at,target_year_levels}).select()` | Leader/admin of organization; starts in DRAFT only |
| List/get events | `from('events').select(...).eq('organization_id',id)` | Org member/admin; RLS scope independent of supplied filter |
| Update draft event | `rpc('update_draft_event',{eid,new_title,new_starts_at,new_ends_at,new_target_year_levels})` | Leader/admin while DRAFT and not frozen |
| Manage checkpoints | `from('event_checkpoints').insert(...)`, `update({label,direction,opens_at,closes_at,sort_order})`, or `delete()` | Leader/admin, only editable DRAFT; `event_id` is immutable |
| Import roster CSV | Parse to JSON `{rows:[{student_id,full_name,program_code,year_level}]}` then `rpc('import_students',{rows})` | Platform admin only, atomic import; upserts existing IDs; duplicate IDs within same batch reject all |
| Freeze event roster | `rpc('freeze_event_roster',{eid})` | Leader/admin; requires at least one valid checkpoint within the event schedule and a nonempty eligible BSIT roster; creates immutable snapshot |
| Read frozen roster | `from('event_roster').select(...).eq('event_id',eid)` | Leader/admin of owning organization |
| Bind verified student account | `rpc('bind_student_account',{actor_id,sid})` | Platform admin only, after independent ID verification; unique student link |

`event_checkpoints` columns: `event_id`, `label`, `direction` (`IN`/`OUT`),
`opens_at`, `closes_at`, `sort_order`. They are arbitrary per event, with
no fixed daily sessions and no universal Time-Out requirement.
Every checkpoint must have `opens_at < closes_at`, be wholly contained in the
owning event's `starts_at`–`ends_at` window, and be configured **before**
freezing. Updating an event's schedule cannot exclude existing checkpoints.
A checkpoint change and roster freeze serialize on the event row: after a
successful freeze, checkpoint additions/edits/deletions are rejected.
A valid IN-only event is permitted; no arbitrary Time-Out is added.

`events.target_year_levels` is a nonempty smallint array (1–6), default
`[1,2,3,4]`. This pilot roster intentionally selects active BSIT students.
Call freeze only after all CSV imports and event draft configuration are correct.
There is **no unfreeze or roster-edit API**. Lifecycle transitions remain unimplemented;
events stay DRAFT. Do not bypass this restriction through service-role clients.

## CSV conversion

`python3 scripts/csv_to_import_json.py test/fixtures/synthetic_roster.csv`

CSV header must be exactly:
`student_id,full_name,program_code,year_level`.
The converter understands standard quoted CSV names, retains zero-prefixed IDs,
rejects duplicate/malformed rows, and outputs the `import_students` RPC
argument JSON. The database *independently* revalidates all values, applies
the complete batch transactionally, and rejects unauthorized calls. Maximum
1000 records per batch; no real student data should be committed or placed in logs.

Import upsert changes the current student record but never rewrites an already
frozen event snapshot. An attempted duplicate ID *within* a batch aborts the
whole transaction. For auditability, administrators should retain the source
and approval evidence in an institution-approved restricted location, not Git.

## Scope not yet approved for consumer integration

PR #2's event-wide `TIME_IN`/`TIME_OUT` assumptions must become
`checkpoint_id`/per-checkpoint windows and conditional attendance requirements.
Its MIS identity assumptions must change to Supabase Auth. No concrete scan
payloads, reconciliation, client release gates, or finalization operations are
implemented here. These contract changes need orchestrator approval; PR #2
must not be silently edited or merged.
