# Offline-first B1 foundation — policy v2 (fixture-only)

Authority: [Backend #27 approved decisions](https://github.com/HNU-Falcon-Devs/hnu-dash-backend/issues/27#issuecomment-7221596891), [B1 package](https://github.com/HNU-Falcon-Devs/hnu-dash-backend/issues/27#issuecomment-7221610749), [owner authorization](https://github.com/HNU-Falcon-Devs/hnu-dash-backend/issues/27#issuecomment-7223700306). Base: `3a1f3a11a0db1cab2bc0716949fa5a7ab761cae3`.

**Historical B1 foundation boundary.** The [B2 reconciliation contract](offline-first-b2-reconciliation.md) describes the additive successor fixture lifecycle; B1 preparation, closure and extension RPC contracts remain unchanged. Ordinary successor activation remains disabled.

**B1 is inert for ordinary users.** This is the canonical contract for the additive foundation, NOT a usable successor capture or sync contract, pilot policy or deployment approval. Existing M2.3/M3.2A/M4.1/M4.2 contracts remain canonical for v1. No client should select v2, consume these RPCs for operational attendance or migrate a queue to v2 until separately approved B2 and coordinated consumer acceptance.

## Persisted model

- `events.policy_version` is immutable, NOT NULL, 1 or 2, default 1 (including all preexisting events and ordinary new drafts). `events.sync_deadline` is null for v1 and v2 DRAFT/OPEN; for v2 SYNCING it is finite and within closure + 24..168 elapsed hours. v2 retains `offline_enabled=false` and `offline_upload_cutoff=null`; legacy opt-in/cutoff and lease semantics remain unchanged for v1. v2 cannot reach FINALIZED or LOCKED in B1.
- `offline_b1_private.closures`: one immutable row per event, unique request UUID, server closure instant/actor, normalized reason, overlap acknowledgment, canonical effective-window payload and initial deadline. `effective_windows`: one immutable row per exact (event, checkpoint) referencing the frozen original checkpoint and closure; planned windows stay on `event_checkpoints` unmodified.
- `deadline_extensions`: immutable request UUID, event, previous/new deadline, normalized reason, actor and server adjustment time. Event deadline and audit insert are one transaction; prior receipts retain prior values.
- `preparations`: separate immutable v2 preparation UUID and unique request UUID, event, exact assignment period (composite FK), owner, server-issued anchor instant and immutable response context; one outstanding preparation per assignment. No expiry column, token, roster cache or photo. v1 leases and their eight-hour/checkpoint bound remain untouched.
- Private schema/tables have no PUBLIC, anon, authenticated or service-role access; RLS enabled and no ordinary policies. New functions revoke default EXECUTE and grant only authenticated (not anon or service role). Security-definer functions use empty search path, fixed UTC rendering and existing live database identity/role locks; no JWT role/owner claims are accepted. The event guard rejects version changes even from the fixture owner, denies non-postgres v2 writes, requires audit before v2 closure/deadline changes, and permits only DRAFT→OPEN→SYNCING in B1. Ordinary creation has no version column grant; no new public toggle or v2 creation/open RPC.

## RPCs (fixture-only, JSON result)

All three require a live verified HNU identity and event-specific authority, not merely an authenticated database role. Each parent event row is locked FOR UPDATE before live authorization rows; preparation shares exact assignment/membership/org/identity locks with existing revocation semantics. All writes are atomic. Inputs are named below; UUIDs are nonnull. `replayed` is false for original durable success, true for exact authorized retry. Each operation has its own global request UUID namespace; reuse for different normalized payload/scope conflicts. Authorized manager replays are scoped to the event/current role, return the **original** actor/time, and do not confer mutation rights. Preparation replay is bound to original Staff and assignment. No new preparation is issued on retry.

### `prepare_offline_capture_v2(p_event_id uuid, p_assignment_id uuid, p_request_id uuid)`

Active verified Staff with exact unrevoked assignment, active organization and Staff membership only. New issuance requires frozen nonempty roster and finite in-schedule checkpoints in DRAFT or OPEN. The assignment and roster freeze must not postdate the anchor. No new issuance after closure, no replacement/renewal and no expiry from the planned schedule or eight-hour legacy lease. Revocation/reassignment denies old-assignment replay; even when already closed, an exact retry with unchanged live original scope may return the immutable receipt, **not** new capture/upload authority.

Result keys: `policy_version=2, preparation_id, request_id, event_id, organization_id, assignment_id, staff_user_id, issued_at, assignment_assigned_at, roster_frozen_at, event_title, event_starts_at, event_ends_at, prepared_event_state, checkpoints, replayed`. Checkpoint objects are `id,label,direction,opens_at,closes_at`, ordered by sort order then ID, original windows only. `prepared_event_state` is historical at issuance (not a live authorization/status read). `issued_at` is the server anchor candidate; not a proof of device time/capture authenticity, lease or upload credential. DRAFT issuance does not open an event. B2/M1 must define actual clock evidence, anchor uncertainty and safe restart/capture semantics.

### `close_event_v2(p_event_id uuid, p_request_id uuid, p_windows jsonb, p_overlap_acknowledged boolean, p_reason text)`

Active owning leader or existing verified platform Admin (same scope as legacy closure; no new Admin privilege). New closure requires OPEN and frozen nonempty roster. Mapping must contain exactly one object for every frozen checkpoint (nonempty, bounded by that exact set); no missing, foreign, duplicated or additional entries/keys. Example shape:
```json
[{"checkpoint_id":"00000000-0000-4000-8000-000000000001","opens_at":"2027-01-01T08:00:00+08:00","closes_at":"2027-01-01T09:00:00+08:00"}]
```
UUID/timestamps are parsed and canonicalized; strings require ISO date/time with seconds and explicit Z or +/-HH:MM offset, optional 1–6 fractional digits. Finite half-open windows, start may only move earlier/equal, end later/equal; independently extend outside planned event schedule. Sort by checkpoint UUID and render normalized instants in UTC for idempotency. Never rewrite originals. Any pair of overlapping effective intervals requires explicit true acknowledgment (touching half-open boundaries are not overlap). Nonblank reason (1..500 characters after trimming surrounding spaces) required for any changed boundary or closure before planned event end, even if all checkpoints ended; otherwise null permitted. A supplied reason must be valid. Server clock records closure, sets SYNCING and initial deadline at closure + 24 elapsed hours in one transaction. No timer transition.

Result: `policy_version, event_id, request_id, event_state='SYNCING', closed_at, closed_by, reason, overlap_acknowledged, effective_windows, initial_sync_deadline, replayed`. Exact normalized replay returns original receipt even after extension, never recalculates initial deadline. Any other request/payload for same closure conflicts. Actual eligibility later intersects effective checkpoint interval with authoritative OPEN [opened_at,closed_at), preparation and assignment period; no capture evaluation or timestamp rewriting in B1.

### `extend_event_sync_deadline_v2(p_event_id uuid, p_request_id uuid, p_new_deadline timestamptz, p_reason text)`

Live active owning leader only, including platform Admin **only if also** an active owning leader. New extension only in unsealed SYNCING, even after current deadline expiration. Finite new instant strictly greater than current deadline and no later than closure + 168 elapsed hours (exact cap allowed); nonblank 1..500-character trimmed reason. Existing seal marker prevents new extension; no B1 operation creates a seal. No shortening, reopening, automatic seal/finalization or upload acceptance. Exact authorized replay returns original receipt including prior deadline even after subsequent extension; no mutation on replay.

Result: `policy_version, event_id, request_id, previous_deadline, new_deadline, reason, adjusted_at, adjusted_by, replayed`. Instants compared as timestamps, not display strings; future consumers must send explicit offsets.

### Errors

| SQLSTATE | Boundary |
| --- | --- |
| 22023 | Null/malformed input, invalid mapping/interval, missing required reason/ack, invalid preparation provenance, invalid extension bounds |
| 42501 | Missing live identity/scope/assignment, denied direct DML/EXECUTE, private data; unknown scoped event is denied |
| 55000 | Wrong policy or lifecycle state, duplicate outstanding preparation, new preparation after closure, new extension after seal, unavailable legacy operation |
| 23505 | Conflicting request UUID/payload or different request for existing closure |
| 40001 | Preparation receipt storage could not be confirmed (retry exact request) |

Do not interpret a preparation or closure receipt as an upload acknowledgement, accepted evidence, completeness or official attendance.

## Legacy boundary and read behavior

| Existing route | v1 | v2 in B1 |
| --- | --- | --- |
| Ordinary events INSERT, policy UPDATE | Default v1, unchanged grants | No selection/upgrade/downgrade; privileged fixture construction only |
| Event/checkpoint/roster/assignment reads; `can_access_assigned_event` | Existing scoped RLS | Hidden from legacy clients (no misleading online/empty evidence UI) |
| `can_edit_draft_event`, `update_draft_event`, checkpoint DML, `freeze_event_roster` | Unchanged | Denied by edit helper/RLS |
| `assign_event_staff`, `open_event`, `enable_event_offline`, `close_event` | Unchanged | Explicit policy guard after scope |
| `revoke_event_staff` | Unchanged | Shared safe revocation, existing manager/assignment locks; never creates authority |
| `ingest_attendance_scan`, `prepare_offline_capture`, `submit_offline_capture` | Exact existing input/response and replay | Explicit guard or missing legacy preparation; no fallback |
| `complete_offline_preparation`, `get_offline_preparation_status` | Unchanged | Missing legacy preparation or policy guard |
| `seal_offline_uploads`, loss/review/confirm, offline summary/preparation/claim reads | Unchanged | Manager helper denies successor policy |
| `get_event_checkpoint_coverage`, `get_event_finalized_results`, `finalize_event` | Unchanged | Coverage hidden by RLS; results/finalization explicitly denied |
| Direct legacy evidence INSERT/promotion/result | Existing ACLs/immutability/slots | Additional insert guards reject v2 scans, records, legacy preparations, claims and confirmations; seals/accounting/reviews have existing revoked direct grants and inaccessible legacy parents or manager guard |

No new service-role grant, weakening of legacy constraints, write access to private tables or authentication locks across unrelated users. Legacy preparation/claim/review/receipt/result identities and rows remain intact. Membership onboarding and CSV/import functions are untouched. Extra nullable/default event columns are additive; current Web/Mobile read explicit legacy fields. Old clients do not see fixture v2 events or be offered an operational route.

## Verification and forward recovery

Fresh database pgTAP suite plus the existing mandatory Repository validation; separate populated v1 reset/seed/upgrade snapshot verifies DRAFT, OPEN, FINALIZED, pending claim/lease and accepted receipt identities plus exact preparation/claim/scan/finalization replays. Two-session disposable tests observe lock contention for issuance, revocation, closure and extensions. Fixture construction is postgres-only within disposable CI: create explicit v2 DRAFT, planned checkpoints, roster/assignment, then privileged synthetic OPEN where needed. One privileged historical closure/seal marker is seeded solely to test expired-unsealed and sealed denial. No fixture seeds or runtime bypass in migration. Test SQL rolls back; CI resets/stops the ephemeral database. No real data or capacity run.

Do not roll back by dropping policy/evidence columns or reinterpret historical versions. If B1 needs repair use a forward migration preserving v1 rows and immutable receipts. If an unauthorized successor fixture appears outside CI, do not attempt uploads, downgrade, purge or finalize; isolate/escalate under owner review. B2 must replace the fixture-only boundary through explicit approved coordinated activation, not a silent default change.

B2 remains responsible for immutable v2 claims, server conditional timing/eligibility, exceptional review, normalized chronological winners, receipt materialization, deadline admission, seal (including early complete-only seal), accounting/loss, coverage, manual gated finalization and recovery. Mobile/Web version handling, encrypted recovery, clock protocol/tolerance/reboot, warning scope, physical Android and institutional trust/privacy/QR/retention gates remain separately pending. B1 is neither attendance acceptance nor deployment authorization.
