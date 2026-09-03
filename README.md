# LeadFinder

Find businesses with **recent 1-star Google reviews** (reputation leads) and businesses with **no website** (website leads), then reach them on WhatsApp.

The live scan engine walks **every U.S. state, city by city** in a real browser. There is no Google Places API and no paid scraping service.

Hosted UI: [https://whatsapplead-a8d9a.web.app](https://whatsapplead-a8d9a.web.app)  
API (runs on your machine): `http://localhost:3001`

## What it does

| Signal | Saved to | Used for |
|--------|----------|----------|
| Recent 1★ Google review | Firestore `leads` | Reputation-management outreach |
| Business listing with no website | Firestore `websiteLeads` | Web-build / digital-presence outreach |
| Phone on WhatsApp (optional) | `hasWhatsApp` on the lead | Filter and message from the mobile app |

A scan also writes an **Excel archive** (one workbook per category, one sheet per state) to Firebase Storage as each state finishes, so progress is not lost if the job is paused or the server restarts.

## Stack

| Layer | Tech |
|-------|------|
| Backend | Node.js, Express, Playwright (Google Maps), whatsapp-web.js |
| Web admin | Flutter Web, Bloc, go_router |
| Mobile | Flutter iOS/Android, Firebase Auth (Google), Firestore |
| Desktop launcher | Flutter — starts the local API and opens the hosted UI |
| Data | Firebase Firestore + Storage (`whatsapplead-a8d9a`) |

## Project layout

```
backend/          Node API, scrapers, WhatsApp Web session, Firestore writes
frontend/         Flutter web admin (Dashboard, Leads, scans, Sales, …)
mobile/           Flutter iOS/Android app for salespeople
launcher/         Desktop helper to start/stop the local backend
scripts/          build-web.sh — release web build into backend/public
Dockerfile        Flutter web + Playwright Chromium, one container
firebase.json     Hosting serves frontend/build/web
render.yaml       Optional Render Docker deploy
```

## Apps

### Web admin (`frontend/`)

Persistent sidebar (or bottom nav on a narrow window):

| Page | URL | Purpose |
|------|-----|---------|
| Dashboard | `/` | Totals and recent saved leads |
| Leads | `/leads` | Review leads from Firestore |
| Website Leads | `/website-leads` | No-website businesses |
| WhatsApp Tool | `/whatsapp` | Link WhatsApp Web + format check |
| Sales | `/sales` | Orders, payouts, assign to a salesman |
| Settings | `/settings` | Watchlist, verified archive, extras |
| Excel Scan | `/excel-scan` | Start a US state/city scan |
| Scan Progress | `/scan-progress` | Live state-by-state / city-by-city status |
| Excel Archive | `/excel-archive` | Download and resume scan workbooks |
| WhatsApp Verified | `/whatsapp-verified` | Archives of numbers that passed a real WA check |

The old single-search results page is gone. **Excel Scan is the way to start a scan.** A dormant multi-country dashboard still lives at `/multi-scan` for old archives only.

### Mobile (`mobile/`) — “Lead Outreach”

Google sign-in. Bottom tabs: **WA** (WhatsApp-verified leads), **Leads**, **Sales**, **Profile**. Salespeople can favorite, update status, open Maps / WhatsApp, and see their own sales. They cannot create or delete leads; the backend (Admin SDK) owns writes.

### Launcher (`launcher/`)

Starts `backend` on port 3001 without a terminal, health-checks `/api/health`, and opens the hosted frontend. Default hosted URL is `https://whatsapplead-a8d9a.web.app`.

## How a scan works

1. **Excel Scan** — pick one or more categories, a review date window (7 / 28 / 30 / 90 / 365 days), and worker count (2–8).
2. For each category (one at a time), every **U.S. state** runs in order.
3. Inside a state, up to `concurrency` **cities** scrape in parallel. Each city opens Google Maps in Playwright and reads listings (up to ~160 per city).
4. Two buckets are filled:
   - **Review leads** — 1-star review inside the date window → Firestore `leads` (and the Excel sheet).
   - **Website leads** — no website on the listing → Firestore `websiteLeads`.
5. When a state finishes, that category’s `.xlsx` is checkpointed to Storage. Pause / resume / cancel are supported. Only one scan runs at a time.

Phones are normalized and a `wa.me` link is attached. **Registration on WhatsApp is not assumed** until you connect WhatsApp Web and run validation.

Scans are slow (hours is normal). Keep the backend process running; the UI polls `/api/state-scan/status`.

## WhatsApp

Two different checks:

1. **Format check** (`POST /api/whatsapp/check`) — is this a plausible phone number? Builds a `wa.me` link. Does not prove the number is on WhatsApp.
2. **Real validation** — connect WhatsApp Web on the WhatsApp Tool page (scan a QR, same as Linked Devices). The backend drives `web.whatsapp.com` in headless Chrome via `whatsapp-web.js`. Use **Validate WhatsApp** on Leads, bulk auto-validate, or validate an Excel list.

This is unofficial and against WhatsApp’s terms. Rate-limit yourself; a linked number can be banned. Session files stay in `backend/.wwebjs_auth/` (gitignored). If connect hangs on “Starting session…”, restart the backend and try again — a stale session is the usual cause.

The hosted Firebase site talks to **localhost:3001**, so WhatsApp Web must run on the same machine as the API. Firebase Hosting cannot open Chrome.

## Quick start

### 1. Firebase

1. Enable **Firestore** and **Storage** on the Firebase project.
2. Download a service account key and save it as `backend/firebase-service-account.json` (gitignored).
3. Or copy `backend/.env.example` → `backend/.env` and set `FIREBASE_PROJECT_ID` / `FIREBASE_SERVICE_ACCOUNT`.

`GET /api/health` should report `"firebase": { "configured": true }`.

### 2. Backend

```bash
cd backend
npm install
npx playwright install chromium
npm run dev
```

API: [http://localhost:3001](http://localhost:3001)

`npm run dev` uses Node `--watch`. Run it from `backend/`, not the repo root. If you see `EADDRINUSE`, something else already owns port 3001 — stop that process first.

### 3. Frontend (local debug)

```bash
cd frontend
flutter pub get
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:3001
```

### 4. Mobile

```bash
cd mobile
flutter pub get
flutter run
```

Requires `google-services.json` / iOS `GoogleService-Info.plist` for the same Firebase project.

## Build and deploy the web admin

The hosted site is built to call the **local** API:

```bash
cd frontend
flutter clean
flutter pub get
flutter build web --release --dart-define=API_BASE_URL=http://localhost:3001
cd ..
firebase deploy --only hosting
```

Same-origin build (UI + API on one Express server, e.g. Docker / `npm start`):

```bash
./scripts/build-web.sh
cd backend && npm start
```

Open [http://localhost:3001](http://localhost:3001).

### Render (optional, one public URL)

`render.yaml` + root `Dockerfile`: Flutter web (empty `API_BASE_URL`) + Playwright Chromium. Health check: `/api/health`. Set `FIREBASE_SERVICE_ACCOUNT` in the dashboard. WhatsApp Web on a free Render instance is unreliable; keep that on the desktop backend.

## Firestore

| Collection | Role |
|------------|------|
| `leads` | Review leads. Mobile may update favorite / status / WhatsApp flags / assignee. |
| `websiteLeads` | No-website businesses. Same mobile update rules. |
| `searches` | Scan batches. Backend write only. |
| `excelScans` | Excel archive metadata + Storage download URL. |
| `whatsappValidatedScans` | Workbooks of numbers that passed a real WA check. |
| `sales` | Orders. A salesman can read only their own rows. |
| `users` | Mobile profiles (created on Google sign-in). |
| `watchlist` | Businesses to re-scan for new 1★ reviews. |

Rules: `firestore.rules`. Indexes: `firestore.indexes.json`.

## API (grouped)

Base: `http://localhost:3001`

| Area | Prefix | Notes |
|------|--------|--------|
| Health | `GET /api/health` | Firebase configured? |
| State/city scan | `/api/state-scan` | `POST /` start, `GET /status`, pause / resume / cancel |
| Session search | `/api/search` | Legacy in-memory search (still mounted) |
| Multi-country | `/api/search/multi` | Dormant orchestrator |
| Firestore leads | `/api/db` | List / delete leads and website leads, stats, clear |
| WhatsApp format | `/api/whatsapp/check` | Shape only |
| WhatsApp Web | `/api/whatsapp-web` | Connect, QR status, bulk validate |
| Excel archives | `/api/excel-scans` | List, download, resume, delete |
| WA-validated archives | `/api/whatsapp-validated-scans` | |
| Watchlist | `/api/watchlist` | CRUD + scan |
| Sales | `/api/sales` | CRUD + stats |
| Users | `/api/users` | Salesman list for assign pickers |
| Export | `/api/export` | CSV / JSON / multi xlsx |

## Notes

- Unsaved session search results live in memory and vanish on restart. Excel Scan checkpoints to Storage and Firestore as it goes.
- Google Maps DOM changes, consent walls, and rate limits reduce yield. Treat scrapes as best-effort.
- `whatsapp-web.js` breaks whenever WhatsApp ships a web-client change. Chromium must be able to launch on the API host.
- Country region files exist under `backend/src/data/` (UK, DE, Gulf, …) for the older multi-country engine. **The live Excel Scan path is U.S. only.**

## Legal / ethics

Use public listings for legitimate outreach only. Respect site terms, robots guidance, and local law. WhatsApp Web automation can get a number banned — keep checks slow. Do not abuse targets.
