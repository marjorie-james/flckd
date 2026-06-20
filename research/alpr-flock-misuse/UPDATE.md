# How to update this dataset

This is a one-shot replay guide for refreshing [`flock-alpr-misuse.csv`](./flock-alpr-misuse.csv).
The goal each run: capture **new** reputable news about FLOCK/ALPR misuse **published after the
last run's `articles_through` date** (see [`RUNLOG.md`](./RUNLOG.md)), dedupe against existing rows,
append, and log the run.

## Procedure

1. **Read the cutoff.** Open `RUNLOG.md`, take the most recent run's `articles_through` date.
   Call it `CUTOFF`. Only collect articles published **after** `CUTOFF`.
2. **Fan out agents.** Dispatch the agents below in parallel (one message, multiple Agent calls).
   Append this line to every prompt:
   > Only include articles published AFTER {CUTOFF}. Use reputable sources only (major papers,
   > AP/Reuters, network affiliates, 404 Media, EFF, ACLU, The Markup, Wired, TechCrunch, court
   > records, government audits). Exclude blogs, forums, Reddit, opinion-only, and aggregators.
   > Return entries as: STATE | CITY/AGENCY | HEADLINE | SOURCE | DATE | URL | 2-3 sentence SUMMARY |
   > POLICE_MISCONDUCT (yes/no).
3. **Dedupe.** Drop any returned story whose `url` already appears in the CSV, or whose
   `(state, headline)` matches an existing row. National investigations that touch multiple
   states get one row per newly-named state (consistent with how Run 1 split the EFF
   protest/Romani investigations).
4. **Append** the survivors to `flock-alpr-misuse.csv` using the existing schema/quoting.
   `police_misconduct=yes` only when an officer/agency misused/illegally accessed/abused the data;
   vendor failures, contract/program controversies, and constitutional challenges are `no`.
5. **Validate** (run from this directory):
   ```
   python3 -c "import csv;r=list(csv.DictReader(open('flock-alpr-misuse.csv')));print(len(r),'rows');assert all(len(x)==9 for x in r)"
   ```
6. **Log the run.** Add a new `### Run N` block in `RUNLOG.md`: set `run_timestamp` to
   `date -u +%Y-%m-%dT%H:%M:%SZ`, set `articles_through` to today's date, record `new_rows_added`
   and any caveats. This new `articles_through` becomes the next run's `CUTOFF`.

## Agent roster (13)

**Regional sweeps** (group results by state):
1. **West Coast** — CA, OR, WA, NV, AZ, AK, HI
2. **Mountain/Plains** — TX, OK, KS, NE, CO, NM, UT, WY, MT, ID, ND, SD, MO
3. **Midwest** — IL, IN, OH, MI, WI, MN, IA
4. **Northeast/Mid-Atlantic** — NY, NJ, PA, MA, CT, RI, VT, NH, ME, MD, DE, DC
5. **Southeast** — VA, NC, SC, GA, FL, TN, AL, MS, LA, AR, KY, WV

**Thematic deep-dives:**
6. **National investigations** — 404 Media (Koebler/Cox), EFF, Wired, The Markup, AP; nationwide
   audit/log of Flock searches; federal (ICE/CBP/Secret Service/Navy) access.
7. **Immigration/ICE** — Flock data accessed by/shared with ICE/CBP/DHS, sanctuary-law and
   SB 34-type violations, council/audit fallout.
8. **Officer personal misuse/stalking** — officers stalking partners/family via Flock; disciplined,
   fired, charged, or sued. (Cross-check the Institute for Justice running tally.)
9. **Data breaches/security** — exposed cameras/feeds, stolen credentials, vendor CVEs, improper
   bulk sharing (404 Media, TechCrunch, named security researchers).
10. **Audits/lawsuits/rulings** — Norfolk IJ suit, California State Auditor, ACLU/EFF/IJ suits,
    Fourth Amendment rulings, IG/state-auditor findings.

**State deep-dives** (highest-volume states):
11. **Texas** — Johnson County abortion search + fallout, ICE searches, contract cancellations.
12. **Illinois** — SoS audits, CBP pilot, Danville records, suburban terminations, DEA credential use.
13. **California** — State Auditor, SB 34/SB 54 violations, SFPD/El Cajon/Oakland, AG actions.

## Standing watchlists (cheap recurring checks)
- 404 Media Flock tag · EFF "Street-Level Surveillance" / Flock deeplinks · ACLU state affiliates
- Institute for Justice ALPR stalking tracker (case count has climbed 14 → 17 → 18)
- `haveibeenflocked.com` and DeFlock community findings — **leads only**, must be traced to a
  reputable outlet before adding a row.
