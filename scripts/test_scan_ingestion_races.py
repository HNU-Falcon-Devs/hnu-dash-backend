#!/usr/bin/env python3
"""Two real PostgreSQL sessions verify UUID retries and capture uniqueness.

Requires fresh isolated Supabase test stack; no hosted credentials or real students.
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

ORG = "71000000-0000-4000-8000-000000000001"
STAFF = "72000000-0000-4000-8000-000000000001"
ADMIN = "72000000-0000-4000-8000-000000000002"
EVENT = "73000000-0000-4000-8000-000000000001"
CP1 = "74000000-0000-4000-8000-000000000001"
CP2 = "74000000-0000-4000-8000-000000000002"
STUDENT = "00000991001"
SAME_UUID = "75000000-0000-4000-8000-000000000001"
DISTINCT_UUID = "75000000-0000-4000-8000-000000000002"
DIFFERENT_UUID = "75000000-0000-4000-8000-000000000003"


def sql(statement):
    r = subprocess.run(PSQL, input=statement, text=True,
                       capture_output=True, timeout=35)
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


sql(f"""
begin;
insert into auth.users(id,instance_id,aud,role,email,email_confirmed_at,created_at,updated_at)
values ('{STAFF}','00000000-0000-0000-0000-000000000000',
'authenticated','authenticated','scan-race@hnu.edu.ph',now(),now(),now()),
('{ADMIN}','00000000-0000-0000-0000-000000000000',
'authenticated','authenticated','admin-scan-race@hnu.edu.ph',now(),now(),now());
insert into public.platform_admins(user_id) values ('{ADMIN}');
insert into public.students(student_id,full_name,program_code,year_level)
values ('{STUDENT}','Synthetic Scan Race','BSIT',1);
insert into public.organizations(id,slug,name)
values ('{ORG}','ingest-race','Ingest Race');
insert into public.organization_memberships(organization_id,user_id,role,granted_by)
values ('{ORG}','{STAFF}','staff','{STAFF}');
insert into public.events(id,organization_id,created_by,title,starts_at,ends_at)
values ('{EVENT}','{ORG}','{STAFF}','Synthetic Concurrent Scan Event',
now()-interval '2 hours',now()+interval '2 hours');
-- Isolated operator fixture supplies deterministic UUIDs; the checkpoint
-- trigger still verifies a real, independently provisioned Admin account.
select set_config('request.jwt.claim.sub','{ADMIN}',true);
insert into public.event_checkpoints(id,event_id,label,direction,opens_at,closes_at)
values
('{CP1}','{EVENT}','Concurrent IN','IN',now()-interval '30 minutes',now()+interval '30 minutes'),
('{CP2}','{EVENT}','Concurrent OUT','OUT',now()-interval '30 minutes',now()+interval '30 minutes');
insert into public.event_roster(event_id,student_id,student_name,program_code,year_level,frozen_at)
values ('{EVENT}','{STUDENT}','Synthetic Scan Race','BSIT',1,now());
update public.events
set roster_frozen_at=now(),state='OPEN',opened_at=now() where id='{EVENT}';
insert into public.event_staff(event_id,staff_user_id,assigned_by)
values ('{EVENT}','{STAFF}','{STAFF}');
commit;
""")


def request(scan_id, checkpoint):
    return (f"select public.ingest_attendance_scan('{scan_id}',"
            f"'{EVENT}','{checkpoint}','{STUDENT}');")


def actor_sql(application_name, statement, hold=False):
    return f"""
begin;
set application_name='{application_name}';
set local role authenticated;
select set_config('request.jwt.claim.sub','{STAFF}',true);
{statement}
{'select pg_sleep(9);' if hold else ''}
commit;
"""


def run_race(prefix, first_id, second_id, checkpoint, expected):
    one = start_session(actor_sql(prefix + '-first', request(first_id, checkpoint), hold=True))
    if not until(f"""select exists(select 1 from pg_stat_activity
          where application_name='{prefix}-first' and wait_event='PgSleep');"""):
        raise AssertionError("First receipt did not reach its transaction barrier")
    two = start_session(actor_sql(prefix + '-second', request(second_id, checkpoint)))
    blocked = until(f"""select exists(select 1 from pg_stat_activity a
      where a.application_name='{prefix}-second'
        and cardinality(pg_blocking_pids(a.pid)) > 0);""")
    first_output, first_error = one.communicate(timeout=35)
    second_output, second_error = two.communicate(timeout=35)
    if not blocked:
        raise AssertionError("Concurrent scan did not wait on database uniqueness")
    if one.returncode or two.returncode:
        raise AssertionError(f"Concurrent submissions failed: {first_error} / {second_error}")
    # The transaction contains SET and pg_sleep statements, so the final
    # stdout line is not necessarily the receipt JSON.
    def receipt(output):
        records = [line for line in output.splitlines() if line.strip().startswith("{")]
        if len(records) != 1:
            raise AssertionError(f"Expected one JSON receipt in session output: {output!r}")
        return json.loads(records[0])

    first = receipt(first_output)
    second = receipt(second_output)
    if first["outcome"] != "accepted" or first["replayed"]:
        raise AssertionError(f"First submission not accepted: {first}")
    if second["outcome"] != expected["outcome"] or second["replayed"] != expected["replayed"]:
        raise AssertionError(f"Unexpected second receipt: {second}")
    if first_id == second_id and first["received_at"] != second["received_at"]:
        raise AssertionError("Identical retries did not return the original receipt timestamp")


run_race("scan-race-retry", SAME_UUID, SAME_UUID, CP1,
         {"outcome": "accepted", "replayed": True})
run_race("scan-race-duplicate", DISTINCT_UUID, DIFFERENT_UUID, CP2,
         {"outcome": "duplicate", "replayed": False})
counts = sql(f"""select
 (select count(*) from public.attendance_scans where event_id='{EVENT}'),
 (select count(*) from public.attendance_scans where event_id='{EVENT}' and outcome='accepted'),
 (select count(*) from public.attendance_scans where event_id='{EVENT}' and outcome='duplicate');""").split("|")
if counts != ["3", "2", "1"]:
    raise AssertionError(f"Unexpected durable receipt/uniqueness counts: {counts}")
print("PASS: UUID retry blocked then replayed; distinct concurrent scan kept duplicate evidence")

# Revocation uses FOR UPDATE on event_staff, while scan ingestion takes
# FOR SHARE on the same effective assignment row. Confirm both orderings:
# an already-authorized in-flight receipt commits before revocation; a scan
# waiting behind a committed revocation is denied without any new evidence.
assignment_id = sql(f"""select id from public.event_staff
 where event_id='{EVENT}' and staff_user_id='{STAFF}' and revoked_at is null;""")
if not assignment_id:
    raise AssertionError("No eligible active Staff assignment to revoke")

IN_FLIGHT_UUID = "75000000-0000-4000-8000-000000000004"
POST_REVOKE_UUID = "75000000-0000-4000-8000-000000000005"


def revoke_sql(label, assignment, hold=False):
    return f"""
begin;
set application_name='{label}';
set local role authenticated;
select set_config('request.jwt.claim.sub','{ADMIN}',true);
select public.revoke_event_staff('{assignment}');
{'select pg_sleep(9);' if hold else ''}
commit;
"""


def ensure_blocked(label):
    if not until(f"""select exists(select 1 from pg_stat_activity a
         where a.application_name='{label}'
           and cardinality(pg_blocking_pids(a.pid)) > 0);"""):
        raise AssertionError(f"Session was not blocked on the assignment row: {label}")


def ensure_sleep(label):
    if not until(f"""select exists(select 1 from pg_stat_activity
         where application_name='{label}' and wait_event='PgSleep');"""):
        raise AssertionError(f"Session did not reach its transaction barrier: {label}")


# Case 1: receipt already authorized and in flight; revocation waits until
# the receipt commits. CP1 is already accepted, so this is a duplicate receipt.
scan_before = start_session(actor_sql(
    "scan-before-revocation", request(IN_FLIGHT_UUID, CP1), hold=True))
ensure_sleep("scan-before-revocation")
revoke_after = start_session(revoke_sql(
    "revocation-after-scan", assignment_id))
ensure_blocked("revocation-after-scan")
scan_out, scan_err = scan_before.communicate(timeout=35)
revoke_out, revoke_err = revoke_after.communicate(timeout=35)
if scan_before.returncode or revoke_after.returncode:
    raise AssertionError(
        f"In-flight scan / revocation failed: {scan_err} / {revoke_err}")
scan_receipts = [line for line in scan_out.splitlines()
                 if line.strip().startswith("{")]
if len(scan_receipts) != 1:
    raise AssertionError("Expected one in-flight scan receipt")
scan_receipt = json.loads(scan_receipts[0])
if scan_receipt["outcome"] != "duplicate" or scan_receipt["replayed"]:
    raise AssertionError(f"Unexpected in-flight scan result: {scan_receipt}")
if sql(f"""select count(*) from public.attendance_scans
          where scan_id='{IN_FLIGHT_UUID}';""") != "1":
    raise AssertionError("In-flight scan receipt was not committed")
if sql(f"""select count(*) from public.event_staff
          where id='{assignment_id}' and revoked_at is not null;""") != "1":
    raise AssertionError("Revocation did not commit after the authorized scan")

# Reassign using the authorized admin RPC, not a direct assignment write.
sql(f"""
begin;
set local role authenticated;
select set_config('request.jwt.claim.sub','{ADMIN}',true);
select public.assign_event_staff('{EVENT}','{STAFF}');
commit;
""")
new_assignment = sql(f"""select id from public.event_staff
 where event_id='{EVENT}' and staff_user_id='{STAFF}'
   and revoked_at is null;""")
if not new_assignment or new_assignment == assignment_id:
    raise AssertionError("Admin re-assignment did not create a new active period")

# Case 2: a revocation is already in flight; subsequent scan is blocked on
# the same row and MUST fail after that revocation commits.
revoke_before = start_session(revoke_sql(
    "revocation-before-scan", new_assignment, hold=True))
ensure_sleep("revocation-before-scan")
scan_after = start_session(actor_sql(
    "scan-after-revocation", request(POST_REVOKE_UUID, CP1)))
ensure_blocked("scan-after-revocation")
revoke_out, revoke_err = revoke_before.communicate(timeout=35)
after_out, after_err = scan_after.communicate(timeout=35)
if revoke_before.returncode:
    raise AssertionError(f"Revocation failed: {revoke_err}")
if scan_after.returncode == 0 or "Scan submission not permitted" not in after_err:
    raise AssertionError(
        f"Scan did not fail closed after revocation: {after_out} / {after_err}")
if sql(f"""select count(*) from public.attendance_scans
          where scan_id='{POST_REVOKE_UUID}';""") != "0":
    raise AssertionError("Revoked Staff created durable scan evidence")
if sql(f"""select count(*) from public.event_staff
          where id='{new_assignment}' and revoked_at is not null;""") != "1":
    raise AssertionError("Final revocation did not commit")
print("PASS: scan/revocation ordering serialized in both directions; post-revoke scan denied")

