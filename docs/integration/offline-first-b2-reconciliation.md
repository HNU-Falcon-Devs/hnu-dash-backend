# Offline-first B2 reconciliation — policy v2 (fixture-only)

Authority: [Backend #27 B2 package](https://github.com/HNU-Falcon-Devs/hnu-dash-backend/issues/27#issuecomment-7224646475), [conditional owner authorization](https://github.com/HNU-Falcon-Devs/hnu-dash-backend/issues/27#issuecomment-7224669319), [B1 terminal prerequisite](https://github.com/HNU-Falcon-Devs/hnu-dash-backend/issues/27#issuecomment-7225125106). Base `8f1502ca452fe367ff9ec39bcece687ff000ff14`. This is the successor Backend contract, not operational activation or institutional policy. The [B1 foundation](offline-first-b1-foundation.md) retains its three exact RPCs and historical foundation-only boundary. M2.3/M3.2A/M4.1/M4.2 remain the canonical v1 contracts.

## Boundary and ownership

- Policy 2 is still available only through privileged disposable fixture construction. Ordinary event INSERT defaults to v1, policy is immutable, and no ordinary creation, upgrade, activation, or reopening RPC exists. Legacy event reads and legacy mutation/reconciliation/finalization paths still exclude v2. No Web/Mobile client should switch to these endpoints before separately authorized coordinated acceptance.
- All v2 operations require current verified HNU identity. Staff must be the original preparation owner with the exact live assignment, active organization and active Staff membership, including on replay. Managers are active owning leaders or authorized existing platform Admins, with existing scope checks. Deadline extension remains active owning leader only (B1). No service-role access, device bearer credential, new offline login or recovery/reassignment bypass.
- New tables and views live in the non-exposed `offline_b1_private` schema. Tables have RLS enabled and no ordinary policies; ordinary roles and service role receive no access. New RPCs explicitly revoke default EXECUTE and grant authenticated only, with empty search path and live database authorization. Mutations serialize on the parent event row before authorization locks; manager reads take a shared event lock. Legacy revocation and membership NOWAIT semantics remain unchanged; exact assignment/membership locks serialize the outcome.
- B2 preserves every scoped admitted raw claim, including rejected/nonwinning claims, its original payload, receipt time, policy classification and bounds. No mutable claim, decision, accounting, seal, confirmation or finalization row. No purge, correction, replacement preparation or automatic state transition.

## Clock evidence and eligibility

`p_clock` is one JSON object (all ten exact keys; no extras, maximum 4096 UTF-8 bytes of JSONB text). Four elapsed values are nullable integer milliseconds in the signed JSON-safe representation range ±9,007,199,254,740,991. Negative values within range are retained as anomalies, not eligible; malformed or out-of-range representations fail admission. Wall instants are nullable ISO date/time with seconds, optional 1–6 fractional digits and explicit Z/offset. Boot markers are nullable opaque 1..128 ASCII alphanumeric/underscore/hyphen strings, never trusted device identity.

```json
{
  "anchor_request_elapsed_ms": 1000,
  "anchor_response_elapsed_ms": 1200,
  "qr_elapsed_ms": 3200,
  "confirmation_elapsed_ms": 3400,
  "qr_wall_at": "2027-01-01T08:00:03.000000+08:00",
  "confirmation_wall_at": "2027-01-01T08:00:03.200000+08:00",
  "anchor_boot_marker": "synthetic_boot_a",
  "capture_boot_marker": "synthetic_boot_a",
  "anchor_provenance": "original",
  "anomaly": "none"
}
```

Anchor provenance: `original | replayed | missing | unknown`. Anomaly: `none | missing | reboot | clock_jump | inconsistent | other`. A replayed B1 response never establishes a fresh anchor. Preserve missing fields as JSON null and report provenance/anomaly explicitly; no local capture expiry inferred from the planned schedule. Capture chronology refers to QR observation, not confirmation or upload.

For an otherwise complete original-anchor, same-boot sequence, let A be the immutable server B1 `issued_at`, r request-start elapsed ms, s response-end ms, q QR ms, c confirmation ms. Require 0 <= r <= s <= q <= c, s-r <= 5000 ms, c-q <= 30000 ms, no reported anomaly. For observation x (q or c) use outward-rounded epsilon = 2,000,000 + ceil((x-r)/10) microseconds (2 seconds plus 100 ppm of the maximum elapsed duration). Its interval is [A+(x-s)ms-epsilon, A+(x-r)ms+epsilon]. Whole days plus integer sub-day microseconds avoid unsafe floating-point epoch arithmetic; arithmetic overflow is exceptional, not silent saturation. Wall observations must lie inside their corresponding derived intervals, and the difference between their wall and elapsed gaps must be within confirmation epsilon. These are synthetic engineering constants, not measured clock behavior or attestation. A malicious authorized client can fabricate coherent telemetry.

For admission, the server records `received_at` after acquiring the event/live-scope locks. Hard lower bound = max(actual opened_at, effective checkpoint start, issued_at, assignment assigned_at). Hard upper bound = min(actual closed_at, effective checkpoint end), exclusive; server receipt is an additional inclusive upper bound. Reliable QR intervals entirely outside these bounds are terminally rejected. Partial OPEN/effective/assignment/preparation overlap is exceptional, never clipped into ordinary eligibility. Intersect reliable intervals with the independent server receipt upper bound only after confidence checks. Entire remaining interval must fit; ordinary normalized capture is its midpoint rounded down to integer microseconds. Empty hard intervals and non-roster IDs are terminally rejected irrespective of clock confidence. Untrustworthy provenance, missing fields, anomalous sequence, wall inconsistency or arithmetic overflow are exceptional; no client-time-only hard rejection when chronology is untrustworthy. Preserve trustworthy partial bounds; do not invent bounds from uncertain telemetry.

All admitted payloads receive the same generic acknowledgement (including scoped non-roster claims). Wrong checkpoint/preparation scope or malformed representations are denied and not counted. A denied request is not a durable claim or proof of synchronization; no eligibility/roster oracle or denied-attempt counter is exposed to Staff.

## RPC contracts

UUIDs are nonnull unless specified. All JSON objects are returned in UTC rendering. Named parameters below are exact. Natural idempotency keys are per capture, preparation or event, as listed; exact authorized retries return original receipt plus `replayed=true`, never recalculate. For the clock object retry equality is JSONB value equality (including literal wall timestamp strings); retain the original raw payload, not a reserialized/updated clock observation. Scope checks precede durable replay. Wrong payload for a previously used key is a conflict.

### Staff

| RPC | Parameters | Response |
|---|---|---|
| `submit_offline_capture_v2` | p_preparation_id uuid, p_capture_id uuid, p_checkpoint_id uuid, p_student_id text (1..64 ASCII letters/digits/hyphen), p_clock jsonb | policy_version, capture_id, preparation_id, received_at, status='submitted', replayed |
| `complete_offline_preparation_v2` | p_preparation_id uuid, p_acknowledged_count bigint (nonnegative) | policy_version, preparation_id, disposition='completed', uploaded_count, declared_count, reason=null, accounted_at, accounted_by, replayed |
| `get_offline_preparation_status_v2` | p_preparation_id uuid | policy_version, preparation_id, event_state, sync_deadline, sealed, uploaded_count, disposition (null until terminal) |

New uploads require SYNCING, server receipt strictly before the current deadline, unsealed and preparation not terminal. Exact authorized replays are available after cutoff/seal/completion/finalization, never a new admission. Capture UUID is the separate v2 claim namespace; cross-event/preparation/payload reuse conflicts. Legacy online and v1 offline UUID namespaces are not used to resolve successor evidence.

Completion declares the distinct durable acknowledgement count for the original preparation, including rejected and exceptional claims. A mismatch fails; zero is explicit. New completion only in SYNCING, including after seal until terminal accounting. Completion and loss are mutually exclusive, immutable and naturally idempotent per preparation. After completion no new claim can arrive under that preparation. Lost/revoked/reassigned local evidence is escalated, not reattributed or purged.

### Manager mutations

All reasons are trimmed, bounded 1..500 nonblank characters when required or supplied. The seal requires explicit confirmation and reason, even when not early.

| RPC | Parameters | Response |
|---|---|---|
| `seal_offline_uploads_v2` | p_event_id uuid, p_confirm boolean=true, p_acknowledge_unused boolean, p_reason text | policy_version, event_id, sealed_at, sealed_by, early, unused_assignments, acknowledged_unused, reason, replayed |
| `account_offline_preparation_loss_v2` | p_event_id uuid, p_preparation_id uuid, p_disposition text (missing/lost/revoked/undrained), p_reason text | policy_version, preparation_id, disposition, uploaded_count, declared_count=null, reason, accounted_at, accounted_by, replayed |
| `review_offline_capture_v2` | p_event_id uuid, p_capture_id uuid, p_decision text (approve/reject), p_reason text, p_basis_category text nullable, p_basis_reference text nullable, p_validated_capture_at timestamptz nullable | policy_version, capture_id, decision, reason, basis_category, basis_reference, validated_capture_at, reviewed_at, reviewed_by, replayed |
| `confirm_offline_reconciliation_v2` | p_event_id uuid, p_acknowledge_unused boolean, p_reason text nullable | policy_version, event_id, acknowledged_unused, unused_assignments, reason, confirmed_at, confirmed_by, replayed |
| `finalize_event_v2` | p_event_id uuid | policy_version, event_id, event_state='FINALIZED', finalized_at, finalized_by, winner_count, record_count, replayed |

Seal is manual in SYNCING. Before deadline every known preparation must have successfully completed (loss cannot qualify). At/after deadline the manager can seal despite missing accounting; loss can be recorded only after deadline-based seal, actual uploaded count only and null declared count. Missing preparations are assignment periods without any preparation, including historical periods; no fabricated session. If there are unused assignments or zero known preparations, explicitly acknowledge at seal and confirmation, with confirmation reason. No seal/reopen/extension after seal; B1 uses the same immutable seal marker.

Adjudication is individual, after seal, only for initial exceptions. Approve requires attributable synthetic reference category `synthetic_organizer_observation` or `synthetic_event_record` and reference `synthetic:[A-Za-z0-9_-]{1,128}`, plus reason and a finite normalized instant within hard bounds, receipt and any reliable partial interval. This reference records an assertion by the live manager, not server verification of a physical observation. No reason-only override, real data or attachments. Reject requires reason and null reference/category/instant. Terminal hard rejections and ordinary eligible claims are not reviewable. Decisions cannot be reversed.

Readiness requires seal, every preparation accounted for with actual durable count, and every claim terminal. Confirmation is separate, checks readiness and explicit acknowledgement of unused/no preparations; no automatic finalization. Finalization rechecks readiness under the same parent lock, requires confirmed reconciliation and frozen nonempty roster/checkpoints. One transaction inserts the finalization audit, canonical receipts for provisional winners and one result per roster student, then updates state. Any failure rolls everything back. Exact retry returns the original actor/time/counts. No LOCKED/correction transition or post-final recalculation is added.

### Manager reads

All require the scoped live manager; no Staff export. Paginated reads default to 200, offset 0; limit 1..200 and offset >=0, stable explicit order within a call. Reads before seal/confirmation are provisional and can change between pages. No unbounded row export.

- `get_event_offline_summary_v2(p_event_id uuid)`: policy_version, event_id, event_state, sync_deadline, sealed, known_preparations, accounted_preparations, completed_preparations, loss_accounted_preparations, unused_assignments, submitted_claims, eligible_claims, rejected_claims, pending_exceptions, provisional_winners, evidence_ready, reconciliation_confirmed, can_finalize, finalized_at, finalized_by, finalized_records (null before finalization). Zero known preparations does not imply coverage or sync completion.
- `get_event_offline_preparations_v2(p_event_id uuid,p_limit integer=200,p_offset integer=0)`: JSON array of assignment periods ordered assigned_at/id. Keys assignment_id, staff_user_id, assigned_at, revoked_at, preparation_id, issued_at, uploaded_count (null if unused), accounting (full immutable accounting row or null).
- `get_event_offline_claims_v2(p_event_id uuid,p_limit integer=200,p_offset integer=0,p_exceptions_only boolean=false)`: JSON array ordered received_at/capture_id. All immutable claim fields (capture_id, preparation_id, event_id, checkpoint_id, student_id, clock_payload, received_at, hard_start, hard_end, plausible_start/end, initial_disposition, timing_basis, validated_capture_at), review decision/reason/category/reference/time/actor (null if absent), resolved disposition, normalized_at, provisional_winner boolean, final_receipt_id (null before materialization/nonwinner). Filter true includes original exceptions, including already adjudicated.
- `get_event_checkpoint_coverage_v2(p_event_id uuid,p_limit integer=200,p_offset integer=0)`: JSON array of frozen roster/checkpoint pairs ordered student ID C collation/checkpoint sort order/ID. Keys student_id, checkpoint_id, checkpoint_label, checkpoint_direction, checkpoint_sort_order, provisional_capture_id, validated_capture_at, received_at, final_receipt_id, finalized. Page-first indexed slot lookup, no per-row caller RLS fanout. A null winner is not a final absence until finalization.
- `get_event_finalized_results_v2(p_event_id uuid,p_limit integer=200,p_offset integer=0)`: FINALIZED only, array ordered student ID C collation of event_id, student_id, status, required_checkpoint_count, accepted_checkpoint_count.

### Errors

| SQLSTATE | Meaning |
|---|---|
| 22023 | Invalid/null/oversize payload, count mismatch, invalid decision/basis/time, page, or missing acknowledgement |
| 42501 | Unauthorized/unverified/revoked/foreign scope or denied direct access |
| 55000 | Wrong policy/state, admission closed, early seal incomplete, hard rejection not reviewable, not ready or not finalized |
| 23505 | Conflicting immutable key or decision |
| 40001 | Persistence unconfirmed; retry exact original request |

Transport/cast failures are not durable acknowledgement. Preserve queue data and retry exact payload; no automatic purge on error.

## Persistence, chronology and compatibility

`claims_v2` references exact B1 (preparation,event) and effective (event,checkpoint); preparation already carries exact assignment/owner composite FK. Non-roster claim IDs intentionally have no roster FK, to retain terminal rejected evidence without a Staff oracle. `reviews_v2`, `accounting_v2`, `seals_v2`, `confirmations_v2`, `finalizations_v2` are append-only. `resolved_v2` and `winners_v2` are private derived relations, not stored accepted flags. Eligible winner order is normalized_at, received_at, capture_id ascending, independent of upload order. Overlapping otherwise eligible estimates do not force review. No assertion of actual physical order.

Canonical `attendance_scans.source='offline_v2'` uses new nullable unique `successor_capture_id` FK, independent generated scan_id, unchanged v1 offline_capture_id (null for v2). Canonical received_at is the actual original server admission time, not claimed/normalized/finalization time. One accepted receipt per slot enforced by the unchanged partial unique index. Nonwinning and rejected raw evidence stays private. Narrow scan/result insert triggers require the exact v2 winner and immutable in-transaction finalization audit, matching actor/time/provenance/counts; event transition requires complete materialization. No session flag or general privileged bypass. Results use existing synthetic PRESENT/INCOMPLETE/ABSENT coverage statuses; no new institutional attendance policy.

Legacy online and M4 functions, RLS, UUID identities, preparation/claim/review/receipt/result contents and accepted-slot index remain unchanged. New nullable receipt provenance is null for all v1 rows; explicit legacy RPC response schemas unchanged. B1 closure, extension and preparation receipts retain exact original context. B1 v2 fixture marker used by existing tests still denies extension. Legacy v2 guards remain for legacy prep/claim/confirmation, old finalization/coverage/results, direct event/receipt writes and ordinary activation. No onboarding or CSV behavior changes.

## Verification and recovery

The existing Repository validation workflow adds focused B2 pgTAP assertions, populated v1+B1 snapshot/replay upgrade and genuine two-session contention checks using the already disposable GitHub-hosted stack. Historical fixtures and intentionally equal receipt-time ties are privileged synthetic test setup only; no fixture or bypass in migrations. No capacity run or production/provider access. CI results must be reported at the tested revision; this contract does not assert that unobserved tests pass.

Forward repair only: do not drop or rewrite historical evidence, downgrade policy or delete pending queues. If a successor event unexpectedly appears outside disposable CI, isolate and escalate; do not activate, migrate, purge, reattribute or finalize it. B2 fixture-only Backend acceptance is not Mobile M1/Web W1 integration, physical Android boot/re-anchor/clock proof, workload/capacity acceptance, real OAuth, privacy/retention/QR/identity or institutional risk acceptance. All remain separate gates.
