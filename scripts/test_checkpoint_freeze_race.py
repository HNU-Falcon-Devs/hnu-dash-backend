#!/usr/bin/env python3
"""Verify checkpoint writes cannot cross a concurrent roster freeze.

Run only against a freshly reset, disposable local Supabase test stack.
Uses two independent PostgreSQL sessions, and confirms actual row-lock blocking.
No third-party Python dependencies.
"""
import os
import subprocess
import time

if os.getenv("HNU_DASH_ISOLATED_TEST_DB") != "1":
    raise SystemExit("Refusing to use a database without the isolated-test flag")

names = subprocess.run(
    ["docker", "ps", "--format", "{{.Names}}"], check=True,
    text=True, capture_output=True,
).stdout.splitlines()
matching = [n for n in names if n == "supabase_db_hnu-dash-backend"]
if len(matching) != 1:
    raise SystemExit(f"Expected a single local HNU DASH database container, got {matching}")

PSQL = ["docker", "exec", "-i", matching[0], "psql",
        "-X", "-q", "-A", "-t", "-v", "ON_ERROR_STOP=1",
        "-U", "postgres", "-d", "postgres"]
EVENT = "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee"
ORG = "eeeeeeee-aaaa-4eee-8eee-eeeeeeeeeeee"
LEADER = "eeeeeeee-bbbb-4eee-8eee-eeeeeeeeeeee"
STUDENT = "000000099901"


def sql(statement):
    result = subprocess.run(PSQL, input=statement, text=True,
                            capture_output=True, timeout=30)
    if result.returncode:
        raise AssertionError(result.stderr)
    return result.stdout.strip()


def start_session(statement):
    process = subprocess.Popen(PSQL, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, text=True)
    process.stdin.write(statement)
    process.stdin.close()
    process.stdin = None
    return process


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
values ('{LEADER}','00000000-0000-0000-0000-000000000000','authenticated',
'authenticated','race-demo@hnu.edu.ph',now(),now(),now());
insert into public.students(student_id,full_name,program_code,year_level)
values ('{STUDENT}','Synthetic Race Student','BSIT',1);
insert into public.organizations(id,slug,name) values
('{ORG}','race-demo','Race Demo Organization');
insert into public.organization_memberships(organization_id,user_id,role,granted_by)
values ('{ORG}','{LEADER}','leader','{LEADER}');
insert into public.events(id,organization_id,created_by,title,starts_at,ends_at)
values ('{EVENT}','{ORG}','{LEADER}','Race demo event',
'2040-01-01 00:00+00','2040-01-02 00:00+00');
set local role authenticated;
select set_config('request.jwt.claim.sub','{LEADER}',true);
insert into public.event_checkpoints(event_id,label,direction,opens_at,closes_at)
values ('{EVENT}','Initial In','IN','2040-01-01 08:00+08','2040-01-01 09:00+08');
commit;
""")

freeze = start_session(f"""
begin;
set application_name='hnu-dash-freeze-race';
select id from public.events where id='{EVENT}' for update;
select pg_sleep(12);
set local role authenticated;
select set_config('request.jwt.claim.sub','{LEADER}',true);
select public.freeze_event_roster('{EVENT}');
commit;
""")
if not until("""select exists(select 1 from pg_stat_activity
    where application_name='hnu-dash-freeze-race' and wait_event='PgSleep');"""):
    raise AssertionError("Freezer never reached its parent-row-lock barrier")

editor = start_session(f"""
begin;
set application_name='hnu-dash-checkpoint-race';
set local role authenticated;
select set_config('request.jwt.claim.sub','{LEADER}',true);
insert into public.event_checkpoints(event_id,label,direction,opens_at,closes_at)
values ('{EVENT}','Concurrent Out','OUT',
'2040-01-01 09:00+08','2040-01-01 10:00+08');
commit;
""")
blocked = until("""select exists(select 1 from pg_stat_activity a
    where a.application_name='hnu-dash-checkpoint-race'
      and cardinality(pg_blocking_pids(a.pid)) > 0);""")
freeze_out, freeze_err = freeze.communicate(timeout=30)
edit_out, edit_err = editor.communicate(timeout=30)
if not blocked:
    raise AssertionError("Checkpoint write was never observed blocked by parent lock")
if freeze.returncode != 0:
    raise AssertionError(f"Freeze failed: {freeze_err} {freeze_out}")
if editor.returncode == 0 or "Checkpoint changes require an editable draft" not in edit_err:
    raise AssertionError(f"Concurrent edit should have been rejected: {edit_err} {edit_out}")

frozen, checkpoints, roster = sql(f"""select
  (roster_frozen_at is not null)::int,
  (select count(*) from public.event_checkpoints where event_id='{EVENT}'),
  (select count(*) from public.event_roster where event_id='{EVENT}')
from public.events where id='{EVENT}';""").split("|")
if (frozen, checkpoints, roster) != ("1", "1", "1"):
    raise AssertionError(f"Unexpected committed state: {frozen}, {checkpoints}, {roster}")

print("PASS: checkpoint writer blocked on parent row; freeze committed; later edit rejected")
