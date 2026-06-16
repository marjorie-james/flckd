# Security Policy

flckd is a privacy-critical application: its central promise is **strict anonymity** —
no third party ever receives a user's origin, destination, or route; no accounts, no
PII, no persistent identifiers; logs never retain route coordinates or client IPs. We
treat anything that weakens that promise as a security issue, not just classic
memory/injection bugs.

## Reporting a vulnerability

**Please do not open a public issue for security or privacy vulnerabilities.**

Report privately via GitHub's
[**private vulnerability reporting**](https://docs.github.com/en/code-security/security-advisories/guidance-on-reporting-and-writing-information-about-vulnerabilities/privately-reporting-a-security-vulnerability)
on this repository (the **Security → Report a vulnerability** tab). If that is
unavailable to you, open a minimal public issue asking a maintainer to open a private
channel — without details.

When reporting, please include:

- A description of the issue and its impact.
- Steps to reproduce (a proof of concept if you have one).
- Affected component(s): backend API, frontend SPA, or the self-hosted geo stack
  (Valhalla / Nominatim / tiles).
- Whether the issue could leak a user's route, origin/destination, or any client
  identifier (these are highest severity — see below).

We aim to acknowledge a report within a few days and to keep you updated as we work on a
fix. We're glad to credit reporters who want it.

## What we consider in scope

- **Anonymity / privacy leaks** (highest priority): any path by which a user's
  origin/destination/route, client IP, or a persistent identifier reaches a third party,
  a log, or another user. flckd has **no network transmission exception** — a route leaves
  the app only as a user-initiated, fully client-side GPX file saved to the user's own
  device. Any path that sends route data off-device, or that makes the GPX export behave
  as anything other than the explicit, warned, local-only action it is meant to be, is in
  scope.
- Standard web vulnerabilities in the API or SPA (injection, SSRF, auth-bypass-style
  logic flaws, XSS, etc.).
- Vulnerabilities in how the self-hosted geo services are wired together that could be
  reached through the application.

## Out of scope

- Vulnerabilities in third-party dependencies that already have a public advisory and a
  fix — please just open a normal PR bumping the dependency (Dependabot covers most of
  these).
- Findings that require a compromised host or physical access to the deployment.
- The contents of public OpenStreetMap data itself.

## Supported versions

flckd is developed on `main`; security fixes land there. There are no separately
maintained release branches at this time.
