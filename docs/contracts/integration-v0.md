# HNU DASH — Shared Integration Contract (Draft v0)

**Status:** PROPOSED — NOT APPROVED OR IMPLEMENTED  
**Owner:** HNU DASH Backend; consumers: Web and Mobile  
**Change authority:** Shared behavior, authorization, data ownership, and scope changes require architecture/orchestrator approval.

This document defines the **minimum shared behavior** for an initial ~600-student BSIT deployment. It is the only canonical integration contract; clients should link to it, not copy it. The operation names and example payloads below are **design proposals**, not deployed endpoints, SQL functions, or an approved authentication protocol. The transport (Supabase table read, RPC, or Edge Function), exact signatures, and provider-specific identity claims remain implementation decisions subject to approval. Nothing in this draft authorizes domain migrations.

## 1. Authority and rules

- Supabase/PostgreSQL owns authoritative event, roster, scan, correction, reconciliation, and attendance state. Web and Mobile never determine official attendance.
- Clients authenticate as users. Reads are constrained by RLS; privileged writes execute with backend-side identity, role, organization, event-assignment, and lifecycle checks. The actor is derived from the authenticated session, **not** from an editable request field. No service-role key is shipped to Web or Mobile.
- Web manages events and reviews results. Mobile downloads **only** its assigned events and frozen rosters, collects QR scans from physical HNU IDs after staff visual verification, and queues provisional records in local SQLite. The clients do not communicate with each other.
- Production identity proof may later use HNU MIS; provider, login flow, identity-to-account binding, and claims are **TBD**. Never store or proxy MIS passwords.
- A server acknowledgment of a scan is **not** validation, reconciliation selection, or an official PRESENT result.
- Use UUIDs for stable record identifiers and RFC 3339 timestamps including an offset, normalized to UTC on the backend. All client timestamps are evidence to validate, not trusted server time. Server-generated timestamps record reception and state transitions.
- All lists and downloads are scoped and paginated/bounded as appropriate. Concrete pagination, batch-size, retention, and rate limits are pending decisions.

## 2. Minimal logical entities

These describe shared fields, **not** approved SQL tables or a complete schema.

| Entity | Minimum fields / obligations |
| --- | --- |
| Actor / Membership | Authenticated actor reference, role (Admin, Governor/Organization Leader, Attendance Staff, Student), organization scope; event assignment checked separately |
| Organization | `organization_id`, display identity, governed member scope |
| Event | `event_id`, `organization_id`, title/schedule, approved required-demographic rule, lifecycle state, state-transition timestamps, frozen `roster_version`, creator/audit references |
| Event Staff Assignment | `event_id`, staff actor reference, active/revoked state, assignment audit |
| Frozen Roster Entry | `event_id`, `roster_version`, canonical student reference, permitted QR-matching value, minimum display data for visual check; snapshot produced by backend from the required demographic |
| Provisional Scan | Stable client-generated `scan_id` (UUID), `event_id`, device reference, `scan_type` (TIME_IN/TIME_OUT), `scanned_at`, QR evidence, staff visual-check attestation; raw scan history is not overwritten |
| Ingest Receipt / Reconciliation | `scan_id`, durable receipt status, optional rejection code, evaluation/disposition, server receipt time; may be revised by subsequent valid scans before finalization |
| Attendance Result | Per frozen-roster student/event: PRESENT, ABSENT, INCOMPLETE_TIME_IN, INCOMPLETE_TIME_OUT; official after server finalization, not inferred from upload count |
| Adjustment / Audit | Target event/student/result, previous and new outcome, reason, authorized actor, time, provenance; EXCUSED is an approved adjustment rather than a mutation/deletion of raw scans |

The actual QR encoding and roster matching field are TBD. `roster_version` identifies the immutable snapshot being used offline. Roster generation must not trust client-supplied membership lists. Avoid distributing unrelated student data or exposing QR values to unassigned users.

## 3. Authorization boundary

| Actor | Proposed minimum access |
| --- | --- |
| Admin | Authorized platform administration/intervention with recorded reason and audit; not an implicit authorization bypass in client code |
| Governor / Organization Leader | Manage events, audience selection, staff assignments, roster review, attendance review, finalization, and eligible correction **within their organization**, subject to state rules |
| Attendance Staff | Read assigned event and its frozen roster; submit/inspect scans and report sync completion **only for active event assignments** |
| Student | Read only their own eligible event/attendance results; cannot manage roster, upload staff scans, or edit official results |

All permissions are enforced by the backend even if a UI hides controls. Deny cross-organization and unassigned-event access without returning protected roster or attendance data. Staff authorization when a device was assigned at capture time but revoked while offline is unresolved (`D-4`). Granular Admin/Governor actions remain subject to approval (`D-2`).

## 4. Event lifecycle (server-controlled)

Only these forward transitions are in scope. No client may force a state change by editing a field directly.

| Transition | Precondition and consequence |
| --- | --- |
| DRAFT → OPEN | Authorized operation; approved demographic resolved and frozen roster available before any scanning; starts collection |
| OPEN → SYNCING | Stop **new** scan capture; allow uploads of **previously captured** offline scans within the sync period |
| SYNCING → FINALIZED | Authorized finalization after reconciliation; blocks all scan uploads and establishes official attendance results and `finalized_at` |
| FINALIZED → LOCKED | End ordinary Governor correction privileges; existing audit history remains accessible to authorized reviewers |

During **FINALIZED**, the Governor's ordinary correction window ends **seven days after `finalized_at`**, or earlier if LOCKED. Whether automatic locking occurs at seven days, who may trigger each transition, and the minimum proof needed before finalization are unresolved (`D-2`, `D-6`). Admin intervention and restricted semester Clearance adjustments require explicit authorization and append-only audit; they never erase scan history. Do not silently allow backward transitions or reopen uploads.

A scan recorded while OPEN may arrive while SYNCING, subject to time, assignment, roster, and integrity validation. A scan first captured during SYNCING is not eligible merely because it was queued offline. FINALIZED and LOCKED reject uploads.

## 5. Web operations (logical contract)

The backend checks authenticated identity and organization scope on **every** operation. `request` fields are intent, not proof of authority.

| Operation | Inputs (minimum) | Result / key behavior | Authorization |
| --- | --- | --- | --- |
| `organizations.list_my` | None | Only visible organizations and effective roles | Authenticated member/admin |
| `events.list` / `events.get` | `organization_id`, optional `event_id` | Scoped events, state and roster metadata | Scoped member/authorized viewer |
| `events.create` / `events.update_draft` | `organization_id`, title, schedule, required demographic definition, version/precondition | Event details or field validation errors; draft changes are not final attendance | Governor/Admin in scope |
| `roster.preview` / `roster.freeze` | `event_id`, demographic criteria reference | Eligible count/preview; immutable server-generated roster and version | Governor/Admin in scope; freeze before OPEN |
| `staff.assign` / `staff.revoke` | `event_id`, staff reference, intended change | Updated assignment state and audit reference | Governor/Admin in scope |
| `events.transition` | `event_id`, expected current state, target next state | New state, server transition timestamp, version | Authorized Governor/Admin; valid transition only |
| `attendance.review` | `event_id`, filters/page | Roster-backed scan evidence, current provisional/official result, correction history | Authorized organization reviewer |
| `attendance.adjust` | `event_id`, student reference, desired adjustment (including EXCUSED), reason, expected result version | Audited adjustment or state/permission conflict; no raw scan overwrite | Governor during allowed seven-day period; explicitly authorized Admin/Clearance actor otherwise |
| `attendance.report` | `event_id`, page/filter | Reconciled attendance with provisional/official state clearly labeled; report provenance | Authorized organization reviewer |
| `attendance.my_results` | Optional filters | Only caller's results and event context, with provisional/official distinction | Student/self |

Creation and transitions require server-side validation of event schedules, frozen roster, and role/organization ownership. Roster eligibility criteria, actor-role mapping, optimistic concurrency fields, report visibility, and adjustments beyond EXCUSED must be approved before concrete handlers (`D-1`–`D-3`, `D-6`–`D-7`).

**Proposed representative Web request/result:**

```json
{
  "operation": "events.transition",
  "request": {
    "event_id": "evt_demo",
    "expected_state": "OPEN",
    "target_state": "SYNCING"
  },
  "response": {
    "event_id": "evt_demo",
    "state": "SYNCING",
    "changed_at": "2026-11-01T10:00:00Z",
    "version": 3
  }
}
```

`expected_state` and `version` illustrate concurrency protection, not a finalized wire format.

## 6. Mobile operations (logical contract)

Mobile uses an authenticated staff session; event assignment and roster access are rechecked server-side. The on-device SQLite queue is provisional and must retain records until a **durable, record-specific** result is known.

| Operation | Inputs (minimum) | Result / key behavior |
| --- | --- | --- |
| `assignments.list_mine` | None | Only events this actor may work on, current assignment and event state |
| `assignments.get_event` | `event_id` | Assigned-event metadata, scanning windows, lifecycle state, frozen roster version |
| `roster.download_assigned` | `event_id`, optionally known version/page | Frozen, version-identified student roster and minimum QR-matching/visual-check fields for the assigned event |
| `scans.upload_batch` | `event_id`, `device_id`, `roster_version`, collection of immutable scan payloads | Independent per-record receipts and latest reconciliation state; partial success allowed |
| `sync.complete` | `event_id`, `device_id`, client-declared queue state | Records the device's completion declaration; **does not** finalize the event or certify all devices finished |

`device_id` is a stable app-installation/device reference; exact registration and trust model remain TBD. Never trust a device identifier alone as authorization. Offline roster contents must be protected on-device and unavailable to unrelated users.

**Proposed scan batch request:**

```json
{
  "event_id": "evt_demo",
  "device_id": "device_demo",
  "roster_version": "roster_v1",
  "records": [
    {
      "scan_id": "00000000-0000-4000-8000-000000000001",
      "scan_type": "TIME_IN",
      "scanned_at": "2026-11-01T08:00:01+08:00",
      "qr_payload": "DEMO_NOT_A_REAL_STUDENT_ID",
      "visual_check_confirmed": true
    }
  ]
}
```

The backend resolves the QR payload against the **frozen** event roster; it must not accept client-chosen student identity as proof. The visual-check flag is a staff attestation, not independent identity proof. The accepted QR format, whether this flag is mandatory, timestamp trust thresholds, and source of the demographic roster are unresolved.

**Proposed per-record response (a durable receipt, not official presence):**

```json
{
  "event_id": "evt_demo",
  "server_time": "2026-11-01T00:00:10Z",
  "results": [
    {
      "scan_id": "00000000-0000-4000-8000-000000000001",
      "receipt": "STORED",
      "disposition": "PENDING",
      "retryable": false,
      "received_at": "2026-11-01T00:00:10Z"
    }
  ]
}
```

Receipt values:

- `STORED`: the immutable scan payload was durably recorded. **Not** official attendance acceptance.
- `ALREADY_STORED`: same `scan_id` and same immutable payload were recorded previously; safe retry, no second logical scan.
- `REJECTED`: not durably accepted for processing; include stable `error.code` and `retryable`. A changed payload with a reused `scan_id` is a conflict, not a replacement.

Disposition values are separate: `PENDING` (awaiting checks/reconciliation), `SELECTED` (currently earliest valid candidate), `SUPERSEDED` (valid but beaten by another eligible scan), or `INVALID` (failed validation). Dispositions may change until finalization. `SELECTED` does **not** imply PRESENT: the server computes per-student Time-In/Time-Out outcomes and freezes official results at FINALIZED.

`sync.complete` must be idempotent for an event/device. It means only that a particular device reports no unresolved locally queued scans at that moment; it is not evidence that every device has synced or that attendance is finalized. Whether subsequent discovery of older offline scans invalidates a prior completion declaration requires approval (`D-6`).

## 7. Idempotency, duplicate rules, and synchronization

**Stable scan identity:** Generate `scan_id` once **at scan capture**, persist before upload, and reuse on every retry. Keep immutable fields unchanged (`event_id`, `device_id`, `scan_type`, `scanned_at`, QR evidence). Do not mint a new UUID after timeout or partial failure.

**Exactly-once logical ingest:** The backend enforces unique `scan_id`. Repeated identical payloads return `ALREADY_STORED` (possibly with updated disposition); reused UUIDs with different payload return `SCAN_ID_CONFLICT`. A lost response is recovered by retrying the *same* batch/records.

**Cross-device duplicates:** After eligibility checks, reconcile by (`event_id`, canonical student reference, `scan_type`), keeping the **earliest valid `scanned_at`** across devices. The deterministic tie-break between equal timestamps is **unapproved**; the candidate is lexical `scan_id` ordering (`D-5`). Never use upload arrival time to choose the winner. Keep superseded raw records for audit.

**Order independence:** Ingest order must not change the final winner. A later-arriving but earlier-captured valid scan can supersede an earlier-uploaded candidate before finalization. Return the latest known disposition when the client queries or retries. Do not silently rewrite or delete the superseded scan.

**Partial failure:** Each record gets its own outcome. A failure to persist one scan must not erase successful records in the same batch. Unacknowledged or transiently failed records remain in the local queue; terminally rejected records are retained locally for staff review and must not be silently marked as successfully synced. A network timeout gives **no receipt guarantee**: retry using the same `scan_id`.

**Lifecycle gate:** OPEN accepts eligible newly recorded scans. SYNCING accepts previously recorded offline scans only. FINALIZED/LOCKED reject all uploads, including retries not previously durably stored. Read-only status lookup for already-recorded `scan_id` should remain possible after finalization so clients can settle lost acknowledgments without reopening upload; exact lookup mechanism is TBD.

**Final attendance:** The backend evaluates Time-In and Time-Out for each frozen-roster student to derive PRESENT, ABSENT, INCOMPLETE_TIME_IN, or INCOMPLETE_TIME_OUT. Approved EXCUSED corrections append an audited adjustment; neither a stored scan nor a client-side computation may create an official result.

## 8. Common response / error behavior

Successful privileged mutations return the authoritative new version/state and server timestamp. Invalid inputs return stable machine-readable `error.code`, a safe message, and optional field details. Never expose private roster data in authorization errors or server traces.

| Condition | Proposed code | Expected client behavior |
| --- | --- | --- |
| No valid authenticated session | `UNAUTHENTICATED` | Reauthenticate; preserve offline queue |
| Incorrect role, organization, or event assignment | `FORBIDDEN` / `NOT_FOUND` | No protected data; do not retry until access changes |
| State/precondition has changed | `EVENT_STATE_CONFLICT` | Refresh and show server state |
| Roster missing or version incompatible | `ROSTER_NOT_READY` / `ROSTER_VERSION_MISMATCH` | Stop guessing; request authorized refresh or staff escalation |
| Reused UUID with different immutable scan payload | `SCAN_ID_CONFLICT` | Retain evidence, flag for investigation; never overwrite |
| Scan malformed/ineligible/clock-invalid | `SCAN_INVALID` | Per-record terminal outcome and reason; do not fabricate success |
| Upload no longer allowed by event state | `UPLOAD_CLOSED` | Retain unsynced records, escalate; do not reopen locally |
| Transient backend failure / throttling | `TEMPORARY_FAILURE` / `RATE_LIMITED` | Retry with backoff, preserving UUIDs and original payload |

Batch-level authentication and authorization failures reject the whole request; independently invalid or conflicting scans can produce per-record errors with partial success. HTTP status mapping and Supabase RPC/Edge Function envelope remain TBD. Client-visible codes must not depend on raw PostgreSQL error messages.

## 9. Approval-needed decisions (not silently settled)

- **D-1 — Roster and QR:** Authoritative source of students/demographics, exact frozen-roster timing and membership exceptions, QR encoding, minimal identifying fields, and roster revision policy.
- **D-2 — Permissions:** Precise capabilities for Admin vs Governor, who transitions states, who assigns staff, and whether any roles are global or organization-specific.
- **D-3 — Authentication:** Provider, identity binding, token claims and session handling; HNU MIS remains unapproved.
- **D-4 — Offline trust:** Device enrollment, capture-time authorization vs sync-time revocation, offline access lifetime, visual-check requirement, and timestamp/clock validation tolerances.
- **D-5 — Deterministic ties:** Approve tie-break after earliest valid `scanned_at`; lexical `scan_id` is proposed, not established.
- **D-6 — Synchronization and finalization:** Retry lookup after close, stale/missing devices, batch size, synchronization deadline, completion revocation, finalization threshold, and automatic LOCKED timing.
- **D-7 — Attendance policy:** Time windows/late rules, whether both scans are required for PRESENT, event-level eligibility, correction reasons, clearance-specific privileges and adjustments. Fines are **not** assumed.
- **D-8 — Transport and privacy:** Select Supabase RLS reads/RPC/Edge Functions per operation, set pagination and retention limits, logs and local roster-data protection.

**Approval boundary:** No provider choice, tables, RLS, RPC/Edge Functions, or production contract consumers should be implemented from this draft as if these decisions were already approved.

## 10. Safe consumer work before approval

**Web:** Continue UI foundation and local presentation-only interfaces for event state, authorized action affordances, attendance review, and error/empty states. May prototype against clearly labeled mock responses from this draft; must not claim real persistence or enforce authority only in UI.

**Mobile:** Continue Flutter foundations, local test doubles for offline scan queues, stable per-scan UUID generation, repeatable retries, assigned-event/roster display, and distinct upload-receipt vs official-attendance UI states. Do not bind to a presumed endpoint, invent QR parsing rules, or treat a scan as official presence.

**Backend next:** Resolve D-1–D-8 with orchestrator, approve versioned operation shapes and permissions, then implement the smallest end-to-end slice with migrations, RLS, security tests, and one consumer integration. Changes to shared behavior require backend contract PR review and orchestrator approval before release.
