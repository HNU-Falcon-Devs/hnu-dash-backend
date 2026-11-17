# M2.6 — Integration QA status

**Snapshot:** 2026-11-17 · **Overall:** OPEN / not pilot-ready · **Part B:** conditionally accepted for the tested online Web–Backend scope

This is one cross-repository status summary, not a new implementation contract. It records the independent Codex QA reports reviewed by the WhiteTree maintainer. Raw local `/tmp/hnu-m26-qa` evidence was reported by the executor but is not retained in this repository; do not treat those paths as durable artifacts or infer tests that were not run.

## Source baselines

| Component | Reviewed `main` commit |
| --- | --- |
| [Web](https://github.com/HNU-Falcon-Devs/hnu-dash-web) | `022acbccbb1f088862f423213ef66140253cf3f0` |
| [Backend](https://github.com/HNU-Falcon-Devs/hnu-dash-backend) | `0b2119cdf3dcbb666603d42a55d4570fb23876f1` |
| [Mobile](https://github.com/HNU-Falcon-Devs/hnu-dash-mobile) | `2dc333bbc7ca05204414e79b76dcc2cf3923f4f1` |

## Completed verification

- **Part A — isolated Backend:** Fresh local Supabase applied all three migrations; database lint found no schema errors; 217/217 pgTAP assertions, six synthetic CSV tests, and checkpoint/freeze, competing OPEN, and scan/revocation concurrency checks passed.
- **Part B — Web–Backend:** Synthetic local Supabase Auth sessions and real Web Server Actions created an organization, draft event and checkpoints, froze a roster, assigned Staff, and activated the event. Membership creation, role changes, deactivation/reactivation, and import confirmation were subsequently exercised against an isolated Backend. Backend checks verified scoped visibility, unauthorized denials, scan `accepted`/`rejected`/`duplicate`, same-UUID replay, conflicting UUID denial, and effective revocation. Repeated OPEN returned documented SQLSTATE `55000` and Web displayed an error without falsely claiming success.
- **CSV component coverage:** 13/13 focused parser/preview tests passed; Web import confirmation persisted one synthetic record, while unauthorized, malformed, and unconfirmed submissions did not.
- **Mobile CI (not independent device QA):** [GitHub run #42571447633](https://github.com/HNU-Falcon-Devs/hnu-dash-mobile/actions/runs/42571447633) passed Flutter tests, Android debug APK build, and SQLCipher native-library verification.
- **Hosted development schema (read-only):** `hnu-dash-dev` was observed to contain the event/Staff/scan migrations and the expected scan RPC. This does **not** attest to live authorization or justify hosted writes.

These tests use **synthetic** students and isolated Auth accounts. Accepted scan receipts are immutable **capture evidence**, not official/finalized attendance.

## Outstanding acceptance

| Boundary | Status / owner |
| --- | --- |
| Actual Flutter app → isolated Backend on Android; camera, encrypted store, retries, account switching, revocation | **Not independently verified** — [Mobile #7](https://github.com/HNU-Falcon-Devs/hnu-dash-mobile/issues/7), next |
| Actual browser CSV file-picker → preview → confirmation and error display | **Blocked by browser access**, despite passing parser and Server Action tests — [Web #16](https://github.com/HNU-Falcon-Devs/hnu-dash-web/issues/16), pre-pilot |
| Real HNU Google OAuth sign-in/callback, restoration and denial | **Not tested**; Part B used local password sessions — [Web #17](https://github.com/HNU-Falcon-Devs/hnu-dash-web/issues/17) |
| Physical HNU ID QR payload, canonical-ID mapping and approval | **Unspecified**; do not infer plain-text physical QR format — [Backend #9](https://github.com/HNU-Falcon-Devs/hnu-dash-backend/issues/9) |
| Offline synchronization, reconciliation, official attendance results, operational privacy/recovery and institutional clearance | **Not implemented / not approved**; separate future milestones, not M2.6 Part B regressions |

## Maintainer decision

**Accept M2.6 Part B conditionally** for its tested authenticated Web–Backend online workflow. Continue **M2.6 Part C** with Mobile independent integration QA; do not re-run previously passed suites without changed code or a specific risk. Keep overall M2.6 and pilot readiness open. A pass in CI or a synthetic Backend RPC test must never be described as physical-device end-to-end validation.
