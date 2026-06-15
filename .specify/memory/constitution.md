<!--
Sync Impact Report
===================
Version change: 1.0.0 → 1.0.1
Bump rationale: PATCH. Principle text unchanged; dependent template tasks-template.md
  reconciled with Principle II (test tasks now required, not optional). Non-semantic
  alignment fix. (Initial ratification at 1.0.0 defined all principles and governance.)

Modified principles:
  - [PRINCIPLE_1_NAME] → I. Code Quality
  - [PRINCIPLE_2_NAME] → II. Testing Standards (NON-NEGOTIABLE)
  - [PRINCIPLE_3_NAME] → III. User Experience Consistency
  - [PRINCIPLE_4_NAME] → IV. Performance Requirements
  - [PRINCIPLE_5_NAME] → (removed; reduced from 5 to 4 principles per request)

Added sections:
  - Quality Gates (was [SECTION_2_NAME])
  - Development Workflow (was [SECTION_3_NAME])

Removed sections:
  - Fifth template principle slot (intentionally dropped — only 4 principles requested)

Templates requiring updates:
  - ✅ .specify/templates/plan-template.md — Constitution Check gate is generic
       ("[Gates determined based on constitution file]"); no hardcoded principle
       references to change. Aligned.
  - ✅ .specify/templates/spec-template.md — no constitution-specific tokens; the
       mandatory Success Criteria section already supports performance/UX metrics. Aligned.
  - ✅ .specify/templates/tasks-template.md — reconciled with Principle II: test tasks
       are now REQUIRED (was "OPTIONAL - only if tests requested"); all conditional test
       phrasings replaced with explicit Constitution Principle II references. Aligned.

Follow-up TODOs:
  - None. RATIFICATION_DATE set to initial adoption date (2026-05-31).

---
Amendment v1.0.0 → v1.0.1 (PATCH, 2026-05-31): No principle text changed. Dependent
template tasks-template.md brought into compliance with Principle II (Testing Standards,
NON-NEGOTIABLE) — test tasks changed from optional to required. Non-semantic alignment fix.
-->

# flckd Constitution

## Core Principles

### I. Code Quality

Code MUST be readable before it is clever. Every change MUST satisfy the following
non-negotiable rules:

- The project's automated linter and formatter MUST pass with zero warnings before
  any code is merged; formatting is never a matter of personal style in committed code.
- Functions and modules MUST have a single, clearly named responsibility. A unit that
  cannot be described without the word "and" MUST be split.
- Public functions, exported types, and non-obvious logic MUST carry documentation that
  explains intent ("why"), not mechanics ("what").
- Dead code, commented-out blocks, and unused dependencies MUST be removed, not left
  "just in case". Version control is the archive.
- Every change MUST be reviewed by at least one person other than the author before merge.

**Rationale**: The dominant cost of software is reading and changing it later. Enforcing
consistency, small responsibilities, and intent-documenting comments keeps the cost of
future change low and reviews fast.

### II. Testing Standards (NON-NEGOTIABLE)

Tests are a first-class deliverable, not an afterthought:

- Every behavioral change MUST be accompanied by automated tests that would fail without
  the change. Bug fixes MUST include a regression test reproducing the original defect.
- The test suite MUST be deterministic. Flaky tests MUST be fixed or quarantined with a
  tracking issue within one working day; they MUST NOT be silently retried into green.
- New code MUST NOT decrease overall test coverage, and critical paths (auth, data
  mutation, money, security boundaries) MUST have explicit test coverage.
- Tests MUST exercise observable behavior and public contracts, not private
  implementation details, so refactors do not require rewriting unrelated tests.
- The full test suite MUST pass in CI before merge. A red build blocks merge — no exceptions.

**Rationale**: Tests are the executable specification that lets the team change code with
confidence. Determinism and behavior-focused tests prevent the suite from becoming noise
that the team learns to ignore.

### III. User Experience Consistency

The product MUST feel like one coherent system, not a collection of features:

- User-facing terminology, command/flag naming, error message structure, and output
  formats MUST follow a single documented convention across the entire surface area.
- Errors MUST be actionable: every error presented to a user MUST state what went wrong
  and what the user can do about it. Raw stack traces MUST NOT be the primary user-facing
  error.
- Interfaces that support both human and machine consumers MUST provide a human-readable
  default and a structured (e.g. JSON) mode; both MUST stay in sync.
- Breaking changes to any user-facing contract (CLI flags, API shapes, output formats)
  MUST be versioned and documented, with a migration note for users.
- Accessibility and clear feedback (progress, success, failure states) MUST be considered
  part of "done", not optional polish.

**Rationale**: Consistency is what lets users transfer what they learned in one part of the
product to another. Predictable naming, errors, and formats reduce support load and build
trust.

### IV. Performance Requirements

Performance is a feature with explicit, measurable targets:

- Every feature with user-perceivable latency MUST define performance budgets (e.g. p95
  latency, throughput, memory ceiling) in its spec before implementation begins.
- Performance-sensitive paths MUST be measured with representative data; claims of "fast
  enough" without a measurement are not acceptable.
- Regressions against an established budget MUST block release until resolved or until the
  budget is explicitly and deliberately renegotiated.
- Optimization MUST be evidence-driven: profile first, then optimize the demonstrated
  bottleneck. Speculative micro-optimization that harms readability is rejected under
  Principle I.
- Resource usage (memory, connections, file handles) MUST be bounded; unbounded growth
  under sustained load is a defect.

**Rationale**: Performance that is not specified and measured silently degrades. Explicit
budgets turn performance into a testable contract rather than a subjective debate, and
evidence-driven optimization keeps effort focused where it pays off.

## Quality Gates

These gates apply to every change and are enforced in CI and code review:

- **Lint & format gate**: linter and formatter pass with zero warnings (Principle I).
- **Test gate**: full suite green, new behavior covered, coverage not decreased (Principle II).
- **UX gate**: user-facing naming, errors, and output conform to the documented conventions
  (Principle III).
- **Performance gate**: declared performance budgets are met for affected paths (Principle IV).

A change that cannot pass a gate MUST either be brought into compliance or documented as a
justified, time-boxed exception in the pull request, referencing the specific principle and
the reason. Unjustified gate failures block merge.

## Development Workflow

- Work proceeds spec-first: a feature specification defines user scenarios, success
  criteria (including UX and performance targets), and acceptance tests before
  implementation.
- All changes land via pull request with at least one independent reviewer. Reviewers are
  responsible for verifying constitution compliance, not only correctness.
- CI MUST run the lint, test, and (where applicable) performance gates on every pull
  request; merging requires a green pipeline.
- Commits SHOULD be small and logically scoped, with messages explaining intent.
- Complexity MUST be justified: any deviation from the simplest working approach is
  recorded in the plan's Complexity Tracking section with the rejected simpler alternative.

## Governance

This constitution supersedes all other development practices. When a practice conflicts with
this document, this document wins until formally amended.

- **Amendments**: Proposed via pull request that edits this file, including the rationale
  and a migration/impact note. Amendments require approval from project maintainers before
  merge.
- **Versioning policy**: This constitution is versioned with semantic versioning.
  - MAJOR: backward-incompatible governance changes or removal/redefinition of a principle.
  - MINOR: a new principle or section, or materially expanded mandatory guidance.
  - PATCH: clarifications, wording, and non-semantic refinements.
- **Compliance review**: Every pull request and review MUST verify compliance with the
  Quality Gates above. Recurring or systemic violations MUST be raised as amendments rather
  than tolerated as informal exceptions.
- **Runtime guidance**: Agent- and contributor-facing operational guidance lives in
  `CLAUDE.md` and feature plans; those documents MUST stay consistent with this constitution.

**Version**: 1.0.1 | **Ratified**: 2026-05-31 | **Last Amended**: 2026-05-31
