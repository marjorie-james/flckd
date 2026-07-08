# FLOCK / ALPR Camera Data Misuse — Research Run Log

This dataset tracks news coverage of misuse, abuse, illegal access, and controversy
involving FLOCK Safety cameras and other ALPR (automated license plate reader) systems.
Each run appends an entry below. When updating, **only add articles published after the
most recent run's `articles_through` date** to avoid re-litigating already-captured stories.

Data file: [`flock-alpr-misuse.csv`](./flock-alpr-misuse.csv)

## CSV schema
`state, city_agency, headline, source, publication_date, url, police_misconduct, category, summary`

- `police_misconduct`: `yes` = an officer/agency misused, illegally accessed, or abused the
  data ("police behaving badly"). `no` = vendor failure, contract/program controversy, or a
  constitutional challenge (not individual police misconduct).
- `category`: immigration · abortion · stalking · protest · discrimination · wrongful ·
  audit · lawsuit · program · vendor · security · oversight · policy · report · summary · cross-state
- `publication_date`: article publish date (use this to filter on future updates).

## Search parameters (held constant across runs)
- Subjects: FLOCK Safety cameras + other ALPR systems
- Scope: United States, grouped by state (+ NATIONAL / multi-state)
- Focus: misuse, illegal/improper access, audits finding violations, lawsuits, officer abuse,
  improper data sharing (ICE/immigration, abortion, protest), data breaches/security failures
- Source bar: reputable only (major papers, AP/Reuters, network affiliates, 404 Media, EFF,
  ACLU, The Markup, Wired, TechCrunch, court records, government audits). Excludes blogs,
  forums, Reddit, opinion-only, and aggregators.
- Dedupe: one row per distinct incident; cross-cutting national investigations under NATIONAL.

## Runs

### Run 1
- `run_timestamp`: 2026-06-20T00:25:00Z
- `articles_through`: 2026-06-19  ← next update: collect articles published AFTER this date
- `rows`: 120 distinct entries (incl. per-state rows for the shared EFF protest/Romani investigations)
- `police_misconduct=yes`: 78  ·  `no`: 42
- `states_with_incidents`: AZ, CA, CO, CT, DE, FL, GA, ID, IL, IN, IA, KS, KY, MD, MA, MI,
  MN, MO, NE, NV, NJ, NM, NY, NC, OH, OR, PA, RI, SC, TN, TX, UT, VT, VA, WA, WI (+ NATIONAL)
- `no_incident_found` (adoption/debate only): AL, AK, AR, HI, LA, MS, MT, ND, NH, OK, SD, WV, WY
- `method`: 13 parallel research agents (5 regional, 8 thematic/state deep-dives), then
  manual dedupe + grouping.
- `caveats`: A few .gov/paywalled URLs (Illinois SoS, NJ OAG, Vermont auditor PDF) were
  bot-blocked to automated fetch but corroborated via 2+ outlets. Thornton CO officer was
  *cleared* on audit (kept for completeness, police_misconduct=no). FL Monroe County deputy
  used DAVID/NCIC plus ALPR. Some 2025–2026 publication dates were month-confirmed but
  day-approximated where the outlet did not print an exact day.

<!-- ### Run 2
- run_timestamp:
- articles_through:
- new_rows_added:
- notes:
-->
