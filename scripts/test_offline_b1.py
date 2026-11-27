#!/usr/bin/env python3
"""B1 populated upgrade and real two-session races; disposable CI only."""
import json
import os
from pathlib import Path
import subprocess
import sys
import time

if os.getenv("HNU_DASH_ISOLATED_TEST_DB") != "1":
    raise SystemExit("Refusing non-isolated database access")
names = subprocess.run(["docker", "ps", "--format", "{{.Names}}"], check=True,
                       text=True, capture_output=True).stdout.splitlines()
if names.count("supabase_db_hnu-dash-backend") != 1:
    raise SystemExit("Expected exactly one isolated HNU DASH database")
PSQL = ["docker", "exec", "-i", "supabase_db_hnu-dash-backend", "psql",
        "-X", "-qAt", "-v", "ON_ERROR_STOP=1", "-U", "postgres", "-d", "postgres"]


def ident(kind, n):
    return f"f8{kind:02x}0000-0000-4000-8000-{n:012d}"


ADMIN, HEAD, STAFF = [ident(0x20, i) for i in range(1, 4)]
ORG = ident(0x10, 1)
STUDENT = "B1-UPGRADE-SYNTHETIC"
E = lambda i: ident(0x30, i)
C = lambda i: ident(0x40, i)
A = lambda i: ident(0x50, i)
R = lambda i: ident(0x60, i)


def sql(statement):
    r = subprocess.run(PSQL, input=statement, text=True, capture_output=True, timeout=60)
    if r.returncode:
        raise AssertionError(r.stderr)
    return r.stdout.strip()


def json_response(out):
    rows = [json.loads(line) for line in out.splitlines() if line.startswith("{")]
    if len(rows) != 1:
        raise AssertionError(f"Expected one JSON response, got {out!r}")
    return rows[0]


def as_actor(actor, statement):
    return f"""begin;
set local role authenticated;
select set_config('request.jwt.claim.sub','{actor}',true);
{statement}
commit;
"""


def rpc(actor, expr):
    return json_response(sql(as_actor(actor, f"select {expr};")))


def actors():
    sql(f"""
insert into auth.users(id,instance_id,aud,role,email,email_confirmed_at,created_at,updated_at)
values
 ('{ADMIN}','00000000-0000-0000-0000-000000000000','authenticated','authenticated','b1-ci-admin@hnu.edu.ph',now(),now(),now()),
 ('{HEAD}','00000000-0000-0000-0000-000000000000','authenticated','authenticated','b1-ci-head@hnu.edu.ph',now(),now(),now()),
 ('{STAFF}','00000000-0000-0000-0000-000000000000','authenticated','authenticated','b1-ci-staff@hnu.edu.ph',now(),now(),now());
insert into public.platform_admins(user_id) values ('{ADMIN}');
insert into public.organizations(id,slug,name) values ('{ORG}','b1-ci-org','B1 CI synthetic');
insert into public.organization_memberships(organization_id,user_id,role,active,granted_by) values
 ('{ORG}','{HEAD}','leader',true,'{ADMIN}'),
 ('{ORG}','{STAFF}','staff',true,'{ADMIN}');
insert into public.students(student_id,full_name,program_code,year_level)
values ('{STUDENT}','B1 CI synthetic student','BSIT',1);
""")


def fixture(i, version2):
    if version2:
        sql(f"""
select set_config('request.jwt.claim.sub','{ADMIN}',false);
insert into public.events(id,organization_id,created_by,title,starts_at,ends_at,policy_version)
values ('{E(i)}','{ORG}','{ADMIN}','B1 race {i}','2090-01-01T09:00:00Z','2090-01-01T14:00:00Z',2);
insert into public.event_checkpoints(id,event_id,label,direction,opens_at,closes_at)
values ('{C(i)}','{E(i)}','Checkpoint','IN','2090-01-01T10:00:00Z','2090-01-01T11:00:00Z');
insert into public.event_roster(event_id,student_id,student_name,program_code,year_level,frozen_at)
values ('{E(i)}','{STUDENT}','B1 CI synthetic student','BSIT',1,now());
update public.events set roster_frozen_at=now() where id='{E(i)}';
insert into public.event_staff(id,event_id,staff_user_id,assigned_by)
values ('{A(i)}','{E(i)}','{STAFF}','{ADMIN}');
{f"update public.events set state='OPEN',opened_at=clock_timestamp() where id='{E(i)}';" if i != 1 else ""}
""")
    else:
        # Populated baseline fixture uses the original columns and RPCs.
        past = i == 103
        start = "now()-interval '4 hours'"
        end = "now()-interval '1 hour'" if past else "now()+interval '3 hours'"
        cp_end = "now()-interval '2 hours'" if past else "now()+interval '2 hours'"
        sql(f"""
select set_config('request.jwt.claim.sub','{ADMIN}',false);
insert into public.events(id,organization_id,created_by,title,starts_at,ends_at)
values ('{E(i)}','{ORG}','{ADMIN}','B1 legacy {i}',{start},{end});
insert into public.event_checkpoints(id,event_id,label,direction,opens_at,closes_at)
values ('{C(i)}','{E(i)}','Checkpoint','IN',now()-interval '3 hours',{cp_end});
{f"select public.enable_event_offline('{E(i)}');" if i != 103 else ""}
{f"select public.freeze_event_roster('{E(i)}'); select public.assign_event_staff('{E(i)}','{STAFF}'); select * from public.open_event('{E(i)}');" if i != 101 else ""}
""")


def snapshot():
    # JSON subtraction is safe before and after the additive event columns.
    queries = [
        ("events", "public.events", "organization_id", "id", "to_jsonb(x)-'policy_version'-'sync_deadline'"),
        ("checkpoints", "public.event_checkpoints", "event_id", "id", "to_jsonb(x)"),
        ("roster", "public.event_roster", "event_id", "event_id,student_id", "to_jsonb(x)"),
        ("assignments", "public.event_staff", "event_id", "id", "to_jsonb(x)"),
        ("scans", "public.attendance_scans", "event_id", "scan_id", "to_jsonb(x)-'successor_capture_id'"),
        ("preparations", "public.offline_preparations", "event_id", "id", "to_jsonb(x)"),
        ("claims", "public.offline_capture_claims", "event_id", "capture_id", "to_jsonb(x)"),
        ("records", "public.attendance_records", "event_id", "event_id,student_id", "to_jsonb(x)"),
    ]
    fields = []
    for name, table, key, order, expr in queries:
        where = f"organization_id='{ORG}'" if key == "organization_id" else (
            f"event_id in (select id from public.events where organization_id='{ORG}')")
        fields.append(f"'{name}',(select coalesce(jsonb_agg({expr} order by {order}),'[]'::jsonb) from {table} x where {where})")
    return json_response(sql("select jsonb_build_object(" + ",".join(fields) + ");"))


def same_receipt(original, replay):
    assert not original["replayed"] and replay["replayed"], (original, replay)
    assert {k: v for k, v in original.items() if k != "replayed"} == {
        k: v for k, v in replay.items() if k != "replayed"}, (original, replay)


def legacy_prepare():
    return f"public.prepare_offline_capture('{E(102)}','{R(101)}')"


def legacy_claim(prep):
    return (f"public.submit_offline_capture('{prep['preparation_id']}','{R(102)}',"
            f"'{C(102)}','{STUDENT}','{prep['issued_at']}')")


def legacy_scan():
    return f"public.ingest_attendance_scan('{R(103)}','{E(102)}','{C(102)}','{STUDENT}')"


def upgrade(mode):
    # Runner-local synthetic snapshot crosses CI steps, not a deployed DB.
    path = Path(os.environ["RUNNER_TEMP"]) / "hnu-dash-b1-legacy-snapshot.json"
    if mode == "upgrade-seed":
        actors()
        for i in (101, 102, 103):
            fixture(i, False)
        prep = rpc(STAFF, legacy_prepare())
        claim = rpc(STAFF, legacy_claim(prep))
        scan = rpc(STAFF, legacy_scan())
        assert scan["outcome"] == "accepted"
        # Historical immutable receipt with planned time already elapsed;
        # only fixture construction, not a new ingestion capability.
        sql(f"""
insert into public.attendance_scans(scan_id,event_id,checkpoint_id,student_id,submitted_by,received_at,outcome)
select '{R(104)}','{E(103)}','{C(103)}','{STUDENT}','{STAFF}',opens_at,'accepted'
from public.event_checkpoints where id='{C(103)}';
""")
        rpc(HEAD, f"public.close_event('{E(103)}')")
        final = rpc(HEAD, f"public.finalize_event('{E(103)}')")
        data = snapshot()
        assert len(data["events"]) == 3 and len(data["preparations"]) == 1
        assert len(data["claims"]) == 1 and len(data["scans"]) == 2
        assert any(x["status"] == "PRESENT" for x in data["records"])
        path.write_text(json.dumps({"snapshot": data, "prep": prep, "claim": claim,
                                    "scan": scan, "final": final}))
        print("B1 populated v1 snapshot seeded (DRAFT, OPEN, FINALIZED, pending evidence)")
    else:
        before = json.loads(path.read_text())
        assert snapshot() == before["snapshot"], "Legacy row identity or data changed"
        assert sql(f"select count(*) from public.events where organization_id='{ORG}' and policy_version=1 and sync_deadline is null;") == "3"
        assert sql("select count(*) from offline_b1_private.preparations;") == "0"
        # B2 adds nullable provenance; no legacy row may acquire it.
        if sql("select exists(select 1 from information_schema.columns where table_schema='public' and table_name='attendance_scans' and column_name='successor_capture_id');") == "t":
            assert sql("select count(*) from public.attendance_scans where successor_capture_id is not null;") == "0"
        same_receipt(before["prep"], rpc(STAFF, legacy_prepare()))
        same_receipt(before["claim"], rpc(STAFF, legacy_claim(before["prep"])))
        same_receipt(before["scan"], rpc(STAFF, legacy_scan()))
        same_receipt(before["final"], rpc(HEAD, f"public.finalize_event('{E(103)}')"))
        assert snapshot() == before["snapshot"], "Legacy replay mutated persisted evidence"
        path.unlink()
        print("B1 populated v1 upgrade and four exact legacy replays PASS")


def prepare(i, request):
    return f"public.prepare_offline_capture_v2('{E(i)}','{A(i)}','{R(request)}')"


def close(i, request, reason="early synthetic closure"):
    mapping = json.dumps([{"checkpoint_id": C(i), "opens_at": "2090-01-01T10:00:00Z",
                           "closes_at": "2090-01-01T11:00:00Z"}])
    return f"public.close_event_v2('{E(i)}','{R(request)}','{mapping}'::jsonb,false,'{reason}')"


def extension(i, request, hours):
    # Use the immutable receipt's observed closure instant, supplied by caller.
    return f"public.extend_event_sync_deadline_v2('{E(i)}','{R(request)}','{CLOSED}'::timestamptz+interval '{hours} hours','synthetic extension')"


def session(label, actor, expr, hold=False):
    statement = f"""begin;
set application_name='{label}';
set local role authenticated;
select set_config('request.jwt.claim.sub','{actor}',true);
select {expr};
{"select pg_sleep(9);" if hold else ""}
commit;
"""
    p = subprocess.Popen(PSQL, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                         stderr=subprocess.PIPE, text=True)
    p.stdin.write(statement)
    p.stdin.close()
    p.stdin = None
    return p


def barrier(label, waiting):
    condition = "cardinality(pg_blocking_pids(pid))>0" if waiting else "wait_event='PgSleep'"
    end = time.monotonic() + 8
    while time.monotonic() < end:
        if sql(f"select exists(select 1 from pg_stat_activity where application_name='{label}' and {condition});") == "t":
            return
        time.sleep(.1)
    raise AssertionError(f"Missing observed {'lock' if waiting else 'hold'} barrier: {label}")


def result(p, error=None):
    out, err = p.communicate(timeout=60)
    if error:
        assert p.returncode and error in err, (out, err)
        return None
    assert not p.returncode, err
    return json_response(out)


def race(label, actor1, expr1, actor2, expr2, error=None):
    p1 = session(label+"-first", actor1, expr1, True)
    p2 = None
    try:
        barrier(label+"-first", False)
        p2 = session(label+"-second", actor2, expr2)
        barrier(label+"-second", True)
        pair = result(p1), result(p2, error)
        print(f"{label}: observed lock contention and expected outcome PASS", flush=True)
        return pair
    finally:
        for p in (p1, p2):
            if p is not None and p.poll() is None:
                p.terminate()
                p.communicate(timeout=15)


def races():
    global CLOSED
    actors()
    for i in range(1, 7):
        fixture(i, True)
    a, b = race("b1-preparation-replay", STAFF, prepare(1, 1), STAFF, prepare(1, 1))
    same_receipt(a, b)
    assert a["prepared_event_state"] == "DRAFT"
    race("b1-revocation-first", HEAD,
         f"jsonb_build_object('assignment_id',public.revoke_event_staff('{A(2)}'))",
         STAFF, prepare(2, 2), "Offline evidence not permitted")
    assert sql(f"select count(*) from offline_b1_private.preparations where event_id='{E(2)}';") == "0"
    race("b1-closure-first", HEAD, close(3, 3), STAFF, prepare(3, 3),
         "New preparation requires frozen DRAFT or OPEN")
    assert sql(f"select count(*) from offline_b1_private.preparations where event_id='{E(3)}';") == "0"
    a, b = race("b1-preparation-first", STAFF, prepare(4, 4), HEAD, close(4, 4))
    assert a["prepared_event_state"] == "OPEN" and b["event_state"] == "SYNCING"
    assert sql(f"select count(*) from offline_b1_private.preparations where event_id='{E(4)}';") == "1"
    a, b = race("b1-closure-replay", HEAD, close(5, 5), ADMIN, close(5, 5))
    same_receipt(a, b)
    CLOSED = a["closed_at"]
    race("b1-closure-conflict", HEAD, close(6, 6), ADMIN, close(6, 7),
         "Closure request conflicts")
    assert sql(f"select count(*) from offline_b1_private.closures where event_id='{E(6)}';") == "1"
    a, _ = race("b1-extension-conflict", HEAD, extension(5, 8, 48), HEAD, extension(5, 9, 36),
                "Deadline must extend within 168 elapsed hours")
    assert sql(f"select sync_deadline=closed_at+interval '48 hours' and state='SYNCING' from public.events where id='{E(5)}';") == "t"
    assert sql(f"select count(*) from offline_b1_private.deadline_extensions where event_id='{E(5)}';") == "1"
    same_receipt(a, rpc(HEAD, extension(5, 8, 48)))
    print("B1 seven concurrency scenarios PASS; immutable fixtures discarded with CI stack")


if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) == 2 else ""
    if mode in ("upgrade-seed", "upgrade-check"):
        upgrade(mode)
    elif mode == "races":
        races()
    else:
        raise SystemExit("Expected upgrade-seed, upgrade-check or races")
