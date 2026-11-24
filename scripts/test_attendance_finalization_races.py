#!/usr/bin/env python3
"""Real PostgreSQL sessions exercise closure/ingestion and finalization races.

Synthetic fixtures only, on the disposable CI Supabase stack.
"""
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


ORG = "a1000000-0000-4000-8000-000000000001"
STAFF = "a2000000-0000-4000-8000-000000000001"
ADMIN = "a2000000-0000-4000-8000-000000000002"
EVENT = "a3000000-0000-4000-8000-000000000001"
EVENT2 = "a3000000-0000-4000-8000-000000000002"
CP = "a4000000-0000-4000-8000-000000000001"
CP2 = "a4000000-0000-4000-8000-000000000002"
SCAN = "a5000000-0000-4000-8000-000000000001"
SCAN2 = "a5000000-0000-4000-8000-000000000002"
STUDENT = "00000992001"

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


sql(f"""
begin;
insert into auth.users(id,instance_id,aud,role,email,email_confirmed_at,created_at,updated_at)
values ('{STAFF}','00000000-0000-0000-0000-000000000000',
'authenticated','authenticated','finalize-race-staff@hnu.edu.ph',now(),now(),now()),
('{ADMIN}','00000000-0000-0000-0000-000000000000',
'authenticated','authenticated','finalize-race-admin@hnu.edu.ph',now(),now(),now());
insert into public.platform_admins(user_id) values ('{ADMIN}');
insert into public.organizations(id,slug,name)
values ('{ORG}','finalization-race','Finalization Race');
insert into public.organization_memberships(organization_id,user_id,role,granted_by)
values ('{ORG}','{STAFF}','staff','{ADMIN}');
insert into public.students(student_id,full_name,program_code,year_level)
values ('{STUDENT}','Synthetic Finalization Race','BSIT',1);
insert into public.events(id,organization_id,created_by,title,starts_at,ends_at)
values ('{EVENT}','{ORG}','{ADMIN}','Ingestion First',
now()-interval '1 hour',now()+interval '1 hour'),
('{EVENT2}','{ORG}','{ADMIN}','Closure First',
now()-interval '1 hour',now()+interval '1 hour');
select set_config('request.jwt.claim.sub','{ADMIN}',true);
insert into public.event_checkpoints(id,event_id,label,direction,opens_at,closes_at)
values ('{CP}','{EVENT}','IN','IN',now()-interval '30 minutes',clock_timestamp()+interval '20 seconds'),
('{CP2}','{EVENT2}','IN','IN',now()-interval '30 minutes',now()-interval '10 minutes');
insert into public.event_roster(event_id,student_id,student_name,program_code,year_level)
select e.id,'{STUDENT}','Synthetic Finalization Race','BSIT',1,now()
from public.events e where e.id in ('{EVENT}','{EVENT2}');
update public.events set roster_frozen_at=now(),state='OPEN',opened_at=now()
where id in ('{EVENT}','{EVENT2}');
insert into public.event_staff(event_id,staff_user_id,assigned_by)
values ('{EVENT}','{STAFF}','{ADMIN}'),('{EVENT2}','{STAFF}','{ADMIN}');
commit;
""")


def ingest(scan, event, cp):
    return f"select public.ingest_attendance_scan('{scan}','{event}','{cp}','{STUDENT}');"


# Ordering A: accepted evidence exists in an uncommitted transaction. Wait
# until its checkpoint closes before attempting the legitimate closure.
first = session("finalization-ingest-first", STAFF, ingest(SCAN, EVENT, CP), 35)
barrier("finalization-ingest-first")
if not until(f"""select clock_timestamp() >= closes_at
  from public.event_checkpoints where id='{CP}';""", timeout=30):
    raise AssertionError("Checkpoint did not reach server-clock closure boundary")
second = session("finalization-close-second", ADMIN,
                 f"select public.close_event('{EVENT}');")
barrier("finalization-close-second", waiting=True)
accepted = result(first)
closed = result(second)
if accepted["outcome"] != "accepted" or accepted["replayed"]:
    raise AssertionError(f"Expected committed accepted receipt: {accepted}")
if closed["event_state"] != "SYNCING":
    raise AssertionError(f"Expected successful closure: {closed}")
print("PASS: closure waited for in-flight accepted evidence")

# Ordering B: closure holds the row lock; a new UUID must wait and then
# fail without creating a rejected or accepted receipt.
first = session("finalization-close-first", ADMIN,
                f"select public.close_event('{EVENT2}');", 9)
barrier("finalization-close-first")
second = session("finalization-ingest-second", STAFF, ingest(SCAN2, EVENT2, CP2))
barrier("finalization-ingest-second", waiting=True)
result(first)
result(second, "Online scan ingestion requires an OPEN event")
if sql(f"select count(*) from public.attendance_scans where scan_id='{SCAN2}';") != "0":
    raise AssertionError("New UUID persisted after closure")
print("PASS: ingestion waited for closure then failed without new evidence")

# Competing finalizers must serialize and return the same durable metadata.
first = session("finalization-first", ADMIN,
                f"select public.finalize_event('{EVENT}');", 9)
barrier("finalization-first")
second = session("finalization-second", ADMIN,
                 f"select public.finalize_event('{EVENT}');")
barrier("finalization-second", waiting=True)
a, b = result(first), result(second)
if a["replayed"] or not b["replayed"] or a["record_count"] != 1:
    raise AssertionError(f"Unexpected finalize/retry outcome: {a} / {b}")
if {k: v for k, v in a.items() if k != "replayed"} != {
        k: v for k, v in b.items() if k != "replayed"}:
    raise AssertionError("Concurrent retry changed authoritative metadata")
if sql(f"""select status || ':' || accepted_checkpoint_count
  from public.attendance_records where event_id='{EVENT}';""") != "PRESENT:1":
    raise AssertionError("Committed in-flight accepted evidence missing from finalized result")
print("PASS: concurrent finalizers serialized; one PRESENT record and unchanged audit")
