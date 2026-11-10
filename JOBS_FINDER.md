# Jobs Finder

An independent module of LeadFinder that finds job openings by **country → state/province → city × job title**,
across several sources, and keeps them de-duplicated in Firestore. It shares the app's Express server, Firebase
project, Playwright and Flutter shell, but not its collections, routes or data flow. The lead-generation features
are untouched.

```
Flutter web  ──►  /api/jobs  ──►  scan engine ──► source adapters ──► jobStore (dedupe) ──► Firestore
 (Jobs tab)        Express          queue + workers   Adzuna Jooble Remotive      jobs, companies, job_keys …
                                    scheduler         Greenhouse Lever Ashby Workable
                                                      career pages (HTTP, then Playwright)
```

## Set up

1. **Nothing to install.** The module is wired into `backend/src/index.js`; the web app has a **Jobs** item in the sidebar.
2. **Keys (optional, server-side only).** Put them in `backend/.env` — never in the Flutter app:
   `ADZUNA_APP_ID`, `ADZUNA_APP_KEY` (developer.adzuna.com), `JOOBLE_API_KEY` (jooble.org/api/about).
   A source without its key is reported as *not configured* and skipped; it never blocks a scan.
3. **Boards and career pages** (Greenhouse/Lever/Ashby/Workable/employer pages) are added in the app: **Jobs → Sources**.
4. **Firestore.** Deploy the new indexes and rules when you are ready (nothing was deployed for you):
   `firebase deploy --only firestore`. Until an index finishes building, the explorer falls back to a slower in-memory filter instead of failing.
5. Other environment switches are listed at the bottom of `backend/.env.example`.

## What a scan does

* **Search configuration** (`job_searches`): countries with a depth per country (whole country / each state / each city),
  all-or-picked states and cities, optional "also search remote jobs", job titles, keywords (each must appear),
  filters, source selection, limits and an optional daily schedule. `POST /api/jobs/searches/estimate` says how many
  combinations it expands to *before* anything runs (the whole US at city level is 7,515 per title).
* **Queue** (`job_search_queue`): one document per combination, claimed by transaction, so a task runs once.
* **Workers** run in the server, independent of any browser. Per scan: concurrency, pages per source, results per
  search, and a ceiling on combinations. Per source: requests/minute, requests/day (persisted), concurrency.
* **Failure isolation.** Every source of a combination runs independently. A combination fails only if *every* source it
  tried failed (after a retry). A source that is refused (401/403), out of daily quota, shows a bot wall, or fails five
  times in a row is switched off *for that scan*; the others carry on. HTTP calls retry with exponential backoff and honour `Retry-After`.
* **Pause / resume / stop** from the Scans tab. **Restart-safe:** progress lives in Firestore; on boot (and every few minutes)
  scans whose server died are resumed from the queue. A graceful shutdown (SIGTERM/SIGINT) marks scans `interrupted` so the next start resumes at once.
* **Daily scans:** a search with a schedule starts by itself at its local time (time zone aware); a server that was down at
  that time still runs it once that day.

## Duplicates

Each incoming job is resolved against, in order: same source + source job id → same canonical direct application URL
→ same **company + title + location** fingerprint → same company+title with a near-identical description (MinHash) and a
compatible location. A match updates the one document (adds the source, moves `lastVerifiedAt`, keeps `discoveredAt` and
per-source first-seen), and the scan reports it as *updated* or *duplicate*, never *new*. Lookups for a whole page of
jobs are one batched read. Deleting a job leaves its keys marked deleted so later scans don't bring it back.

A job is **expired** only when *every* source reports it gone on two consecutive checks (404/410, or a board that was read in
full no longer lists it). A source that errors or can't tell changes nothing. Manual expiry always wins over scans.

## Data

Collections: `jobs` (+ `raw` sub-collection with the original payloads), `companies`, `job_searches`, `job_sources`,
`job_scan_runs`, `job_search_queue`, `job_applications`, `job_alerts`, and `job_keys` (duplicate-detection lookups).
Missing facts are stored as `null`, never guessed. Rules: all of these are explicitly **server-only**; the existing rules
are untouched. Lists are cursor-paged on the server; the explorer only ever holds the pages it has scrolled.

## Sources — what is verified

| Source | Needs | Checked against |
|---|---|---|
| Greenhouse, Lever, Ashby | board token (no key) | **live public APIs** (fixtures in the tests are real payloads) |
| Remotive | nothing | **live**. Their free API currently returns only the 12 newest jobs and ignores `search`; terms require a link back + credit, ≤4 calls/day (enforced) |
| Adzuna | `ADZUNA_APP_ID/KEY` | documented API shape only — no key was available. Countries: US, CA, DE and more; **not** QA/AE/SA |
| Jooble | `JOOBLE_API_KEY` | documented API shape only — no key was available. This is the source that covers QA/AE/SA |
| Workable | account name | endpoint confirmed live; job-field mapping from the documented payload (no populated public account was found) |
| Career pages | page URL | local pages incl. JS-rendered ones through real Chrome; reads schema.org `JobPosting`, obeys robots.txt, **never** works around CAPTCHAs/bot walls/logins |

No LinkedIn or Indeed scraping. Adzuna/Jooble links go through their redirect URLs, so those jobs have an *original* link but no direct apply link.

## Geography

`backend/src/data/jobs/geo/*.json`: US (51 regions, 7,515 cities), CA, DE, SA, AE, QA — GeoNames places with population ≥ 5,000
(CC-BY 4.0) — plus the *Worldwide / Remote* pseudo-country. **Add a country without code:** drop a JSON file there, or
`npm run jobs:import-geo -- --csv france.csv --country FR --name France --label Region` (CSV columns `region,city[,population[,region_code]]`),
or from GeoNames dumps (see the script header). `JOBS_GEO_DIR` adds an extra directory.

## API

All under `/api/jobs`; see the header of `backend/src/modules/jobs/routes/jobsRoutes.js` for the full list: geo, sources,
searches (CRUD, estimate, `…/scan`), scans (history, active, progress, pause/resume/stop, failures), jobs (filters + cursor paging,
detail, patch, delete, verify, match, CSV export of filters or selected ids), companies, stats, applications, alerts.
Validation errors are `422` with a field list; conflicts `409`; rate limit `429`. **Auth:** the web console has no sign-in today, so
like the other admin routes the API is open by default. `JOBS_REQUIRE_AUTH=true` requires a Firebase ID token of an approved
account (admins only for changes) — turn it on when the console signs in, or it will lock the Jobs section out.

## AI matching (prepared, not wired into scans)

`matching/matcher.js` defines the result shape (score, matching/missing skills, experience fit, relevant requirements, CV
suggestions) and a provider interface. The built-in `keyword` provider is local and free; it runs only on demand
(`POST /api/jobs/:id/match`, or *Compare with my CV* on a job). No scan or listing calls it. An AI provider = one object
`{ id, match }` registered in `createMatcher`; none ships today.

## Tests

```
cd backend  && npm run test:jobs      # 128 tests: dedupe, engine, adapters, API, scheduler, geo, career pages (real Chrome)
cd backend  && npm test               # whole backend suite
cd frontend && flutter test           # 123 tests (59 for Jobs)
```
Store and engine tests run on `testing/fakeFirestore.js` (an in-memory stand-in that models the behaviours that matter);
they never touch a real database. One older test (`scan/scanProgress.test.js`) fails on a machine without Playwright's bundled
browser (`npx playwright install`); it is unrelated to Jobs.

## Known limits

* Dedupe is exact within one server process (writes are serialised); two server instances scanning at once could, rarely, both create the same new job.
* Salary filters compare approximate annual figures and only within a stated currency.
* Alerts record matches on the Overview; sending email is not implemented.
* The geography stops at places of 5,000+ people; import a fuller list for smaller towns.
* Adzuna, Jooble and Workable mappings have not been exercised live (see the table).
