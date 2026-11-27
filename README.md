# HNU DASH Backend

HNU DASH is a planned event attendance system for Holy Name University, initially aimed at approximately 600 BSIT students. The Backend is the behind-the-scenes part that will keep event, staff, and attendance records consistent and trustworthy.

## How it fits into HNU DASH

- [Web](https://github.com/HNU-Falcon-Devs/hnu-dash-web) will let authorized organizers manage events and review attendance, and let students view their own records.
- [Mobile](https://github.com/HNU-Falcon-Devs/hnu-dash-mobile) will help assigned staff collect ID scans at events, even offline.
- **Backend (this repository)** will check identities and permissions, receive scans, maintain official records, and provide results to both apps.

Only the Backend will decide official attendance. A saved or uploaded scan by itself does not mean a student has been marked present.

## Current status

**Synthetic-only implementation through M4.2 is merged; no production use is authorized.** Backend owns verified HNU identities, frozen rosters, Staff assignment, immutable online receipts, checkpoint coverage and prototype finalization. M4.1 adds bounded offline preparations and immutable submitted claims; M4.2 adds explicit Staff completion, manager seal, loss accounting, individual review and reconciliation-gated finalization. See [M3.2A](docs/integration/milestone-3-part-2a-attendance-finalization.md), [M4.1](docs/integration/milestone-4-part-1-offline-evidence.md) and [M4.2](docs/integration/milestone-4-part-2-offline-reconciliation.md).

As of 2026-11-26, [Backend main CI](https://github.com/HNU-Falcon-Devs/hnu-dash-backend/actions/runs/45433090568) passed 649 database assertions and concurrency suites. Mobile M4.3A/B and Web M4.4 are merged with separate passing CI. Prior bounded online device ([Mobile #7](https://github.com/HNU-Falcon-Devs/hnu-dash-mobile/issues/7#issuecomment-7110814051)) and browser/RPC ([Web #24](https://github.com/HNU-Falcon-Devs/hnu-dash-web/issues/24#issuecomment-7135489451)) acceptance remains historical. [M4.5A acceptance](https://github.com/HNU-Falcon-Devs/hnu-dash-backend/issues/19#issuecomment-7180150336) establishes bounded synthetic Web–Staff RPC–PostgreSQL integration using separate live pre-cutoff and seeded historical post-cutoff fixtures. Physical offline QA remains outstanding ([Mobile #13](https://github.com/HNU-Falcon-Devs/hnu-dash-mobile/issues/13)). The last reported hosted development migration verification covered M2.1/M2.3 only; do not infer M3/M4 hosted deployment from source or CI.

Historical [Backend PR #2](https://github.com/HNU-Falcon-Devs/hnu-dash-backend/pull/2) was closed without approval and superseded. Implemented operations are documented in [Milestone 1 Web integration](docs/integration/milestone-1-web.md), [Milestone 2, Part 1](docs/integration/milestone-2-part-1.md), and [Milestone 2.3 online scan ingestion](docs/integration/milestone-2-part-3-scan-ingestion.md); the MVP uses Supabase Auth. See the [M2.6 integration QA status](docs/qa/m2-6-integration-status.md) for verified scope, limits, and next acceptance tests.

The additive [offline-first B1 foundation](docs/integration/offline-first-b1-foundation.md) defines fixture-only policy v2 lifecycle/preparation. The [offline-first B2 reconciliation contract](docs/integration/offline-first-b2-reconciliation.md) adds the fixture-only evidence-to-finalization Backend candidate. Neither enables ordinary successor events, changes v1 evidence, or authorizes consumer activation or real attendance. B2 requires independent review and coordinated consumer acceptance; CI evidence is recorded separately.

## Pilot delivery direction

The working target is an **approximately 600-student BSIT pilot, tentatively February 2027**, subject to HNU approval. This is a delivery direction, not approval to deploy or process real student data.

- **Validate the implemented vertical slice:** M1–M4.4 synthetic functionality is implemented across the three repositories. Retain accepted M4.5A browser/RPC/database evidence and proceed to separately authorized physical Android QA ([Mobile #13](https://github.com/HNU-Falcon-Devs/hnu-dash-mobile/issues/13)). Preserve historical acceptance boundaries and use synthetic data; **do not build a disposable Web scanner**.
- **Harden for the pilot:** Validate the existing durable offline queue, idempotent sync, immutable reconciliation and authorization in actual integrations. Measure manual review workload and realistic volume; resolve physical-device security, privacy, recovery and institutional requirements before real data. Defer HNU MIS integration, fines, clearance, additional dashboards and separate middleware unless justified.
- **Keep infrastructure minimal:** Retain the three existing repositories. Plan for Web on Vercel, authoritative Backend on Supabase/PostgreSQL, and Flutter/SQLite on Android. Web and Mobile consume Backend independently. Do not add an Express/Render layer without a demonstrated need. Use **Supabase Auth** for the MVP with verified `@hnu.edu.ph` email accounts; defer HNU MIS integration.
- **Resolve only blocking decisions before each slice:** M2.1/M2.3/M3.2A/M4.1/M4.2 are implemented contracts; historical PR #2 is superseded. Obtain an [approved physical HNU ID QR specification](https://github.com/HNU-Falcon-Devs/hnu-dash-backend/issues/9), institutional attendance rules, privacy and recovery policy before dependent real-data functionality. Existing offline trust rules authorize synthetic development only.
- **Release gate:** Before using real student records, verify backend authorization/RLS and negative tests, mobile data isolation and protection, replay/retry behavior, realistic pilot-volume testing, recovery/backups, and the required privacy/organizational approvals. Existing PR CI is only the foundation: introduce isolated staging, controlled production releases/rollback, and backward-compatible migrations before live use. Routine application updates should avoid interrupting the whole system, but **unconditional zero downtime is not guaranteed**.

## Developer setup

Use Node.js 24, npm, Python 3.11 or newer (for validation), and a running Docker-compatible container engine. No hosted Supabase project or production credentials are needed.

```bash
npm ci
npm run supabase -- start
npm run supabase -- status
```

The CLI prints local API and database connection details after start. Stop the stack with `npm run supabase -- stop`. Local ports are the Supabase CLI defaults; adjust `supabase/config.toml` if they conflict with another project. Keep secrets and machine-specific `.env` files out of Git.

## Database changes and validation

Once a schema change is agreed, run `npm run supabase -- migration new <name>`, edit the generated SQL in `supabase/migrations`, and review its constraints, grants, and policies. With the local stack running, use `npm run supabase -- db reset` to apply migrations from scratch and `npm run supabase -- db lint` to check the database. Keep backend migrations in this repository only.

Run `npm run validate` for credential-free configuration and migration-layout checks. CI also starts the local stack, resets the database, lints it, and runs `npm run supabase -- test db` (pgTAP) on PRs and `main`. Roster converter smoke test: `python3 scripts/csv_to_import_json.py test/fixtures/synthetic_roster.csv`.

Do not use real student data in foundation testing or store or proxy HNU MIS passwords.
