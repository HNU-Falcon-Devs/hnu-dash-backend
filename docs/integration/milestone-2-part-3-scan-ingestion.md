# Milestone 2.3 — Online scan-ingestion contract

This is the Backend-owned, implemented **online-only** Supabase/PostgREST contract.
It extends [Milestone 2, Part 1](milestone-2-part-1.md); the historical closed
PR #2 is superseded and is not a supported API. No Middleware/Edge Function.

## Credential and scan identity

For this RPC, **`p_student_id` is the canonical Student ID Number as a
string**, exactly as stored in the frozen `event_roster.student_id` column
(e.g. `"00000123456"`). Leading zeros must not be parsed away.
Allowed format: `^[A-Za-z0-9-]{1,64}$`. This contract does **not** prescribe
or decode the physical HNU ID's QR content. A Mobile component must not treat
an opaque QR payload as a student number without a separately approved
credential mapping/decoding rule.

`p_scan_id` is a client-generated UUID, preferably UUIDv4, stable across
retries. Mobile's existing SQLite `ProvisionalScan.id` already stores such a
stable UUID. Mobile currently does **not** persist a checkpoint ID or submit
scans; this contract does not claim Mobile compatibility is complete.

## Ingestion RPC

Use the **authenticated user's** Supabase client and publishable/anon key,
not a service-role key:

```ts
const { data, error } = await supabase.rpc("ingest_attendance_scan", {
  p_scan_id: "65000000-0000-4000-8000-000000000001",
  p_event_id: "<event-uuid>",
  p_checkpoint_id: "<checkpoint-uuid>",
  p_student_id: "00000123456"
});
```

All four inputs are required. `p_student_id` is `text` and the other three
fields are UUIDs; no client-provided timestamp, role, scan outcome, or officer
identity is accepted.

On a successful RPC call, `data` is **one JSON object**:

```json
{
  "scan_id": "65000000-0000-4000-8000-000000000001",
  "outcome": "accepted",
  "received_at": "2026-11-08T13:00:00+00:00",
  "replayed": false
}
```

The timestamp above is illustrative, **not** a live event receipt. The
Backend creates it using its database clock; it is the **server receipt
time**, not the device capture time. Outcomes:

- `accepted`: online submission passed live authorization, event OPEN,
  matching event checkpoint with its server-time window open, and frozen
  roster membership; only one accepted capture per
  `(event_id, checkpoint_id, student_id)`.
- `rejected`: authorized submission against a valid event checkpoint was
  recorded, but the event is not OPEN, the **server** receipt time is outside
  its `[opens_at, closes_at)` window, or the student is absent from the
  event's frozen roster. Reasons are intentionally not distinguished in the
  caller-facing response to avoid exposing roster membership.
- `duplicate`: a **different scan UUID** targeted a capture already
  accepted for that event/checkpoint/student. The attempt is durably recorded
  with its own UUID/time, but is not another accepted capture.
- `replayed: true`: this scan UUID and its entire payload (including the
  authenticated submitting Staff UUID) match an already committed receipt.
  The Backend returns the **original** outcome and receipt timestamp,
  without creating another record. The original outcome can be any of the
  above three values.

An identical retry is allowed after a checkpoint's window closes **only if
the user still has effective online Staff authorization for the event**.
Revocation, inactive membership/organization, unverified identity, or
cross-event assignment loss blocks even replaying an old scan. Reusing an
existing scan UUID for any different event, checkpoint, Student ID, or
submitting Staff account fails with `23505`. It never overwrites evidence.
A new UUID after a prior `rejected` attempt may be revalidated against the
server time and conditions at its **new** receipt.

## Required server-side permissions and time rules

A request is permitted only when **all** apply:

1. Caller is an authenticated, email-confirmed `@hnu.edu.ph` Auth account,
   checked against Backend `auth.users` (not caller metadata).
2. Caller has an active organization `staff` membership **and** an unrevoked
   assignment to this exact event, with an active owning organization.
3. The checkpoint belongs to this exact event (including for a rejected
   receipt). Incorrect, missing, or cross-event checkpoint references are
   denied without exposing another organization's records.

The event must be `OPEN`, the server receipt timestamp must lie within
`opens_at <= received_at < closes_at`, and the Student ID must be in the
immutable frozen event roster **for the receipt to be accepted**.
All validation, the receipt insert, duplicate classification, and unique
constraints occur transactionally in PostgreSQL. Event-row and authorization
row locks serialize against competing state changes and Staff revocations.

Failure codes: `42501` for unauthenticated, unauthorized, inactive or
out-of-scope event/checkpoint operations; `22023` for invalid inputs;
`23505` for conflicting scan UUID reuse; `40001` if evidence persistence
cannot be safely confirmed. RPC/network/availability failures are **not**
receipts. Never interpret a missing response or a transport timeout as
acceptance; retry the **same UUID and unchanged payload**, while still
authorized. Do not log raw student credentials or SQL messages.

## Evidence visibility and authority

`public.attendance_scans` stores immutable evidence:
`scan_id`, `event_id`, `checkpoint_id`, `student_id` (text),
`submitted_by` (from `auth.uid()`), `received_at` (server clock) and
`outcome`. Clients have **SELECT only**, scoped by RLS:
authorized organization Leaders/Platform Administrators for their events,
or the original Staff submitter while still effectively assigned.
There is no direct client INSERT, UPDATE, or DELETE; mutation attempts are
also blocked by the immutable-evidence trigger.

A stored `accepted` scan or `replayed` receipt is **capture evidence, not
finalized/official attendance**. No reconciliation, attendance rollup, device
capture-time authority, officer correction, sync period, or lifecycle
transition is implemented here. Offline Mobile uploads must wait for an
explicit policy and a separately approved contract; this online RPC does not
implicitly validate old locally captured scans.
