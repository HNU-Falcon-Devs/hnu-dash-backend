# HNU DASH Backend

This repository owns the authoritative Supabase/PostgreSQL backend for HNU DASH: project configuration, database migrations, constraints and functions, Row Level Security policies, and backend validation. The [web repository](https://github.com/HNU-Falcon-Devs/hnu-dash-web) owns the Next.js interface and client integration. Backend migrations belong here only.

## Shared integration contract

The proposed [Web/Mobile integration contract](docs/contracts/integration-v0.md) defines shared logical operations, authorization, sync receipts, and open decisions. **Draft for orchestrator review; not approved or implemented.** Client repositories should link to this source rather than copy it.

## Local setup

Use Node.js 24, npm, Python 3.11 or newer (for validation), and a running Docker compatible container engine. No hosted Supabase project or production credentials are needed.

```bash
npm ci
npm run supabase -- start
npm run supabase -- status
```

The CLI prints local API and database connection details after start. Stop the stack with `npm run supabase -- stop`. Local ports are the Supabase CLI defaults; adjust `supabase/config.toml` if they conflict with another project. Keep secrets and machine-specific `.env` files out of Git.

## Migrations and validation

Once a schema change is agreed, run `npm run supabase -- migration new <name>`, edit the generated SQL in `supabase/migrations`, and review its constraints, grants, and policies. With the local stack running, use `npm run supabase -- db reset` to apply all migrations from scratch and `npm run supabase -- db lint` to check the database. Review the SQL and reset results before a PR. Do not copy migrations into the web repository.

Run `npm run validate` for the current credential-free configuration and migration layout check. CI also starts the local stack, resets the database, and lints it on PRs and `main`. There is no domain SQL to test yet.

## Current status

Only the local Supabase foundation exists. Authentication, HNU MIS integration, profiles, organizations, permissions, events, scanners, attendance, reconciliation, reporting, fines, clearance, and mobile functionality are deferred. Server-side authorization and attendance reconciliation must be designed with their first domain features. Offline mobile records will remain provisional until backend validation; HNU DASH must never store or proxy MIS credentials.
