# LeadFinder — Free Reputation Lead Generation

Find USA businesses with **recent 1-star Google reviews** and a **WhatsApp-available phone** so you can offer reputation management services.

- **No Google Places API**
- **No paid APIs or scraping services**
- **Firebase Firestore** — search results stay in memory until you click **Save to Firebase**
- Playwright browser automation on public maps pages
- **Nationwide by default** — pick a category; searches all 50 U.S. states + D.C. until ~100 WhatsApp leads

## Stack

| Layer | Tech |
|-------|------|
| Backend | Node.js, Express, Playwright, Cheerio |
| Frontend | Flutter Web, Bloc, Clean Architecture |

## Project layout

```
backend/
  src/
    data/             # US states list
    scraper/          # googleMaps, bing, yelp
    services/         # filter, export, analyzer, lead orchestration
    controllers/
    routes/
    utils/            # memory store, date helpers
  exports/            # leads.csv / leads.json written here

frontend/
  lib/
    core/
    domain/
    data/
    presentation/     # Bloc + Search/Results pages (web search tool)

mobile/               # Flutter iOS/Android — browse Firebase leads by category
```

## Quick start

### 1. Backend

```bash
cd backend
npm install
npx playwright install chromium
npm run dev
```

API: `http://localhost:3001`

### 2. Frontend

```bash
cd frontend
flutter pub get
flutter run -d chrome
```

Optional custom API URL:

```bash
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:3001
```

## API

| Method | Path | Description |
|--------|------|-------------|
| POST | `/api/search` | Body: `{ category, dateRange, nationwide?, targetLeadCount?, maxResultsPerState?, analyze? }` |
| GET | `/api/search/status` | Progress / status |
| GET | `/api/search/results` | In-memory leads |
| DELETE | `/api/search/results` | Clear session |
| GET | `/api/export/csv` | Download CSV (+ write `exports/leads.csv`) |
| GET | `/api/export/json` | Download JSON (+ write `exports/leads.json`) |
| POST | `/api/db/save` | Persist current session leads to **Firebase Firestore** |
| GET | `/api/db/leads` | List saved leads from Firestore |
| GET | `/api/db/searches` | List save batches from Firestore |
| POST | `/api/search/analyze` | Optional keyword complaint categorization |

`dateRange`: `"7"` \| `"30"` \| `"90"` \| `"365"`

### Nationwide search (default)

Omit `location` or set `nationwide: true`. The backend walks every U.S. state (dense metro per state), keeps recent 1★ leads, verifies WhatsApp, and stops at `targetLeadCount` (default **100**).

```json
{
  "category": "Dentist",
  "dateRange": "30",
  "nationwide": true,
  "targetLeadCount": 100
}
```

### Single-location search (optional)

```json
{
  "location": "Austin, Texas",
  "category": "Dentist",
  "dateRange": "30",
  "nationwide": false
}
```

## MVP workflow

1. Choose category + date range on the Search page (no state needed)
2. Backend scrapes Google Maps across U.S. states
3. Keeps businesses that have **1-star** reviews inside the date window
4. Checks each phone for **WhatsApp availability** — only WA numbers are kept
5. Stops around **100 leads** (or when all states are done)
6. Results page shows name, rating, review, phone, WhatsApp link, website
7. Click **Save to Firebase** to write leads to Firestore (`leads` + `searches` collections) — duplicates match on Maps URL
8. Export CSV / JSON anytime

## Mobile app (browse leads)

```bash
cd mobile
flutter pub get
flutter run
```

Shows businesses from Firestore by category. Each card opens **Google Maps** or **WhatsApp**.

## Firebase setup

1. Create a project at [Firebase Console](https://console.firebase.google.com/) and enable **Firestore**.
2. Project settings → **Service accounts** → **Generate new private key**.
3. Save the JSON as:

```bash
backend/firebase-service-account.json
```

   (This file is gitignored.) Or copy `backend/.env.example` → `backend/.env` and set `FIREBASE_SERVICE_ACCOUNT` / `FIREBASE_PROJECT_ID`.

4. Restart the backend. `/api/health` should show `"firebase": { "configured": true }`.

On Render: add env var `FIREBASE_SERVICE_ACCOUNT` with the full JSON string, plus `FIREBASE_PROJECT_ID`.

## Notes

- Nationwide runs are **slow** (can take hours) because each listing is opened in a real browser and WhatsApp is checked one by one. Keep the tab open; the UI polls status.
- Scraping public Google Maps is best-effort; DOM changes or consent walls can reduce yield.
- Unsaved session leads are in memory only — restarting the server clears them. Saved leads live in Firebase.
- `ReviewAnalyzer` is heuristic/keyword-based and optional (no paid AI required).

## Go live (one URL for UI + API)

### Local production-style (same machine)

```bash
./scripts/build-web.sh
cd backend && npm start
```

Open **http://localhost:3001** — Flutter UI and `/api/*` on the same origin.

### Deploy on Render (public URL)

1. Push this repo to GitHub.
2. In [Render](https://render.com): **New → Blueprint** → connect the repo (uses `render.yaml`).
3. Wait for the Docker build (Flutter + Playwright). Open the service URL.

Or: **New → Web Service** → Docker → root Dockerfile → health check `/api/health`.

### Temporary public tunnel (your laptop)

With the server already on port 3001:

```bash
npx localtunnel --port 3001
```

Use the printed `https://….loca.lt` URL in a browser.

## Legal / ethics

Only use public pages for legitimate outreach. Respect site terms, robots guidance, and local laws. Rate-limit yourself; do not abuse targets.
