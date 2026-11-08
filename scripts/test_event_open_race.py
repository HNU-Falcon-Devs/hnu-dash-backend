#!/usr/bin/env python3
"""Real two-session DRAFT -> OPEN concurrency regression.

Use only a disposable local Supabase CLI stack with synthetic records.
"""
import os
import subprocess
import time

if os.getenv("HNU_DASH_ISOLATED_TEST_DB") != "1":
    raise SystemExit("An isolated Supabase test database is required")
names = subprocess.run(["docker", "ps", "--format", "{{.Names}}"],
                       check=True, text=True, capture_output=True).stdout.splitlines()
matching = [n for n in names if n == "supabase_db_hnu-dash-backend"]
if len(matching) != 1:
    raise SystemExit(f"Expected one isolated HNU DASH database, got {matching}")

PSQL = ["docker", "exec", "-i", matching[0], "psql",
        "-X", "-q", "-A", "-t", "-v", "ON_ERROR_STOP=1",
        "-U", "postgres", "-d", "postgres"]
EVENT = "52000000-0000-4000-8000-000000000001"
ORG = "53000000-0000-4000-8000-000000000001"
LEADER = "54000000-0000-4000-8000-000000000001"
STUDENT = "00009990111"


def sql(statement):
    r = subprocess.run(PSQL, input=statement, text=True,
                       capture_output=True, timeout=30)
    if r.returncode != 0:
        raise AssertionError(f"psql query failed: {r.stderr}")
    return r.stdout.strip()


def start_session(statement):
    p = subprocess.Popen(PSQL, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                         stderr=subprocess.PIPE, text=True)
    p.stdin.write(statement)
    p.stdin.close()
    p.stdin = None
    return p


def until(statement, timeout=9):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if sql(statement).splitlines()[-1:] == ["t"]:
            return True
        time.sleep(0.15)
    return False


sql(f"""
begin;
insert into auth.users(id,instance_id,aud,role,email,email_confirmed_at,created_at,updated_at)
values ('{LEADER}','00000000-0000-0000-0000-000000000000',
'authenticated','authenticated','open-race@hnu.edu.ph',now(),now(),now());
insert into public.students(student_id,full_name,program_code,year_level)
values ('{STUDENT}','Synthetic Activation Student','BSIT',1);
insert into public.organizations(id,slug,name)
values ('{ORG}','open-race-demo','Open Race Demo');
insert into public.organization_memberships(organization_id,user_id,role,granted_by)
values ('{ORG}','{LEADER}','leader','{LEADER}');
insert into public.events(id,organization_id,created_by,title,starts_at,ends_at)
values ('{EVENT}','{ORG}','{LEADER}','Concurrent Event',
'2041-01-01 00:00+00','2041-01-02 00:00+00');
set local role authenticated;
select set_config('request.jwt.claim.sub','{LEADER}',true);
insert into public.event_checkpoints(event_id,label,direction,opens_at,closes_at)
values ('{EVENT}','One In','IN',
'2041-01-01 08:00+08','2041-01-01 09:00+08');
select public.freeze_event_roster('{EVENT}');
commit;
""")

first = start_session(f"""
begin;
set application_name='hnu-dash-first-opener';
set local role authenticated;
select set_config('request.jwt.claim.sub','{LEADER}',true);
select event_state from public.open_event('{EVENT}');
select pg_sleep(10);
commit;
""")
if not until("""select exists(
 select 1 from pg_stat_activity where application_name='hnu-dash-first-opener'
 and wait_event='PgSleep');"""):
    raise AssertionError("First activation never reached its open-event lock barrier")

second = start_session(f"""
begin;
set application_name='hnu-dash-second-opener';
set local role authenticated;
select set_config('request.jwt.claim.sub','{LEADER}',true);
select event_state from public.open_event('{EVENT}');
commit;
""")
blocked = until("""select exists(
 select 1 from pg_stat_activity a where a.application_name='hnu-dash-second-opener'
 and cardinality(pg_blocking_pids(a.pid)) > 0);""")
out_one, err_one = first.communicate(timeout=35)
out_two, err_two = second.communicate(timeout=35)
if not blocked:
    raise AssertionError("Competing activation was never observed waiting on event lock")
if first.returncode != 0 or "OPEN" not in out_one:
    raise AssertionError(f"First activation failed: {out_one} {err_one}")
if second.returncode == 0 or "Only a DRAFT event can be opened" not in err_two:
    raise AssertionError(f"Second activation was not rejected: {out_two} {err_two}")

state, timestamp, checkpoints, roster = sql(f"""select state,
 (opened_at is not null)::int,
 (select count(*) from public.event_checkpoints where event_id='{EVENT}'),
 (select count(*) from public.event_roster where event_id='{EVENT}')
from public.events where id='{EVENT}';""").split("|")
if (state, timestamp, checkpoints, roster) != ("OPEN", "1", "1", "1"):
    raise AssertionError(
        f"Unexpected committed event state: {(state, timestamp, checkpoints, roster)}")
print("PASS: first opener committed; second blocked then rejected; roster/checkpoints preserved")
