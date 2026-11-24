# Milestone 3.2A — Online attendance finalization prototype

Authorized under [Backend #12](https://github.com/HNU-Falcon-Devs/hnu-dash-backend/issues/12).
**Synthetic-only development.** Results are not institution-approved attendance,
pilot approval, real student processing, or hosted deployment authorization.
This extends [M3.1 coverage](milestone-3-part-1-checkpoint-coverage.md)
and preserves [M2.3 receipt ingestion](milestone-2-part-3-scan-ingestion.md).

## Manager API

Use the authenticated verified HNU session and publishable/anon key.
Only the owning organization's active Leader or authorized platform Admin may
perform any of the following operations. No client role, organization, timestamp,
status or student assertions are accepted.

| Call | Response / behavior |
| --- | --- |
| `rpc('close_event',{eid})` | JSON object: event_id, event_state (SYNCING), closed_at, closed_by. Requires OPEN, frozen nonempty roster, checkpoints, and all checkpoint windows ended at server time. |
| `rpc('finalize_event',{eid})` | JSON object: event_id, event_state (FINALIZED), finalized_at, finalized_by, record_count, replayed. Requires explicit prior closure. Retry returns original metadata and stored count with replayed=true; no recalculation. |
| `rpc('get_event_finalized_results',{eid,p_limit:200,p_offset:0})` | Array of rows: event_id, student_id (text), status, required_checkpoint_count, accepted_checkpoint_count, finalized_at, finalized_by. FINALIZED only, ordered by Student ID (C collation); page size 1..200, offset >= 0. |

Unknown and out-of-scope events return 42501, including assigned Staff,
unverified/inactive/non-owning leaders. Anonymous EXECUTE is revoked.
Null IDs and invalid pagination fail 22023. Invalid transition, early closure,
or non-finalized reads fail 55000. Missing frozen roster or checkpoints fail
22023 when checked during an otherwise permitted transition. Repeated closure
fails 55000; finalization is replay-safe. No direct client result-table grants.
Managers have no direct event update or record write authority.

## Evidence and transaction boundary

SYNCING means closed to new online evidence and awaiting explicit organizer
review; it does **not** assert offline upload completion. Closure waits on
the event-row lock held by in-flight M2.3 ingestion. New UUIDs fail 55000
once closure commits; still-authorized identical retries replay the original
receipt unchanged in SYNCING or FINALIZED.

Finalization obtains an exclusive parent-event row lock and inserts exactly
one result per frozen-roster student in a single transaction. It counts
accepted receipts for configured checkpoints only; rejected/duplicate
receipts, cross-event or non-roster evidence do not contribute.
All configured checkpoints are required for this prototype, including IN-only:

- PRESENT: all checkpoints have accepted evidence.
- INCOMPLETE: some but not all have accepted evidence.
- ABSENT: none have accepted evidence.

Event+student primary key and composite frozen-roster foreign key preserve
identity and uniqueness. Counts and status are constrained; record updates
and deletes and changes to populated closure/finalization audit metadata
are rejected. Event actor/time are captured from trusted identity and
server clock. Any failed insert or event update rolls the transaction back.
There is no partial publication, automatic finalization or re-finalization.
The M3.1 paged preview is not used as a snapshot.

Offline capture/trust, optional checkpoints, LATE/EXCUSED, correction,
appeals, grace/LOCKED, student self-view, actual QR decoding, hosted deployment
and consumer changes remain deferred.
