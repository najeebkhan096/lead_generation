# LeadFinder: Project Overview

## 1. What this project is

LeadFinder is a lead-generation system for sales teams. It scans Google Maps, city by city across every U.S. state, and finds two kinds of business leads:

| Lead type | Signal | Pitch |
|-----------|--------|-------|
| **Review leads** | A recent 1-star Google review | Reputation-management services |
| **Website leads** | A business listing with no website | Web design and digital presence |

Salespeople can then check whether a lead's phone number is on WhatsApp, contact them by WhatsApp or email, and track sales.

There is no Google Places API and no paid scraping service. Everything uses a real headless browser (Playwright).

## 2. Components

```
lead_generation/
├── backend/    Node.js + Express API, scrapers, WhatsApp Web session, outreach engine
├── frontend/   Flutter Web admin panel (Bloc + go_router)
├── mobile/     Flutter iOS/Android app "Lead Outreach" for salespeople
├── launcher/   Flutter desktop helper that starts/stops the local backend
├── scripts/    build-web.sh: builds the web app into backend/public
├── Dockerfile  Builds Flutter web + Node + Playwright in one container
├── render.yaml Render deploy config (not suitable for this app's resource needs)
└── firebase.json / firestore.rules / firestore.indexes.json
```

### Backend (`backend/`)
Node.js + Express. Entry point `src/index.js` mounts every module's router under `/api/*` and serves the built web app from `backend/public`.

Code is organized **by feature module**, each folder holding its own routes, controllers and services:

```
src/
├── index.js              mounts the routers
├── firebase/admin.js     Firestore + Storage (Admin SDK)
├── lib/                  leadIdentity.js (one doc-id scheme for every lead
│                         collection), paths.js (runtime-state locations),
│                         memoryStore.js, asyncMutex.js, dateUtils.js
├── scraper/              Google Maps (main), Bing and Yelp fallbacks
├── data/                 country / state / city lists
├── middleware/           firebaseAuth.js
└── modules/
    ├── scan/             scan engines (state-city = live; single and
    │                     multi-category = legacy), review filtering
    ├── leads/            saved review + no-website leads (`leads`,
    │                     `websiteLeads`), the /api/db routes, leadSources.js
    ├── validation/
    │   ├── whatsapp/     real WhatsApp Web check, safety limits, job,
    │   │                 `whatsappLeads` store, verified archives
    │   └── email/        site crawl + web-search discovery, MX
    │                     verification, job, `emailLeads` store, archives
    ├── archive/          Excel scan archives + CSV/JSON/XLSX export
    ├── outreach/         email campaigns, drafts and sending
    ├── sales/  watchlist/  users/
    └── twilio-chat/      optional Express copy of the chat service —
                          NOT mounted; the live implementation is in
                          `functions/`. Needs `ffmpeg-static` to run.
```

**Runtime state** (`.wwebjs_auth`, `data/`, `exports/`) is anchored to the backend root by `src/lib/paths.js`, never to a module's own folder, so reorganizing `src/` cannot orphan the linked WhatsApp session.

### Web admin (`frontend/`)
Flutter web (Bloc + go_router). The navigation follows the work, in order:

| Item | What it is |
|------|-----------|
| Dashboard | Overview |
| **Scan** | Start a scan; watch it at `/scan-progress` |
| **Archive** | Finished scans as Excel workbooks — validate from here |
| **Leads** | `1-star review leads` / `No-website leads`, each with a **WhatsApp + Email** validation bar |
| **Verified** | `WhatsApp` / `Email` — the output of each validator |
| More | WhatsApp connection (QR), email outreach, sales, watchlist, users, verified archives |

Old URLs (`/excel-scan`, `/excel-archive`, `/website-leads`, `/email-leads`, `/settings`) redirect to their new homes.

### Mobile app (`mobile/`)
Flutter (iOS/Android), Google sign-in via Firebase Auth. Four tabs: **Leads** (scans / 1-star / no website), **WhatsApp** and **Email** (read live from `whatsappLeads` / `emailLeads`), and **More** (account, outreach chat, sales, search history, settings). Salespeople can favorite leads, set status, and open WhatsApp, email, phone or Maps. They cannot create or delete leads.

### Launcher (`launcher/`)
A desktop app. It starts the backend on port 3001, health-checks `/api/health`, and opens the UI.

## 3. How a scan works

1. In **Excel Scan**, the user picks categories, a review window and a worker count.
2. Categories run one at a time. For each, every U.S. state runs in order.
3. Within a state, up to N cities are scraped in parallel. Each city is a Google Maps search of up to about 160 listings.
4. Review leads and website leads are saved. A per-category Excel workbook (one sheet per state) is saved after each state finishes.
5. Pause, resume and cancel are supported. Only one scan runs at a time. Scans take hours.
6. Phones are normalized and given a `wa.me` link. WhatsApp registration is not assumed until validation runs.

## 4. Data model (Firebase)

| Collection | Holds | Written by |
|-----------|-------|-----------|
| `leads` | **Review leads** — a recent 1-star review | scan |
| `websiteLeads` | **No-website leads** | scan |
| `whatsappLeads` | Leads whose number a real WhatsApp check confirmed | WhatsApp validator |
| `emailLeads` | Leads whose contact email was found and verified | email validator |
| `searches` | Scan batches | scan |
| `excelScans` | Excel archive metadata (file in Storage) | scan |
| `whatsappValidatedScans`, `emailValidatedScans` | Verified-archive workbooks (metadata; file in Storage) | validators, from an archive |
| `sales`, `users`, `watchlist` | Sales, salesperson profiles, re-scan list | their modules |
| `outreach*` | Campaigns, records, queue, events | outreach |

**One identity across collections.** `lib/leadIdentity.js` derives the document id from the Maps URL (else phone, else name+address), so the same business has the *same id* in `leads`, `websiteLeads`, `whatsappLeads` and `emailLeads`.

**Validating copies, it never moves.** Both validators work on either lead type. A verified lead is *copied* into `whatsappLeads` / `emailLeads` (with `sourceType: review | website`, and for email the page it came from), and the verdict is also written onto the source lead (`hasWhatsApp`, `email`). Source leads are never deleted or re-keyed.

## 4b. Paging and lazy loading

Nothing loads a whole collection. `websiteLeads` alone holds tens of thousands of documents, so every lead list is read a page at a time and rendered lazily.

**Backend** (`lib/pagination.js`): `GET /api/db/{leads,website-leads,whatsapp-leads,email-leads}` take `limit` (default 50, max 200), `cursor`, `category`, `q`, and return `{ leads, nextCursor, total }`.

| | Indexed path | Scan path |
|---|---|---|
| When | no text search | `q` (text search) or an in-memory filter |
| Cost | one page of reads | walks the collection in slices (≤2,500 docs per request), field-masked; only matches are fetched in full |
| `total` | on the first page only | `null` |
| Resume | `nextCursor` | `nextCursor` — the client keeps asking until a page fills |

`nextCursor` is the last returned document's `updatedAt` + id (ties are broken by id, so nothing is skipped or repeated). `GET /api/db/categories?collection=` returns distinct categories with counts (cached 10 minutes) and `GET /api/db/overview` the dashboard's numbers (cached 1 minute). A category filter needs a composite index; until it has built, the backend falls back to filtering in memory instead of failing.

**Web**: one list engine — `PagedLeadsBloc` + `PagedLeadList` (a sliver grid, so only visible cards are built; the next page loads on scroll or via a "Load more" button) — behind Review, No-website, WhatsApp and Email leads (`LeadListPage` + a small config each). Search is debounced and answered by the server. Archive lead lists are bounded (parsed from a workbook) and reveal a window at a time (`LazyRevealMixin`).

**Mobile**: `PagedQueryController` (`limit` + `startAfterDocument`) behind `LeadCollectionPage`. Lists are one-shot page reads, so new data arrives on pull-to-refresh rather than live. "Discover leads" starts each salesman at a point derived from their uid in the document-id order and wraps around, which keeps salesmen on different leads without downloading the pool to shuffle it. Search on the phone filters what has been read (up to 1,500 documents) — pick a category to search further. Profile stats use server-side `count()`.

## 4a. Validation

| | WhatsApp | Email |
|---|---|---|
| Check | Number registered on WhatsApp (linked WhatsApp Web session) | Contact email found on the lead's website, or — with no website — by web search; then syntax, disposable-domain and MX checks |
| Pacing | Strictly sequential, randomized delay, daily cap, circuit breaker (account-ban protection) | 3–4 in parallel; web search is paced and stops if the search engine pushes back |
| Run over | Saved leads (`/validate-saved`), an Excel archive (`/validate-list`) | Saved leads (`/validate-saved`), an Excel archive (`/validate-list`) |
| Output | `whatsappLeads` (+ optional archive workbook) | `emailLeads` (+ optional archive workbook) |

Web-search emails are deliberately conservative: an address is kept only if it appears on a page that also shows the business's phone number (or its full name and city), and directory/social sites are never a source. Expect partial coverage — a miss beats a wrong address.

## 5. API summary

| Area | Prefix | Notes |
|------|--------|-------|
| Health | `GET /api/health` | |
| Scan | `/api/state-scan` | live engine |
| Saved leads | `/api/db` | `leads`, `website-leads`, **`whatsapp-leads`**, `email-leads` (all paged — see 4b), `categories`, `overview`, stats, clear |
| WhatsApp validation | `/api/whatsapp-web` | `connect`, `validate-saved`, `validate-list`, `validate/status`, `validate/cancel`, `safety` |
| Email validation | `/api/email-validation` | `validate-saved`, `validate-list`, `status`, `cancel` |
| Excel archives | `/api/excel-scans` | |
| Verified archives | `/api/whatsapp-validated-scans`, `/api/email-validated-scans` | |
| Watchlist / Sales / Users | `/api/watchlist`, `/api/sales`, `/api/users` | |
| Outreach | `/api/outreach` | |
| Export | `/api/export` | |
| Legacy | `/api/search`, `/api/search/multi`, `/api/whatsapp/check` | dormant |

`validate-saved` takes `{ "collection": "leads" | "websiteLeads", "ids": [...] }` (Firestore ids). Fields are read from Firestore by id, not trusted from the client.

## 6. Resource requirements

- **Two headless Chromium instances:** one for Playwright scraping and one for WhatsApp Web. Plan for 2 GB of RAM or more (`npm start` allows an 8 GB heap).
- **Persistent disk:** needed for the WhatsApp session in `.wwebjs_auth` (about 146 MB) and `data/` (WhatsApp safety counters).
- **Always-on process:** scans run for hours.
- **Not suited to:** Render free (512 MB, sleeps, no disk) and serverless platforms.

## 7. Risks and cautions

- WhatsApp Web automation is unofficial and against WhatsApp's terms. A linked number can be banned, so rate-limit it.
- Scraping Google Maps may breach its terms of service, and selectors can break when the page changes.
- Outreach email needs consent and opt-out handling. Check anti-spam laws such as CAN-SPAM.
- `backend/firebase-service-account.json` is a secret. Never commit it, and rotate it if it has been exposed.
- **The API has no authentication.** Every endpoint — including `POST /api/db/clear` — is open and the server binds `0.0.0.0` with CORS `*`. Keep it on localhost or behind a firewall until auth is added (the `middleware/firebaseAuth.js` helper exists but is not applied).

## 8. Deployment plan: free and independent

**Target:** one Docker container on a free always-on server that you control.

1. **Server:** Oracle Cloud Always Free ARM VM (2–4 cores, 12–24 GB RAM). A home PC or Raspberry Pi is an alternative.
2. **Run:** build the root `Dockerfile` and mount `.wwebjs_auth` and `backend/data` as volumes.
3. **HTTPS:** Caddy with a free DuckDNS subdomain.
4. **Email:** your own SMTP (Gmail app password). Skip OpenAI, since the template fallback works.
5. **Independence from Firebase** (phased):
   - Phase 1: deploy as is.
   - Phase 2: port the Firestore stores to SQLite.
   - Phase 3: replace Firebase Auth with backend email and password login using JWT.
   - Phase 4: update the mobile app to use the new auth.
6. **Backups:** a daily copy of the SQLite file and WhatsApp session to free storage.

## 9. Quick start (local)

```bash
cd backend
npm install
npx playwright install chromium
npm run dev            # API on http://localhost:3001

# Web UI, same origin:
./scripts/build-web.sh
cd backend && npm start
```

`GET /api/health` shows whether Firebase is configured.
