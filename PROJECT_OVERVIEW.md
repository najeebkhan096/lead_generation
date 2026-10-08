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
- **Entry point:** `src/index.js`. It serves the API under `/api/*` and also serves the built web app from `backend/public`.
- **Scrapers** (`src/scraper/`): Google Maps (main), Yelp and Bing.
- **Orchestrators:**
  - `stateCityOrchestrator` walks states and cities. Several cities run in parallel (2–8 workers).
  - `multiCategoryOrchestrator` runs one category after another.
- **Review logic:** `reviewAnalyzer` and `reviewFilter` pick out 1-star reviews inside a date window (7, 28, 30, 90 or 365 days).
- **WhatsApp:**
  - `whatsappChecker` is a format check only.
  - `whatsappWebService` and `whatsappValidationJob` use `whatsapp-web.js` with a QR-linked session to really validate numbers. They run one at a time, with rate limits.
- **Outreach** (`src/services/outreach/`): email discovery, email verification, website analysis, AI or template email generation, sending (SMTP or Resend), campaigns and logging.
- **Storage services:** the `*Store.js` files read and write leads, website leads, sales, users, the watchlist, Excel archives and outreach records. They currently use Firebase Firestore and Storage.
- **Local DB:** `better-sqlite3` in `src/db/database.js`.
- **Export:** CSV, JSON and multi-sheet Excel (ExcelJS).

### Web admin (`frontend/`)
Pages: Dashboard, Leads, Website Leads, WhatsApp Tool, Sales, Settings, Excel Scan, Scan Progress, Excel Archive and WhatsApp Verified. It is built with `--dart-define=API_BASE_URL=` (empty) so the UI and API share one origin.

### Mobile app (`mobile/`)
- Google sign-in through Firebase Auth.
- Tabs: WA (WhatsApp-verified leads), Leads, Sales and Profile.
- Salespeople can favorite leads, set status, open Maps or WhatsApp, and see their own sales. They cannot create or delete leads.

### Launcher (`launcher/`)
A desktop app. It starts the backend on port 3001, health-checks `/api/health`, and opens the UI.

## 3. How a scan works

1. In **Excel Scan**, the user picks categories, a review window and a worker count.
2. Categories run one at a time. For each, every U.S. state runs in order.
3. Within a state, up to N cities are scraped in parallel. Each city is a Google Maps search of up to about 160 listings.
4. Review leads and website leads are saved. A per-category Excel workbook (one sheet per state) is saved after each state finishes.
5. Pause, resume and cancel are supported. Only one scan runs at a time. Scans take hours.
6. Phones are normalized and given a `wa.me` link. WhatsApp registration is not assumed until validation runs.

## 4. Data model (current: Firebase)

| Collection | Purpose |
|-----------|---------|
| `leads` | Review leads |
| `websiteLeads` | No-website businesses |
| `searches` | Scan batches |
| `excelScans` | Excel archive metadata and download URL |
| `whatsappValidatedScans` | Workbooks of validated numbers |
| `sales` | Orders and payouts |
| `users` | Salesperson profiles |
| `watchlist` | Businesses re-scanned for new 1-star reviews |
| outreach collections | Campaigns, records and email logs |

## 5. API summary

| Area | Prefix |
|------|--------|
| Health | `GET /api/health` |
| State/city scan | `/api/state-scan` |
| Leads DB | `/api/db` |
| WhatsApp format check | `/api/whatsapp/check` |
| WhatsApp Web | `/api/whatsapp-web` |
| Excel archives | `/api/excel-scans` |
| WhatsApp-validated archives | `/api/whatsapp-validated-scans` |
| Watchlist | `/api/watchlist` |
| Sales | `/api/sales` |
| Users | `/api/users` |
| Outreach | `/api/outreach` |
| Export | `/api/export` |
| Legacy and dormant | `/api/search`, `/api/search/multi` |

## 6. Resource requirements

- **Two headless Chromium instances:** one for Playwright scraping and one for WhatsApp Web. Plan for 2 GB of RAM or more (`npm start` allows an 8 GB heap).
- **Persistent disk:** needed for the WhatsApp session in `.wwebjs_auth` (about 146 MB) and the SQLite data.
- **Always-on process:** scans run for hours.
- **Not suited to:** Render free (512 MB, sleeps, no disk) and serverless platforms.

## 7. Risks and cautions

- WhatsApp Web automation is unofficial and against WhatsApp's terms. A linked number can be banned, so rate-limit it.
- Scraping Google Maps may breach its terms of service, and selectors can break when the page changes.
- Outreach email needs consent and opt-out handling. Check anti-spam laws such as CAN-SPAM.
- `backend/firebase-service-account.json` is a secret. Never commit it, and rotate it if it has been exposed.
- Check that the API is authenticated before exposing it publicly.

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
