## Summary

<!-- What does this change and why? -->

## Type of change

- [ ] Bug fix
- [ ] New feature
- [ ] Docs / infra / chore

## Non-negotiables checklist

- [ ] **Anonymity preserved** — no third party receives a user's origin/destination/route;
      no accounts/PII/persistent identifiers added; logs don't retain route coordinates or
      client IPs. (A route leaves the app only as a user-initiated, fully client-side GPX
      export — nothing is transmitted off-device.)
- [ ] **Self-hosted geo stack preserved** — no new third-party geo/tile/font/script
      dependency called at request time.
- [ ] **Camera avoidance** still excludes the specific monitored segment(s) via
      snap-to-road, not a radius (if applicable).
- [ ] **Tests added/updated** for behavioral changes (Constitution Principle II); geo
      services stubbed with fixtures.
- [ ] CI is green.

## Notes for reviewers

<!-- Anything that needs context: trade-offs, follow-ups, anonymity/security implications. -->
