# Milestone 4.2 — Offline reconciliation (synthetic only)

[Issue #17](https://github.com/HNU-Falcon-Devs/hnu-dash-backend/issues/17) and
[owner approval](https://github.com/HNU-Falcon-Devs/hnu-dash-backend/issues/14#issuecomment-7136554216).
Extends [M4.1](milestone-4-part-1-offline-evidence.md) without changing preparation
or upload signatures, response fields, claimed-time rules, or old acknowledgements.
Use verified authenticated HNU accounts with publishable key, never service-role.
No real data, deployment, automatic acceptance or institutional attendance policy.

## Staff API

All IDs are UUIDs; timestamps are timestamptz serialized as ISO 8601 with offset;
counts are nonnegative bigint JSON numbers (consumers must check safe integer bounds).
JSON results are objects, not arrays, except manager page reads below.

- `complete_offline_preparation(p_preparation_id uuid,p_acknowledged_count bigint)`:
  {preparation_id, disposition:"completed", uploaded_count, declared_count,
  accounted_at, accounted_by, replayed}. Stop capturing under this preparation
  before declaring; all distinct local captures must have durable acknowledgements.
  Count is compared to the actual stored claims, including ineligible/duplicate
  claims. This is an accountable declaration, not proof of no omitted captures.
  The preparation ID is the idempotency key; identical count replays original
  audit, changed count or prior loss disposition conflicts. Zero is valid if
  no claims exist. New claims after completion are denied; identical authorized
  upload replay is unchanged. Completing does not shorten original lease:
  no new preparation before its original expiry, and the same preparation
  request still returns its original metadata (not fresh capture permission).
  Fresh requests after expiry follow unchanged M4.1 rules.
- `get_offline_preparation_status(p_preparation_id uuid)`:
  {preparation_id,event_id,event_state,expires_at,upload_cutoff,sealed_at,
  uploaded_count,disposition,declared_count,accounted_at,can_upload,can_complete}.
  Nullable timestamps/count/disposition mean no corresponding record. Boolean
  can_upload is for NEW submissions only; not a capture authorization. No private
  eligibility, per-claim decisions, roster, loss reason or other user's data.
  Staff must check completion status before resuming a previously prepared context.
  Both RPCs require the exact original currently active assignment and same
  verified Staff identity; no revoked/reassigned exception. Completion can occur
  in OPEN or SYNCING, including after seal, until immutable accounting exists.
  It cannot create or reopen uploads. After finalization only authorized identical
  completion replay/status is allowed.

## Manager API

All operations require live authorized owning Leader/platform Admin, using event
scope, not client role assertions. New actions only in offline-enabled SYNCING
after seal, except the seal itself. Same immutable requests replay original
audit after state change even if another authorized manager retries; reasons are
compared exactly (not trimmed). Reasons 1..500 characters, non-whitespace.

| RPC (exact parameters) | JSON result |
| --- | --- |
| seal_offline_uploads(eid uuid) | event_id,sealed_at,sealed_by,replayed |
| account_offline_preparation_loss(eid uuid,p_preparation_id uuid,p_disposition text,p_reason text) | preparation_id,disposition,uploaded_count,declared_count (null),reason,accounted_at,accounted_by,replayed |
| review_offline_capture(eid uuid,p_capture_id uuid,p_decision text,p_reason text) | capture_id,decision,reason,receipt_id,receipt_outcome,reviewed_at,reviewed_by,replayed |
| confirm_offline_reconciliation(eid uuid) | event_id,confirmed_at,confirmed_by,replayed |

Seal requires existing closure and server clock >= exclusive upload cutoff (last
checkpoint close + 24 hours). No early seal, automatic seal or reopen. Completion
or manager loss accounting is terminal; the first committed accounting wins.
Loss categories missing/lost/revoked/undrained require reason and are recorded
with actual durable count and null declaration, never inferred local count.
Manager review is per claim, approve/reject, with reason. Only privately eligible
claims can be approved; claimed time is untrusted, not proven capture time.
Prior submitted claims remain reviewable after Staff revocation. Approval creates
one server-allocated canonical receipt with source offline, linked capture UUID,
original Staff and original server upload received_at; accepted if slot unused,
duplicate otherwise. Review actor/time separate. Rejection creates no canonical
receipt (receipt_id/outcome null). Immutable decision, no reversal; same
decision+reason replays, changed payload conflicts. Online UUID and offline
capture UUID remain separate; online RPC rejects a promoted canonical receipt UUID
as an online replay (23505). Existing online outcomes/timestamps are unchanged.

## Manager reads

`get_event_offline_summary(eid uuid)` object:
event_id,event_state,upload_cutoff,sealed_at,sealed_by,confirmed_at,confirmed_by,
preparation_count,completed_count,loss_count,unaccounted_count,claim_count,
reviewed_count,unreviewed_count,can_seal,can_confirm,can_finalize.
Nullable audit fields indicate no record; DRAFT cutoff and can_seal may be null
only where cutoff is absent (no readiness asserted). Count known sessions, not devices.

`get_event_offline_preparations(eid uuid,p_limit integer=200,p_offset integer=0)`
returns array rows: preparation_id,assignment_id,staff_user_id,issued_at,expires_at,
revoked_at,uploaded_count,disposition,declared_count,reason,accounted_at,accounted_by.
Order issued_at,preparation_id; null disposition means unaccounted.
`get_event_offline_claims(eid uuid,p_limit integer=200,p_offset integer=0)`
returns array rows: capture_id,preparation_id,checkpoint_id,student_id (text),
staff_user_id,claimed_at,received_at,review_eligible (boolean),decision,reason,
receipt_id,receipt_outcome,reviewed_at,reviewed_by. Order received_at,capture_id;
null decision means unreviewed. Page limit 1..200, offset >=0. One event lock
provides consistent individual reads; separate pages are not one snapshot
during collection. No direct new-table reads/writes. Existing receipt SELECT
remains scoped; offline promoted receipts are manager-only.

## Errors and finalization

42501 denied/unknown/foreign scope or revoked identity; 22023 null/invalid input,
count mismatch or pagination/reason bound; 55000 unavailable state, early seal,
unsealed review, ineligible approval, or unmet reconciliation gate; 23505
conflicting immutable replay. Transport/SQL failure is not success; retry exact
payload after restoring authorization or reload authoritative state.

Confirmation requires sealed uploads, every known preparation accounted for
(including expired/revoked), every submitted claim reviewed. Zero-session events
still need seal and confirmation. Finalization independently rechecks all these
predicates and confirmation under the parent lock, including older clients.
Existing finalized replay, online-only finalization, accepted-only coverage and
classification remain unchanged. Loss accounting does not fabricate evidence;
missing evidence may yield ABSENT/INCOMPLETE in this synthetic prototype.
No automatic finalization, reopening, corrections or student publication.

Additive migration: existing receipts default source online without changes to
identity/outcome/time; existing immutable results preserved. New audit tables
deny direct privileges and mutation. Event lock serializes upload, completion,
seal, loss, review, confirmation and finalization; identity locks maintain live
authorization. No down-migration that removes evidence or restores an ungated
finalizer. Mobile/Web integration, physical QA and operational trust/retention
remain separately gated.
