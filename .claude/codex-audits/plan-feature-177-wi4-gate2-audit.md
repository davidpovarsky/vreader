# Feature 177 WI-4 — Gate 2 Plan Audit

Date: 2026-09-27  
Plan: `dev-docs/plans/20260927-feature-177-wi4-structured-context.md`  
Auditor: independent read-only subagent (`wi4_plan_audit`)

## Round 1

Verdict: `REVISE`

1. **High — MD Chapter bounds lacked a rendered-coordinate authority.**
   Existing generic MD TOC offsets can originate in raw Markdown while
   `MDReaderViewModel` owns rendered text and headings. Revision: provider
   registration now supplies rendered headings and snapshot chapter bounds;
   raw MD TOC offsets are forbidden for AI.
2. **High — inaccessible Whole-book units disappeared before coverage.**
   `AIReadiumDocumentProvider.chunks()` omits unavailable resources. Revision:
   add a provider-produced ordered source manifest retaining all unit identities,
   availability, and structured covered/dropped IDs.
3. **High — immediate Chat send could consume the previous async cache.**
   Revision: bounded sends await an exact-session/scope/generation refresh before
   citation/context snapshot, then re-check the send operation token.
4. **Medium — relocation invalidation used an unscoped global notification.**
   Revision: format hosts/registrations directly invalidate their exact session;
   provider snapshot identity is authoritative.
5. **Medium — TXT registration lacked an async teardown race contract.**
   Revision: generation-bearing state machine, no interim chapter-only attach,
   verify generation after loader await, and mutation-only registry events.
6. **Medium — DebugBridge Summarize remained on the flattened path.**
   Revision: one resolved-summary launcher shared by UI and DebugBridge.

Round 2 re-audit is required before RED tests.

## Round 2

Verdict: `REVISE`

1. **High — bounded legacy manifest could falsely report complete.**
   Revision: manifests now declare enumeration completeness; legacy's bounded
   current unit carries an unknown remainder and always yields partial coverage.
2. **Medium — coordinator text still named `chunks()` as Whole-book input.**
   Revision: production Whole-book retrieval is manifest-only; `chunks()` is
   reserved for bounded resolver scopes.

Round 3 re-audit is required before RED tests.

## Round 3

Verdict: `APPROVE`

No High or Medium findings remain. The auditor confirmed manifest enumeration
completeness, explicit legacy unknown remainder, manifest-only production
Whole-book retrieval, and the six round-1 corrections.
