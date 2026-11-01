# Backend maintainer guidance

## Ownership and approval

- Supabase/PostgreSQL is authoritative. This repository owns schemas, migrations, RLS, authorization, synchronization, reconciliation, and the canonical shared integration contract. Web and Mobile are separate consumers.
- Obtain WhiteTree Orchestrator approval for cross-project architecture or scope changes. Implement only approved, scoped assignments after inspecting existing code and requirements.
- The backend repository owns the canonical shared integration contract. Do not implement proposed contract behavior or unresolved decisions without WhiteTree Orchestrator approval, and do not create competing specifications.

## Security boundaries

- Enforce privileges and organization scope server-side. Never expose service-role credentials to clients or commit secrets or real student data.
- Preserve raw scan history and auditability. The authentication provider and HNU MIS integration remain unapproved.

## Workflow and handoff

- Work on dedicated feature branches. Use Conventional Commits at meaningful boundaries; respect the 50-commit ceiling without manufacturing commits. Preserve unrelated user work.
- Open PRs for review. Never merge or push directly to protected `main`; final merge authorization belongs to the human repository owner.
- Run relevant repository checks and report actual results. Never weaken validation to obtain green CI. Preserve the exact required CI check name `Repository validation`.
- Review the final diff before pushing. Report the branch, commits, PR, validation results, and unresolved issues at handoff.
