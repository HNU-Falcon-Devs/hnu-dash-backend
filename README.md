# HNU DASH Backend

HNU DASH is a planned event attendance system for Holy Name University, initially aimed at approximately 600 BSIT students. The Backend is the behind-the-scenes part that will keep event, staff, and attendance records consistent and trustworthy.

## How it fits into HNU DASH

- [Web](https://github.com/HNU-Falcon-Devs/hnu-dash-web) will let authorized organizers manage events and review attendance, and let students view their own records.
- [Mobile](https://github.com/HNU-Falcon-Devs/hnu-dash-mobile) will help assigned staff collect ID scans at events, even offline.
- **Backend (this repository)** will check identities and permissions, receive scans, maintain official records, and provide results to both apps.

Only the Backend will decide official attendance. A saved or uploaded scan by itself does not mean a student has been marked present.

## Current status

**Development milestones implemented in repository; not deployed.** The schema supports verified HNU identities, event preparation and frozen rosters, Staff assignments, DRAFT → OPEN activation, and (Milestone 2.3) secure **online scan-ingestion receipts**. Mobile QR scanning, offline synchronization, reconciliation, official attendance results, and production access are not implemented.

Historical [Backend PR #2](https://github.com/HNU-Falcon-Devs/hnu-dash-backend/pull/2) was closed without approval and superseded. Implemented operations are documented in [Milestone 1 Web integration](docs/integration/milestone-1-web.md), [Milestone 2, Part 1](docs/integration/milestone-2-part-1.md), and [Milestone 2.3 online scan ingestion](docs/integration/milestone-2-part-3-scan-ingestion.md); the MVP uses Supabase Auth.

## Pilot delivery direction

The working target is an **approximately 600-student BSIT pilot, tentatively February 2027**, subject to HNU approval. This is a delivery direction, not approval to deploy or process real student data.

- **Build a usable vertical slice:** Implement authoritative event, roster, staff-assignment, attendance, and student-self-view operations in Backend with the necessary Web interfaces. Then connect the Flutter mobile QR scanner to the real backend. Use synthetic data and direct API tests during development; **do not build a disposable Web scanner**.
- **Harden for the pilot:** Add durable offline mobile capture, safe retries and idempotent sync, server reconciliation, auditability, role/organization enforcement, protected roster data, and end-to-end testing. Defer HNU MIS integration, fines, clearance, additional dashboards, and separate middleware unless a concrete pilot requirement warrants them.
- **Keep infrastructure minimal:** Retain the three existing repositories. Plan for Web on Vercel, authoritative Backend on Supabase/PostgreSQL, and Flutter/SQLite on Android. Web and Mobile consume Backend independently. Do not add an Express/Render layer without a demonstrated need. Use **Supabase Auth** for the MVP with verified `@hnu.edu.ph` email accounts; defer HNU MIS integration.
- **Resolve only blocking decisions before each slice:** The [proposed integration contract in PR #2](https://github.com/HNU-Falcon-Devs/hnu-dash-backend/pull/2) is not approved. Settle the relevant roster/QR source, identity and permissions, event/attendance rules, offline trust, privacy, and transport choices before implementing their dependent behavior; do not treat draft payloads as deployed APIs.
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
