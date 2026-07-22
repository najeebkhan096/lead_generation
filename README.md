# LeadFinder — Free Reputation Lead Generation

Find USA businesses with **recent 1-star Google reviews** so you can offer reputation management services.

- **No Google Places API**
- **No paid APIs or scraping services**
- **No database** (in-memory session + optional local file export)
- Playwright browser automation on public maps pages

## Stack

| Layer | Tech |
|-------|------|
| Backend | Node.js, Express, Playwright, Cheerio |
| Frontend | Flutter Web, Bloc, Clean Architecture |

## Project layout

```
backend/
  src/
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
    presentation/     # Bloc + Search/Results pages
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
| POST | `/api/search` | Body: `{ location, category, dateRange, maxResults?, analyze? }` |
| GET | `/api/search/status` | Progress / status |
| GET | `/api/search/results` | In-memory leads |
| DELETE | `/api/search/results` | Clear session |
| GET | `/api/export/csv` | Download CSV (+ write `exports/leads.csv`) |
| GET | `/api/export/json` | Download JSON (+ write `exports/leads.json`) |
| POST | `/api/search/analyze` | Optional keyword complaint categorization |

`dateRange`: `"7"` \| `"30"` \| `"90"`

Example search body:

```json
{
  "location": "New York",
  "category": "Dentist",
  "dateRange": "30"
}
```

## MVP workflow

1. Enter location + category + date range on the Search page
2. Backend scrapes public Google Maps (Bing/Yelp fallback)
3. Keeps businesses that have **1-star** reviews inside the date window
4. Results page shows name, rating, review, phone, website
5. Export CSV / JSON (browser download + `backend/exports/`)

## Notes

- Scraping public Google Maps is best-effort; DOM changes or consent walls can reduce yield.
- Session data lives in memory only — restarting the server clears leads.
- `ReviewAnalyzer` is heuristic/keyword-based and optional (no paid AI required).

## Legal / ethics

Only use public pages for legitimate outreach. Respect site terms, robots guidance, and local laws. Rate-limit yourself; do not abuse targets.
