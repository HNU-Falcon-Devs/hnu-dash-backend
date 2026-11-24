# Milestone 4.1 — Bounded offline evidence (synthetic-only)

Backend-owned contract for [Issue #15](https://github.com/HNU-Falcon-Devs/hnu-dash-backend/issues/15)
and the [approved M4 direction](https://github.com/HNU-Falcon-Devs/hnu-dash-backend/issues/14#issuecomment-7135931314).
This migration is not deployed or approved for real data. It does not replace
[M2.3 online ingestion](milestone-2-part-3-scan-ingestion.md) or the online-only
[M3.2A lifecycle](milestone-3-part-2a-attendance-finalization.md).

## RPCs

Use the authenticated verified HNU session and publishable key, never service-role.
All IDs below are UUIDs unless explicitly text; times are PostgreSQL timestamptz
(send ISO 8601 with offset). No client role, outcome, actor or server time.

| RPC and exact parameters | Response (one JSON object unless noted) |
| --- | --- |
| `enable_event_offline(eid)` | Boolean true; owning manager only, DRAFT only; repeat in DRAFT returns true. |
| `prepare_offline_capture(p_event_id,p_request_id)` | preparation_id, request_id, event_id, assignment_id, staff_user_id, issued_at, expires_at, upload_cutoff, event_title, event_starts_at, event_ends_at, checkpoints (array of id,label,direction,opens_at,closes_at), replayed (boolean). |
| `submit_offline_capture(p_preparation_id,p_capture_id,p_checkpoint_id,p_student_id,p_claimed_at)` | capture_id, preparation_id, received_at, status (always "submitted"), replayed (boolean). |

The opt-in is one-way in M4.1; no disabling/reopening route. DRAFT checkpoint
and event edits continue under existing freeze rules. Activation derives
upload_cutoff = last frozen checkpoint close + exactly 24 hours. Default
false/null preserves all previous events. Policy/cutoff cannot be edited
after activation. No direct client writes or reads of preparation/claim tables.

## Preparation

An actual active verified Staff assignment is required, including current
organization and membership. Backend records the exact assignment period,
not merely the event/user pair. New issuance requires offline-enabled OPEN
with a frozen nonempty roster and valid remaining checkpoint window.
Expiry = min(server issuance + 8 hours, last checkpoint close).
One active preparation per assignment is enforced under the event row lock.
The request UUID is stable across a lost response; an authorized identical
retry returns the original context and expiry (even after expiry/closure),
not a fresh authorization. Reassignment/revocation denies old replay.
An explicit new request after the old expiry is a fresh online preparation
subject to the same checks; no overlapping lease, extension or history rewrite.
No offline renewal/revalidation API. A caller must treat expired context as
expired and reconnect before new capture after restart/account change.
Preparation identity is correlation, not a bearer permit, trusted device
assertion, or evidence of actual capture time. No roster is returned.

## Claims

Use a stable capture UUID and immutable payload (including timestamp instant).
Student ID is canonical text, /^[A-Za-z0-9-]{1,64}$/; preserve leading zeros.
Capture mode is fixed: an unknown online receipt must use the original M2.3 RPC,
never this RPC. Online scan UUID and offline capture UUID are separate typed
namespaces; neither resolves to the other's receipt even if bytes match.

New claims require live verified Staff authorization for the exact preparation
assignment period, an event-matching checkpoint, and OPEN or SYNCING before
the server cutoff (exclusive). Upload after capture expiry is allowed.
The private review_eligible flag means only that the claimed time lies in
[issued_at,expires_at), [opens_at,closes_at), is not after server receipt,
and the Student ID is in the frozen roster. It is NOT proof of capture time
or accepted attendance. Scoped but ineligible claims are retained with the
same generic acknowledgement. Invalid formats/foreign checkpoint scope are
denied. No raw table SELECT or eligibility oracle is exposed. No roster,
acceptance or review result is returned. received_at is server-generated.

Still-authorized identical retries return the original acknowledgement/time
before state/cutoff checks; no new row. A conflicting capture UUID fails
without changing prior evidence. Revocation/inactive membership/org/unverified
identity denies replay as well as new claims. Reassignment does not revive
old preparation. A same-UUID retry is the bounded acknowledgement lookup;
no listing/status/reconciliation API in M4.1.

Errors: 42501 unauthorized or foreign/unknown scope (including old assignment);
22023 invalid/null input or missing frozen prerequisites; 55000 state, cutoff,
or active preparation conflict; 23505 conflicting immutable capture ID;
40001 unconfirmed persistence. Transport, cast failures and malformed
responses are not acknowledgement; preserve payload and retry the same ID.
For preparation request collisions outside the caller's exact assignment,
return generic 42501. No eligibility distinctions in the acknowledgement.

## Integrity and lifecycle

Parent event lock serializes preparation, upload, closure and finalization;
live identity, organization, membership and exact assignment are locked
through commit. Unique IDs, composite scope FKs and immutable-row triggers
protect history. Offline claims never enter attendance_scans, coverage or
attendance_records. Existing online RPC and accepted-slot uniqueness remain
unchanged, including post-close authorized identical replay.
Offline-enabled nonfinalized events fail finalize_event with 55000, even
with zero claims/preparations and through old clients; no bypass flag.
Existing FINALIZED replay and online-only finalization are unchanged.

Additive migration only, no backfill of existing evidence or result mutation.
Disable operational use until approved M4.2 reconciliation and downstream
acceptance; do not roll back to an ungated finalizer for enabled events.
No purge, recovery, export, acceptance/promotion, loss disposition, sealing,
completion, device trust, real QR, Mobile/Web or institutional policy here.
M4.2 must separately define admissibility, loss exceptions and receipt
provenance; M4.3 owns encrypted local queue and restart behavior.
