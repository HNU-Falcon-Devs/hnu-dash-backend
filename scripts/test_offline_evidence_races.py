#!/usr/bin/env python3
"""Concurrent PostgreSQL M4.1 evidence tests; disposable synthetic stack only."""
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



ORG = "c1000000-0000-4000-8000-000000000001"
STAFF = "c2000000-0000-4000-8000-000000000001"
ADMIN = "c2000000-0000-4000-8000-000000000002"
EVENTS = [f"c3000000-0000-4000-8000-{i:012d}" for i in range(1, 5)]
CPS = [f"c4000000-0000-4000-8000-{i:012d}" for i in range(1, 5)]
ASSIGNMENTS = [f"c5000000-0000-4000-8000-{i:012d}" for i in range(1, 5)]
REQUESTS = [f"c6000000-0000-4000-8000-{i:012d}" for i in range(1, 8)]
HISTORICAL = [f"c7000000-0000-4000-8000-{i:012d}" for i in range(1, 3)]
CAPTURES = [f"c8000000-0000-4000-8000-{i:012d}" for i in range(1, 7)]
STUDENT = "00000993001"
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



# A scalar-returning revoke RPC is wrapped in JSON for the shared parser.
def revoke(assignment):
    return f"select jsonb_build_object('assignment_id',public.revoke_event_staff('{assignment}'));"


def prepare(event, request):
    return f"select public.prepare_offline_capture('{event}','{request}');"


def upload(prep, capture, cp, claimed, student=STUDENT):
    return (f"select public.submit_offline_capture('{prep}','{capture}',"
            f"'{cp}','{student}','{claimed}');")


def race(prefix, actor1, statement1, actor2, statement2, error=None):
    first = session(prefix + "-first", actor1, statement1, 9)
    barrier(prefix + "-first")
    second = session(prefix + "-second", actor2, statement2)
    barrier(prefix + "-second", waiting=True)
    return result(first), result(second, error)


def same_receipt(a, b):
    if a["replayed"] or not b["replayed"]:
        raise AssertionError(f"Incorrect original/replay flags: {a} / {b}")
    if {k: v for k, v in a.items() if k != "replayed"} != {
            k: v for k, v in b.items() if k != "replayed"}:
        raise AssertionError("Retry changed authoritative acknowledgement")


sql(f"""
begin;
insert into auth.users(id,instance_id,aud,role,email,email_confirmed_at,created_at,updated_at)
values ('{STAFF}','00000000-0000-0000-0000-000000000000',
'authenticated','authenticated','offline-race-staff@hnu.edu.ph',now(),now(),now()),
('{ADMIN}','00000000-0000-0000-0000-000000000000',
'authenticated','authenticated','offline-race-admin@hnu.edu.ph',now(),now(),now());
insert into public.platform_admins(user_id) values ('{ADMIN}');
insert into public.organizations(id,slug,name) values ('{ORG}','offline-race','Offline Race');
insert into public.organization_memberships(organization_id,user_id,role,granted_by)
values ('{ORG}','{STAFF}','staff','{ADMIN}');
insert into public.students(student_id,full_name,program_code,year_level)
values ('{STUDENT}','Synthetic Offline Race','BSIT',1);
select set_config('request.jwt.claim.sub','{ADMIN}',true);
"""+ "\n".join(f"""
insert into public.events(id,organization_id,created_by,title,starts_at,ends_at)
values ('{event}','{ORG}','{ADMIN}','Synthetic Offline Race {i}',
now()-interval '4 hours',now()+interval '4 hours');
select public.enable_event_offline('{event}');
insert into public.event_checkpoints(id,event_id,label,direction,opens_at,closes_at)
values ('{CPS[i]}','{event}','IN','IN',now()-interval '3 hours',
now() {'+' if i < 2 else '-'} interval '1 hour');
insert into public.event_roster(event_id,student_id,student_name,program_code,year_level,frozen_at)
values ('{event}','{STUDENT}','Synthetic Offline Race','BSIT',1,now()-interval '3 hours');
insert into public.event_staff(id,event_id,staff_user_id,assigned_at,assigned_by)
values ('{ASSIGNMENTS[i]}','{event}','{STAFF}',now()-interval '3 hours','{ADMIN}');
update public.events set roster_frozen_at=now()-interval '3 hours',
state='OPEN',opened_at=now()-interval '3 hours' where id='{event}';
""" for i, event in enumerate(EVENTS)) + "\n" + "\n".join(f"""
-- Historical prepared context, with real ended checkpoint and live cutoff.
insert into public.offline_preparations(id,request_id,event_id,assignment_id,
staff_user_id,issued_at,expires_at)
values ('{HISTORICAL[i]}','{REQUESTS[i+4]}','{EVENTS[i+2]}',
'{ASSIGNMENTS[i+2]}','{STAFF}',now()-interval '2 hours',now()-interval '1 hour');
""" for i in range(2)) + "commit;")

# Identical preparation request racing an uncommitted original must replay,
# and a different competing request for another event must not overlap.
a, b = race("offline-prepare-retry", STAFF, prepare(EVENTS[0], REQUESTS[0]),
            STAFF, prepare(EVENTS[0], REQUESTS[0]))
same_receipt(a, b)
if sql(f"select count(*) from public.offline_preparations where event_id='{EVENTS[0]}';") != "1":
    raise AssertionError("Duplicate/orphan preparation")
print("PASS: competing identical preparation requests replay one immutable session")
c, _ = race("offline-prepare-active", STAFF, prepare(EVENTS[1], REQUESTS[1]),
            STAFF, prepare(EVENTS[1], REQUESTS[2]), "An active offline preparation already exists")
if sql(f"select count(*) from public.offline_preparations where event_id='{EVENTS[1]}';") != "1":
    raise AssertionError("Competing preparations overlapped")
print("PASS: competing distinct requests cannot create overlapping sessions")

p, when = a["preparation_id"], a["issued_at"]
statement = upload(p, CAPTURES[0], CPS[0], when)
x, y = race("offline-capture-retry", STAFF, statement, STAFF, statement)
same_receipt(x, y)
if x["status"] != "submitted" or "review_eligible" in x or "outcome" in x:
    raise AssertionError("Upload acknowledgement leaked eligibility or acceptance")
print("PASS: competing identical uploads replay one immutable claim")

# Closure accepts no new online scan but is deliberately compatible with
# offline upload in SYNCING. Exercise both orderings on two historical events.
claim_time = sql(f"select issued_at from public.offline_preparations where id='{HISTORICAL[0]}';")
x, y = race("offline-upload-close", STAFF,
            upload(HISTORICAL[0], CAPTURES[1], CPS[2], claim_time),
            ADMIN, f"select public.close_event('{EVENTS[2]}');")
if x["status"] != "submitted" or y["event_state"] != "SYNCING":
    raise AssertionError("Upload before closure failed")
claim_time = sql(f"select issued_at from public.offline_preparations where id='{HISTORICAL[1]}';")
x, y = race("offline-close-upload", ADMIN, f"select public.close_event('{EVENTS[3]}');",
            STAFF, upload(HISTORICAL[1], CAPTURES[2], CPS[3], claim_time))
if x["event_state"] != "SYNCING" or y["status"] != "submitted":
    raise AssertionError("Upload after closure failed")
print("PASS: upload and closure serialize in both directions")

# Revocation must wait for already-authorized upload; an upload waiting on a
# committed revocation fails without writing, even with an old preparation.
x, y = race("offline-upload-revoke", STAFF, upload(p, CAPTURES[3], CPS[0], when),
            ADMIN, revoke(ASSIGNMENTS[0]))
if x["status"] != "submitted" or y["assignment_id"] != ASSIGNMENTS[0]:
    raise AssertionError("Upload before revocation failed")
race("offline-revoke-upload", ADMIN, revoke(ASSIGNMENTS[1]), STAFF,
     upload(c["preparation_id"], CAPTURES[4], CPS[1], c["issued_at"]),
     "Offline evidence not permitted")
print("PASS: upload and revocation serialize in both directions")

counts = sql(f"""
select (select count(*) from public.offline_capture_claims where event_id in
 ({','.join("'" + event + "'" for event in EVENTS)})),
 (select count(*) from public.attendance_scans where event_id in
 ({','.join("'" + event + "'" for event in EVENTS)})),
 (select count(*) from public.attendance_records where event_id in
 ({','.join("'" + event + "'" for event in EVENTS)}));""")
if counts != "4|0|0":
    raise AssertionError(f"Unexpected claim/receipt/result deltas: {counts}")
print("PASS: exactly four claims; no canonical receipts or finalized results")
