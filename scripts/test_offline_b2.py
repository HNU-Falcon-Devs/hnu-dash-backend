#!/usr/bin/env python3
"""B2 upgrade and lock-contention checks: disposable GitHub CI only."""
import json
import os
from datetime import datetime, timedelta
from pathlib import Path
import sys

# Reuse the proven isolation gate, psql process/barrier and receipt helpers.
import test_offline_b1 as b1

sql = b1.sql
rpc = b1.rpc
same_receipt = b1.same_receipt


def q(value):
    return "'" + str(value).replace("'", "''") + "'"


def b1_snapshot():
    fields = {
        "events": "select to_jsonb(x) from public.events x order by id",
        "closures": "select to_jsonb(x) from offline_b1_private.closures x order by event_id",
        "windows": "select to_jsonb(x) from offline_b1_private.effective_windows x order by event_id,checkpoint_id",
        "extensions": "select to_jsonb(x) from offline_b1_private.deadline_extensions x order by request_id",
        "preparations": "select to_jsonb(x) from offline_b1_private.preparations x order by id",
    }
    return {name: [json.loads(line) for line in sql(statement).splitlines()]
            for name, statement in fields.items()}


def upgrade(mode):
    path = Path(os.environ["RUNNER_TEMP"]) / "hnu-dash-b2-populated-snapshot.json"
    if mode == "upgrade-seed":
        b1.actors()
        for i in (101, 102, 103):
            b1.fixture(i, False)
        for i in (1, 2):
            b1.fixture(i, True)
        legacy_prep = rpc(b1.STAFF, b1.legacy_prepare())
        legacy_claim = rpc(b1.STAFF, b1.legacy_claim(legacy_prep))
        legacy_scan = rpc(b1.STAFF, b1.legacy_scan())
        sql(f"""
insert into public.attendance_scans(scan_id,event_id,checkpoint_id,student_id,submitted_by,received_at,outcome)
select '{b1.R(104)}','{b1.E(103)}','{b1.C(103)}','{b1.STUDENT}','{b1.STAFF}',opens_at,'accepted'
from public.event_checkpoints where id='{b1.C(103)}';
""")
        rpc(b1.HEAD, f"public.close_event('{b1.E(103)}')")
        legacy_final = rpc(b1.HEAD, f"public.finalize_event('{b1.E(103)}')")
        prep_draft = rpc(b1.STAFF, b1.prepare(1, 1))
        prep_open = rpc(b1.STAFF, b1.prepare(2, 2))
        closure = rpc(b1.HEAD, b1.close(2, 3))
        b1.CLOSED = closure["closed_at"]
        extension = rpc(b1.HEAD, b1.extension(2, 4, 48))
        assert legacy_scan["outcome"] == "accepted"
        assert prep_draft["prepared_event_state"] == "DRAFT"
        assert prep_open["prepared_event_state"] == "OPEN"
        path.write_text(json.dumps({
            "legacy": b1.snapshot(), "b1": b1_snapshot(),
            "legacy_prep": legacy_prep, "legacy_claim": legacy_claim,
            "legacy_scan": legacy_scan, "legacy_final": legacy_final,
            "prep_draft": prep_draft, "prep_open": prep_open,
            "closure": closure, "extension": extension,
        }))
        print("B2 populated v1 + B1 upgrade snapshot seeded")
    else:
        before = json.loads(path.read_text())
        assert b1.snapshot() == before["legacy"], "Legacy rows changed during B2 upgrade"
        assert b1_snapshot() == before["b1"], "B1 context or event rows changed during B2 upgrade"
        assert sql("select count(*) from public.attendance_scans where successor_capture_id is not null;") == "0"
        for table in ("claims_v2", "reviews_v2", "accounting_v2", "seals_v2",
                      "confirmations_v2", "finalizations_v2"):
            assert sql(f"select count(*) from offline_b1_private.{table};") == "0"
        same_receipt(before["legacy_prep"], rpc(b1.STAFF, b1.legacy_prepare()))
        same_receipt(before["legacy_claim"], rpc(b1.STAFF, b1.legacy_claim(before["legacy_prep"])))
        same_receipt(before["legacy_scan"], rpc(b1.STAFF, b1.legacy_scan()))
        same_receipt(before["legacy_final"], rpc(b1.HEAD, f"public.finalize_event('{b1.E(103)}')"))
        same_receipt(before["prep_draft"], rpc(b1.STAFF, b1.prepare(1, 1)))
        same_receipt(before["prep_open"], rpc(b1.STAFF, b1.prepare(2, 2)))
        same_receipt(before["closure"], rpc(b1.HEAD, b1.close(2, 3)))
        b1.CLOSED = before["closure"]["closed_at"]
        same_receipt(before["extension"], rpc(b1.HEAD, b1.extension(2, 4, 48)))
        assert b1.snapshot() == before["legacy"] and b1_snapshot() == before["b1"]
        path.unlink()
        print("B2 populated v1 + B1 upgrade and eight exact replays PASS", flush=True)


def ident(kind, n):
    return f"b3{kind:02x}0000-0000-4000-8000-{n:012d}"


ADMIN, HEAD, STAFF = (ident(0x20, i) for i in range(1, 4))
ORG = ident(0x10, 1)
STUDENT = "B2-CI-SYNTHETIC"
E = lambda i: ident(0x30, i)
C = lambda i: ident(0x40, i)
A = lambda i: ident(0x50, i)
P = lambda i: ident(0x60, i)
R = lambda i: ident(0x70, i)
REQ = lambda i: ident(0x80, i)
ANCHORS = {}


def actors():
    sql(f"""
insert into auth.users(id,instance_id,aud,role,email,email_confirmed_at,created_at,updated_at) values
 ('{ADMIN}','00000000-0000-0000-0000-000000000000','authenticated','authenticated','b2-ci-admin@hnu.edu.ph',now(),now(),now()),
 ('{HEAD}','00000000-0000-0000-0000-000000000000','authenticated','authenticated','b2-ci-head@hnu.edu.ph',now(),now(),now()),
 ('{STAFF}','00000000-0000-0000-0000-000000000000','authenticated','authenticated','b2-ci-staff@hnu.edu.ph',now(),now(),now());
insert into public.platform_admins(user_id) values ('{ADMIN}');
insert into public.organizations(id,slug,name) values ('{ORG}','b2-ci-org','B2 CI synthetic');
insert into public.organization_memberships(organization_id,user_id,role,active,granted_by) values
 ('{ORG}','{HEAD}','leader',true,'{ADMIN}'),
 ('{ORG}','{STAFF}','staff',true,'{ADMIN}');
insert into public.students(student_id,full_name,program_code,year_level)
values ('{STUDENT}','B2 CI synthetic student','BSIT',1);
""")


def fixture(i, expired=False):
    # Privileged historical B1 context is synthetic test setup, not an RPC
    # bypass. Fixed past instants make deadline/clock tests independent of
    # GitHub runner speed. No local or provider data.
    a = sql("select date_trunc('second',clock_timestamp())-interval "
            + ("'48 hours';" if expired else "'10 minutes';"))
    ANCHORS[i] = datetime.fromisoformat(a.replace(" ", "T"))
    t = q(ANCHORS[i].isoformat()) + "::timestamptz"

    def at(s):
        return f"({t}+interval '{s} seconds')"

    sql(f"""
select set_config('request.jwt.claim.sub','{ADMIN}',false);
insert into public.events(id,organization_id,created_by,title,starts_at,ends_at,policy_version)
values ('{E(i)}','{ORG}','{ADMIN}','B2 race {i}',{at(-60)},{at(180)},2);
insert into public.event_checkpoints(id,event_id,label,direction,opens_at,closes_at)
values ('{C(i)}','{E(i)}','Checkpoint','IN',{at(5)},{at(90)});
insert into public.event_roster(event_id,student_id,student_name,program_code,year_level,frozen_at)
values ('{E(i)}','{STUDENT}','B2 CI synthetic student','BSIT',1,{at(-30)});
update public.events set roster_frozen_at={at(-30)} where id='{E(i)}';
insert into public.event_staff(id,event_id,staff_user_id,assigned_at,assigned_by)
values ('{A(i)}','{E(i)}','{STAFF}',{at(-20)},'{ADMIN}');
insert into offline_b1_private.preparations(id,request_id,event_id,assignment_id,staff_user_id,issued_at,context)
values ('{P(i)}','{REQ(100+i)}','{E(i)}','{A(i)}','{STAFF}',{t},'{{}}');
update public.events set state='OPEN',opened_at={at(3)} where id='{E(i)}';
insert into offline_b1_private.closures(event_id,request_id,closed_at,closed_by,reason,overlap_acknowledged,normalized_windows,initial_deadline)
values ('{E(i)}','{REQ(200+i)}',{at(100)},'{HEAD}','synthetic race closure',false,
 jsonb_build_array(jsonb_build_object('checkpoint_id','{C(i)}','opens_at',{at(5)},'closes_at',{at(90)})),{at(100)}+interval '24 hours');
insert into offline_b1_private.effective_windows values ('{E(i)}','{C(i)}',{at(5)},{at(90)});
update public.events set state='SYNCING',closed_at={at(100)},closed_by='{HEAD}',sync_deadline={at(100)}+interval '24 hours' where id='{E(i)}';
""")


def upload(i, capture, exceptional=False):
    wall = (ANCHORS[i] + timedelta(seconds=20)).isoformat()
    evidence = dict(anchor_request_elapsed_ms=1000, anchor_response_elapsed_ms=1000,
                    qr_elapsed_ms=21000, confirmation_elapsed_ms=21000,
                    qr_wall_at=wall, confirmation_wall_at=wall,
                    anchor_boot_marker="boot_a", capture_boot_marker="boot_a",
                    anchor_provenance="missing" if exceptional else "original",
                    anomaly="missing" if exceptional else "none")
    return f"public.submit_offline_capture_v2('{P(i)}','{R(capture)}','{C(i)}','{STUDENT}',{q(json.dumps(evidence))}::jsonb)"


def complete(i, n):
    return f"public.complete_offline_preparation_v2('{P(i)}',{n})"


def seal(i):
    return f"public.seal_offline_uploads_v2('{E(i)}',true,false,'synthetic seal')"


def confirm(i):
    return f"public.confirm_offline_reconciliation_v2('{E(i)}',false,null)"


def finalize(i):
    return f"public.finalize_event_v2('{E(i)}')"


def count_claims(i):
    return int(sql(f"select count(*) from offline_b1_private.claims_v2 where event_id='{E(i)}';"))


def deactivation_race():
    # Onboarding deliberately uses NOWAIT and returns busy instead of
    # waiting on an upload's locked membership. Observe that real API
    # contract, then the opposite ordering with a held deactivation.
    revision = sql(f"select revision from public.organization_memberships where organization_id='{ORG}' and user_id='{STAFF}';")
    deactivate = f"public.update_org_member('{ORG}','{STAFF}','staff',false,{revision})"
    p1 = b1.session("b2-upload-membership-first", STAFF, upload(9, 9), True)
    try:
        b1.barrier("b2-upload-membership-first", False)
        assert rpc(ADMIN, deactivate)["status"] == "busy"
        assert b1.result(p1)["status"] == "submitted"
        assert count_claims(9) == 1
    finally:
        if p1.poll() is None:
            p1.terminate()
            p1.communicate(timeout=15)
    a, _ = b1.race("b2-deactivation-replay", ADMIN, deactivate, STAFF, upload(9, 9),
                   "Offline evidence not permitted")
    assert a["status"] == "updated" and count_claims(9) == 1
    print("b2-upload-membership: NOWAIT busy and deactivation-first denied replay PASS", flush=True)


def races():
    actors()
    for i in range(1, 10):
        fixture(i, expired=i in (3, 4))
    a, b = b1.race("b2-upload-completion", STAFF, upload(1, 1), STAFF, complete(1, 1))
    assert a["status"] == "submitted" and b["uploaded_count"] == 1 and count_claims(1) == 1
    b1.race("b2-completion-upload", STAFF, complete(2, 0), STAFF, upload(2, 2),
            "Successor upload window or preparation closed")
    assert count_claims(2) == 0
    b1.race("b2-seal-upload", HEAD, seal(3), STAFF, upload(3, 3),
            "Successor upload window or preparation closed")
    assert count_claims(3) == 0
    deadline = (ANCHORS[4] + timedelta(seconds=100, hours=72)).isoformat()
    ext = f"public.extend_event_sync_deadline_v2('{E(4)}','{REQ(300)}','{deadline}','synthetic extension')"
    a, b = b1.race("b2-extension-upload", HEAD, ext, STAFF, upload(4, 4))
    assert b["status"] == "submitted" and count_claims(4) == 1
    b1.race("b2-revocation-upload", HEAD,
            f"jsonb_build_object('assignment_id',public.revoke_event_staff('{A(5)}'))",
            STAFF, upload(5, 5), "Offline evidence not permitted")
    assert count_claims(5) == 0
    b1.race("b2-cross-event-uuid", STAFF, upload(6, 6), STAFF, upload(7, 6),
            "Successor capture identifier conflicts")
    assert count_claims(6) == 1 and count_claims(7) == 0
    rpc(STAFF, complete(7, 0))
    a, b = b1.race("b2-seal-confirm", HEAD, seal(7), ADMIN, confirm(7))
    assert a["early"] and b["confirmed_by"] == ADMIN
    rpc(STAFF, upload(8, 8, exceptional=True))
    rpc(STAFF, complete(8, 1))
    rpc(HEAD, seal(8))
    adjudicated = (ANCHORS[8] + timedelta(seconds=20)).isoformat()
    review = (f"public.review_offline_capture_v2('{E(8)}','{R(8)}','approve','synthetic review',"
              f"'synthetic_event_record','synthetic:race-8','{adjudicated}')")
    a, b = b1.race("b2-exception-confirm", HEAD, review, ADMIN, confirm(8))
    assert a["decision"] == "approve" and b["confirmed_by"] == ADMIN
    a, b = b1.race("b2-finalization-replay", HEAD, finalize(8), ADMIN, finalize(8))
    same_receipt(a, b)
    assert a["winner_count"] == 1 and a["record_count"] == 1
    assert sql(f"select count(*) from public.attendance_scans where event_id='{E(8)}';") == "1"
    assert sql(f"select count(*) from public.attendance_records where event_id='{E(8)}';") == "1"
    # Membership deactivation runs last so it cannot affect unrelated fixtures.
    deactivation_race()
    print("B2 ten lock-contention scenarios PASS; disposable synthetic database only", flush=True)


if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) == 2 else ""
    if mode in ("upgrade-seed", "upgrade-check"):
        upgrade(mode)
    elif mode == "races":
        races()
    else:
        raise SystemExit("Expected upgrade-seed, upgrade-check or races")
