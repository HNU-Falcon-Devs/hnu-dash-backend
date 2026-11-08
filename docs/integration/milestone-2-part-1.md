# Milestone 2, Part 1 — Staff assignment and activation

Backend-owned description of **implemented** Supabase/PostgREST operations.
Read [Milestone 1 Web integration](milestone-1-web.md) for existing event/roster
setup; this document lists only new or changed access/operations. PR #2 is a
closed, superseded proposal, **not** an API specification.

## Authorization

All new RPCs require a verified `@hnu.edu.ph` Supabase Auth session.
Only a platform Administrator or an active organization `leader` in the
owning organization may assign/revoke Staff or open an event. The Backend
checks its own tables and Auth verification; user metadata, client role
labels, and caller-supplied organization IDs do not grant permissions.
Use an authenticated session with a publishable/anon key, never a
service-role key in Web/Mobile.

An eligible assignee must be a verified HNU Auth user with an **active**
`organization_memberships` row (`role = 'staff'`) for the event's organization.
No generic organization membership or assignment permits management.
The Backend does not require a student-account binding for Staff accounts.

## Implemented operations

| Operation | Supabase client call | Result / constraints |
| --- | --- | --- |
| Assign Staff | `rpc('assign_event_staff',{eid,staff_uid})` | Returns new assignment UUID. Manager only, event must be DRAFT or OPEN, organization active, assignee verified active Staff in owning organization. Duplicate active pair fails SQLSTATE 23505. |
| List assignments | `from('event_staff').select('id,event_id,staff_user_id,assigned_at,assigned_by,revoked_at,revoked_by').eq('event_id',eid)` | Managers see assignment periods (including revoked history) for events in scope. Staff see only their own currently valid active assignment. |
| Revoke Staff | `rpc('revoke_event_staff',{assignment_id})` | Returns revoked assignment UUID, records server time/actor; revoking a revoked row fails 55000. Manager only. Past attribution retained. |
| Check effective Staff access | `rpc('can_access_assigned_event',{eid})` | Boolean for the calling authenticated Staff account; requires both active Staff membership and unrevoked event assignment, active organization and verified HNU Auth. |
| Activate event | `rpc('open_event',{eid})` | Returns a one-row array of `{event_id,event_state:'OPEN',opened_at}` with authoritative timestamp. Only DRAFT → OPEN. |

`open_event` requires an active owning organization, DRAFT state, a
previously frozen and **nonempty** event roster, a valid event schedule
and at least one in-schedule configurable attendance checkpoint. An IN
checkpoint alone is sufficient; no OUT pair is required. The RPC **does not
freeze the roster automatically** and does not require a minimum assigned
Staff count (that policy has not been approved). Repeated activation fails
SQLSTATE 55000; missing/invalid prerequisites fail 22023; unauthorized
attempts fail 42501.

All operations are atomic within their PostgreSQL transactions. Opening
serializes on the existing parent-event lock shared with checkpoint edits
and roster freezing; concurrent competing attempts cannot both succeed.
Event `opened_at` is backend-generated; browsers have no direct event
UPDATE or event_staff INSERT/UPDATE/DELETE grants.

## Online reads and revocation

An assigned Staff member can SELECT only their assigned events, associated
checkpoints, frozen event roster, and own effective active assignment.
This intentionally narrows Milestone 1's earlier organization-wide Staff
event/checkpoint reads. Leaders and Administrators retain scoped management
reads; unauthorized users receive filtered rows. Assignment revocation
immediately prevents subsequent authorized **online** reads, even if an
existing JWT has not expired. Revoking or deactivating the organization
Staff membership likewise removes effective assignment access.

Previously downloaded offline data cannot be remotely erased while a device
is disconnected. Staff removal during offline capture, token lifetime,
device storage and scan-upload validation are **deferred** and require
separate scope/contract approval. No mobile sync or scan acceptance is
provided here.

## Out of scope

No QR decoding, scan records, offline uploads, automatic event status
propagation, attendance results, corrections, later lifecycle transitions,
HNU MIS, external servers, or hosted database changes. `OPEN` records only
the authoritative event state; checkpoint-specific capture windows must
be enforced by a future attendance-ingest workflow.
