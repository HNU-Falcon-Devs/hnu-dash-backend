# HNU DASH Backend

HNU DASH is a planned event attendance system for Holy Name University, initially aimed at approximately 600 BSIT students. The Backend is the behind-the-scenes part that will keep event, staff, and attendance records consistent and trustworthy.

## How it fits into HNU DASH

- [Web](https://github.com/HNU-Falcon-Devs/hnu-dash-web) will let authorized organizers manage events and review attendance, and let students view their own records.
- [Mobile](https://github.com/HNU-Falcon-Devs/hnu-dash-mobile) will help assigned staff collect ID scans at events, even offline.
- **Backend (this repository)** will check identities and permissions, receive scans, maintain official records, and provide results to both apps.

Only the Backend will decide official attendance. A saved or uploaded scan by itself does not mean a student has been marked present.

## Current status

**Milestone 1 development foundation in progress; not deployed.** The new schema supports admin-controlled students and identity linkage, scoped draft events, configurable checkpoints, CSV roster import, and frozen roster snapshots. Scanning, synchronization, event finalization, official attendance results, and production access are not implemented.

A shared integration plan is proposed in [Backend PR #2](https://github.com/HNU-Falcon-Devs/hnu-dash-backend/pull/2). It remains **unapproved and is not a working API**. The authorized Milestone 1 operations are documented separately in [Milestone 1 Web integration](docs/integration/milestone-1-web.md); they use Supabase Auth for the MVP.

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
