# Milestone 3.1 — Provisional checkpoint coverage

This document specifies the **proposed M3.1 Backend-only** read API implemented
by the corresponding migration. The RPC is not live on hosted Supabase until
a separately approved deployment applies that migration.

M3.1 extends the implemented [M1 event and frozen-roster contract](milestone-1-web.md),
[M2.1 Staff contract](milestone-2-part-1.md), and
[M2.3 online receipt contract](milestone-2-part-3-scan-ingestion.md).
It does **not** compute or finalize official attendance.

## Authorized API

With a verified `@hnu.edu.ph` Supabase Auth session and the publishable/anon
client key:

```ts
const { data, error } = await supabase.rpc('get_event_checkpoint_coverage', {
  eid: eventId,       // UUID
  p_limit: 200,       // 1..200, defaults to 200
  p_offset: 0         // nonnegative row offset, defaults to 0
});
```

Signature:

```sql
public.get_event_checkpoint_coverage(
  eid uuid, p_limit integer default 200, p_offset integer default 0
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
```

Each returned row represents **one frozen-roster student × one configured
checkpoint**. Student IDs remain **text**, including leading zeros; labels and
direction (`IN` or `OUT`) come from the frozen checkpoint configuration.

- `has_accepted_scan = true` means precisely one immutable M2.3
  `attendance_scans.outcome = 'accepted'` receipt exists for that event,
  checkpoint and student.
- `accepted_received_at` is the original **Backend server** `received_at`
  timestamp for the accepted receipt, or `null` when missing. It is
  **not** a device capture timestamp.
- `rejected` or `duplicate` receipts never create coverage. A replay of the
  same accepted UUID does not create an additional receipt or coverage row.
- The response does not include scan UUIDs, submitting Staff identity,
  rejection reasons, official status, attendance verdicts or personal photos.

The function is read-only, `STABLE` and `SECURITY INVOKER`, with an empty
`search_path`. It invokes existing verified-user and organization-scope
authorization helpers, and the underlying roster, checkpoint, event and
receipt SELECTs continue to obey existing table RLS and grants. This is
not a new unrestricted view or a privileged evidence export.

## Pagination and consistency

The function orders rows by **Student ID** (deterministic C collation),
**checkpoint sort order**, then **checkpoint UUID**. Each student-checkpoint
pair has exactly one position while the roster and checkpoints remain frozen.

`p_limit` must be in `1..200`; `p_offset` must be a nonnegative integer.
An invalid limit or offset fails SQLSTATE `22023`. The default page is 200
rows — safely below the standard Supabase Data API 1,000-row limit.
The server does **not** silently clamp requested pages above 200.

Iterate offsets `0, 200, 400, ...` until a page has fewer than 200 rows.
For 600 students × four checkpoints (2,400 combinations), the client
retrieves 12 full pages and one empty page, with no implicit 1,000-row
truncation. An alternative consumer may stop after a returned empty page.

A single RPC request reads a consistent PostgreSQL statement snapshot.
**Separate requests are not a historical snapshot**: while an event remains
OPEN, new committed accepted scan receipts may change the booleans and
timestamps seen in a later page or repeated preview. They do not change
the fixed pagination positions. Clients must not treat this read as an
official reconciliation or finalization boundary.

## Authorization and errors

Only a verified platform administrator or an active, verified `leader` of
the event's **actual owning organization** may call this RPC successfully.
An active organization is required for an organization leader; existing
Backend platform-admin scope remains unchanged.

- Anonymous, unverified, wrong-domain, unrelated organization, ordinary
  Staff (even assigned Staff), inactive leaders, and other users have no
  aggregated coverage access.
- Unknown and out-of-scope events both fail SQLSTATE `42501`; do not
  leak whether the event exists.
- A visible but unfrozen event fails SQLSTATE `55000`.
- Null event IDs or invalid pagination arguments fail SQLSTATE `22023`.
- RPC `EXECUTE` is granted only to `authenticated`, not `PUBLIC`/`anon`.
  Database privileges to modify events, rosters, or scan receipts are unchanged.

The caller must **not** pass organization IDs, role labels, student IDs,
scan timestamps, or status decisions; the Backend derives its authorization
from existing server-side records.

## Explicit exclusions

No `PRESENT`, `LATE`, `ABSENT`, `INCOMPLETE`, `EXCUSED`,
required-checkpoint interpretation, sync status, event closure,
`FINALIZED`/`LOCKED` transition, corrections, offline uploads, device
time, QR decoding, or student-facing official attendance view is added.

This is provisional **online accepted-evidence coverage only**.
Institutional attendance policies from
`HNU-M3-BACKEND-ASSESSMENT-001` remain unapproved.
Mobile and Web integrations require separately authorized consumer work.
