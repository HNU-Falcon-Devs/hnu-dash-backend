#!/usr/bin/env python3
"""Actual multi-session PostgreSQL reconciliation checks; disposable synthetic only."""
import json
import os
import subprocess
import time

if os.getenv("HNU_DASH_ISOLATED_TEST_DB") != "1":
    raise SystemExit("Refusing non-isolated database access")
names = subprocess.run(["docker", "ps", "--format", "{{.Names}}"],
                       check=True, text=True, capture_output=True).stdout.splitlines()
matching = [name for name in names if name == "supabase_db_hnu-dash-backend"]
if len(matching) != 1:
    raise SystemExit(f"Expected exactly one isolated test database: {matching}")
PSQL = ["docker", "exec", "-i", matching[0], "psql", "-X", "-q", "-A",
        "-t", "-v", "ON_ERROR_STOP=1", "-U", "postgres", "-d", "postgres"]



ORG = "e1000000-0000-4000-8000-000000000001"
STAFF = "e2000000-0000-4000-8000-000000000001"
ADMIN = "e2000000-0000-4000-8000-000000000002"
STUDENT = "00000994001"
EVENT = [f"e3000000-0000-4000-8000-{i:012d}" for i in range(1, 8)]
CP = [f"e4000000-0000-4000-8000-{i:012d}" for i in range(1, 8)]
ASSIGN = [f"e5000000-0000-4000-8000-{i:012d}" for i in range(1, 8)]
REQ = [f"e6000000-0000-4000-8000-{i:012d}" for i in range(1, 8)]
PREP = [f"e7000000-0000-4000-8000-{i:012d}" for i in range(1, 8)]
CAP = [f"e8000000-0000-4000-8000-{i:012d}" for i in range(1, 10)]

def sql(statement):
    r = subprocess.run(PSQL, input=statement, text=True,
                       capture_output=True, timeout=60)
    if r.returncode:
        raise AssertionError(r.stderr)
    return r.stdout.strip()


def start_session(statement):
    p = subprocess.Popen(PSQL, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                         stderr=subprocess.PIPE, text=True)
    p.stdin.write(statement)
    p.stdin.close()
    p.stdin = None
    return p


def until(statement, timeout=8):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if sql(statement).splitlines()[-1:] == ["t"]:
            return True
        time.sleep(.15)
    return False



def session(label, actor, statement, hold=0):
    return start_session(f"""
begin;
set application_name='{label}';
set local role authenticated;
select set_config('request.jwt.claim.sub','{actor}',true);
{statement}
{f'select pg_sleep({hold});' if hold else ''}
commit;
""")


def barrier(label, waiting=False):
    condition = ("cardinality(pg_blocking_pids(pid)) > 0"
                 if waiting else "wait_event='PgSleep'")
    if not until(f"""select exists(select 1 from pg_stat_activity
      where application_name='{label}' and {condition});"""):
        raise AssertionError(f"Session did not reach expected barrier: {label}")


def result(process, expected_error=None):
    out, err = process.communicate(timeout=60)
    if expected_error is not None:
        if process.returncode == 0 or expected_error not in err:
            raise AssertionError(f"Expected error {expected_error}: {out} / {err}")
        return None
    if process.returncode:
        raise AssertionError(err)
    records = [json.loads(line) for line in out.splitlines()
               if line.strip().startswith("{")]
    if len(records) != 1:
        raise AssertionError(f"Expected a single JSON RPC response: {out!r}")
    return records[0]



def fixture(i, closes):
    # The historical preparation is an operator-only fixture; its issuance and
    # expiry precede the real checkpoint close. The actual cutoff is derived
    # by the production activation trigger, never overwritten.
    return f"""
insert into public.events(id,organization_id,created_by,title,starts_at,ends_at)
values ('{EVENT[i]}','{ORG}','{ADMIN}','Synthetic Reconciliation Race {i}',
now()-interval '32 hours',now()+interval '2 hours');
select public.enable_event_offline('{EVENT[i]}');
insert into public.event_checkpoints(id,event_id,label,direction,opens_at,closes_at)
values ('{CP[i]}','{EVENT[i]}','IN','IN',now()-interval '29 hours',{closes});
insert into public.event_roster(event_id,student_id,student_name,program_code,year_level,frozen_at)
values ('{EVENT[i]}','{STUDENT}','Synthetic Reconciliation Race','BSIT',1,now()-interval '30 hours');
insert into public.event_staff(id,event_id,staff_user_id,assigned_at,assigned_by)
values ('{ASSIGN[i]}','{EVENT[i]}','{STAFF}',now()-interval '30 hours','{ADMIN}');
update public.events set roster_frozen_at=now()-interval '30 hours',
state='OPEN',opened_at=now()-interval '30 hours' where id='{EVENT[i]}';
insert into public.offline_preparations(id,request_id,event_id,assignment_id,staff_user_id,issued_at,expires_at)
values ('{PREP[i]}','{REQ[i]}','{EVENT[i]}','{ASSIGN[i]}','{STAFF}',
now()-interval '28 hours',least({closes},now()-interval '20 hours'));
"""


# Each SQL session must use the same immutable timestamp value for a retry.
# Read a synthetic fixture timestamp as operator, not through a Staff bypass.
def upload(i, capture):
    return (f"select public.submit_offline_capture('{PREP[i]}','{capture}',"
            f"'{CP[i]}','{STUDENT}','{CLAIMED[i]}');")


def complete(i, count):
    return f"select public.complete_offline_preparation('{PREP[i]}',{count});"


def seal(i):
    return f"select public.seal_offline_uploads('{EVENT[i]}');"


def loss(i):
    return (f"select public.account_offline_preparation_loss('{EVENT[i]}',"
            f"'{PREP[i]}','missing','Synthetic missing device');")


def review(i, capture, decision="approve"):
    return (f"select public.review_offline_capture('{EVENT[i]}','{capture}',"
            f"'{decision}','Synthetic review evidence');")


def confirm(i):
    return f"select public.confirm_offline_reconciliation('{EVENT[i]}');"


def finalize(i):
    return f"select public.finalize_event('{EVENT[i]}');"


def race(prefix, actor1, statement1, actor2, statement2, error=None):
    first = session(prefix + "-first", actor1, statement1, 9)
    barrier(prefix + "-first")
    second = session(prefix + "-second", actor2, statement2)
    barrier(prefix + "-second", waiting=True)
    return result(first), result(second, error)


def same(a, b):
    if a["replayed"] or not b["replayed"]:
        raise AssertionError(f"Expected original and replay: {a} / {b}")
    if {k: v for k, v in a.items() if k != "replayed"} != {
            k: v for k, v in b.items() if k != "replayed"}:
        raise AssertionError("Replay changed immutable acknowledgement")


sql(f"""
begin;
insert into auth.users(id,instance_id,aud,role,email,email_confirmed_at,created_at,updated_at)
values ('{STAFF}','00000000-0000-0000-0000-000000000000',
'authenticated','authenticated','reconcile-race-staff@hnu.edu.ph',now(),now(),now()),
('{ADMIN}','00000000-0000-0000-0000-000000000000',
'authenticated','authenticated','reconcile-race-admin@hnu.edu.ph',now(),now(),now());
insert into public.platform_admins(user_id) values ('{ADMIN}');
insert into public.organizations(id,slug,name) values ('{ORG}','reconciliation-race','Reconciliation Race');
insert into public.organization_memberships(organization_id,user_id,role,granted_by)
values ('{ORG}','{STAFF}','staff','{ADMIN}');
insert into public.students(student_id,full_name,program_code,year_level)
values ('{STUDENT}','Synthetic Reconciliation Race','BSIT',1);
select set_config('request.jwt.claim.sub','{ADMIN}',true);
""" + "\n".join(fixture(i, "now()-interval '1 hour'" if i < 2 else "now()-interval '25 hours'")
                 for i in range(6)) + f"""
-- Two eligible historical claims for the same slot, and one online-independent
-- event for review/confirmation ordering. Receipt time precedes cutoff.
insert into public.offline_capture_claims(capture_id,preparation_id,event_id,checkpoint_id,
student_id,claimed_at,received_at,review_eligible) values
('{CAP[2]}','{PREP[4]}','{EVENT[4]}','{CP[4]}','{STUDENT}',now()-interval '27 hours',now()-interval '24 hours',true),
('{CAP[3]}','{PREP[4]}','{EVENT[4]}','{CP[4]}','{STUDENT}',now()-interval '27 hours',now()-interval '24 hours',true),
('{CAP[4]}','{PREP[5]}','{EVENT[5]}','{CP[5]}','{STUDENT}',now()-interval '27 hours',now()-interval '24 hours',true);
""" + "\n".join(f"select public.close_event('{EVENT[i]}'); {seal(i)}"
                 for i in range(2, 6)) + "commit;")
CLAIMED = [sql(f"select issued_at from public.offline_preparations where id='{p}';")
           for p in PREP[:6]]

# New upload vs completion in both orders. A completion count is checked
# only after the competing transaction resolves, not against a stale snapshot.
a, b = race("reconcile-upload-complete", STAFF, upload(0, CAP[0]), STAFF, complete(0, 1))
if a["status"] != "submitted" or b["uploaded_count"] != 1:
    raise AssertionError("Completion did not include committed upload")
a, _ = race("reconcile-complete-upload", STAFF, complete(1, 0), STAFF, upload(1, CAP[1]),
            "Offline preparation or upload window is closed")
if a["uploaded_count"] != 0:
    raise AssertionError("Completion invented an upload")
print("PASS: upload and completion serialize in both directions")

# A completed declaration and manager loss disposition cannot both win.
a, _ = race("reconcile-complete-loss", STAFF, complete(2, 0), ADMIN, loss(2),
            "Preparation accounting already recorded")
b, _ = race("reconcile-loss-complete", ADMIN, loss(3), STAFF, complete(3, 0),
            "Preparation accounting already recorded")
if a["disposition"] != "completed" or b["disposition"] != "missing" or b["declared_count"] is not None:
    raise AssertionError("Accounting did not preserve terminal distinction")
print("PASS: completion and loss disposition serialize in both directions")

# Competing reviewers of one capture return original evidence; subsequent
# conflicting decision fails. Another eligible capture of same slot is duplicate.
a, b = race("reconcile-review-retry", ADMIN, review(4, CAP[2]), ADMIN, review(4, CAP[2]))
same(a, b)
if a["receipt_outcome"] != "accepted":
    raise AssertionError("First eligible slot not accepted")
c, _ = race("reconcile-review-conflict", ADMIN, review(4, CAP[3]), ADMIN,
            review(4, CAP[3], "reject"), "Offline claim review already recorded")
if c["receipt_outcome"] != "duplicate":
    raise AssertionError("Second capture did not preserve accepted-slot uniqueness")
print("PASS: review retries and conflicts preserve one accepted slot")

# Confirmation waits for final review; finalization waits for confirmation.
# Before confirmation, an older client cannot publish.
sql(f"""begin; set local role authenticated;
select set_config('request.jwt.claim.sub','{STAFF}',true);
{complete(5, 1)} commit;""")
first = session("reconcile-finalize-before-confirm", ADMIN, finalize(5))
result(first, "Offline-enabled events require reconciliation before finalization")
a, b = race("reconcile-review-confirm", ADMIN, review(5, CAP[4]), ADMIN, confirm(5))
if a["receipt_outcome"] != "accepted" or b["replayed"]:
    raise AssertionError("Confirmation missed committed review")
# Use a separate real transaction that first acquires the confirmation replay
# lock, then holds it while finalization waits. Confirmation cannot be undone.
a, b = race("reconcile-confirm-finalize", ADMIN, confirm(5), ADMIN, finalize(5))
if not a["replayed"] or b["record_count"] != 1:
    raise AssertionError("Finalization did not observe committed reconciliation")
print("PASS: review/confirmation/finalization serialize; old client denied before confirmation")

# Cutoff boundary with actual server clock. A valid pre-cutoff upload holds the
# event lock across expiry; sealing must wait, then a new UUID must fail.
sql("begin; select set_config('request.jwt.claim.sub','" + ADMIN + "',true);" +
    fixture(6, "now()-interval '24 hours'+interval '20 seconds'") +
    f"select public.close_event('{EVENT[6]}'); commit;")
CLAIMED.append(sql(f"select issued_at from public.offline_preparations where id='{PREP[6]}';"))
first = session("reconcile-cutoff-upload", STAFF, upload(6, CAP[5]), 35)
barrier("reconcile-cutoff-upload")
if not until(f"select clock_timestamp() >= offline_upload_cutoff from public.events where id='{EVENT[6]}';", timeout=30):
    raise AssertionError("Server cutoff not reached")
second = session("reconcile-cutoff-seal", ADMIN, seal(6))
barrier("reconcile-cutoff-seal", waiting=True)
a, b = result(first), result(second)
if a["status"] != "submitted" or b["replayed"]:
    raise AssertionError("Pre-cutoff upload or seal failed")
_, _ = race("reconcile-seal-upload", ADMIN, seal(6), STAFF, upload(6, CAP[6]),
            "Offline preparation or upload window is closed")
replay = result(session("reconcile-seal-replay", STAFF, upload(6, CAP[5])))
if not replay["replayed"] or replay["received_at"] != a["received_at"]:
    raise AssertionError("Sealing changed original upload acknowledgement")
print("PASS: pre-cutoff upload committed before seal; new post-seal claim denied and replay preserved")

counts = sql(f"""select
 (select count(*) from public.offline_capture_claims where event_id='{EVENT[6]}'),
 (select count(*) from public.attendance_scans where event_id='{EVENT[4]}' and outcome='accepted'),
 (select count(*) from public.attendance_scans where event_id='{EVENT[4]}' and outcome='duplicate'),
 (select count(*) from public.attendance_records where event_id='{EVENT[5]}' and status='PRESENT'),
 (select count(*) from public.offline_claim_reviews r join public.offline_capture_claims c
   on c.capture_id=r.capture_id where c.event_id='{EVENT[4]}');""")
if counts != "1|1|1|1|2":
    raise AssertionError(f"Unexpected persisted claim/receipt/result/review counts: {counts}")
print("PASS: independent durable counts agree with serialized decisions")
