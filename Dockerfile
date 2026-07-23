# Stage 1: build Flutter web (same-origin API)
FROM ghcr.io/cirruslabs/flutter:stable AS web
WORKDIR /src
COPY frontend/ ./frontend/
WORKDIR /src/frontend
RUN flutter config --enable-web \
  && flutter pub get \
  && flutter build web --release --dart-define=API_BASE_URL=

# Stage 2: Node + Playwright Chromium
FROM mcr.microsoft.com/playwright:v1.61.1-jammy
WORKDIR /app

COPY backend/package.json backend/package-lock.json* ./backend/
WORKDIR /app/backend
RUN npm install --omit=dev

WORKDIR /app
COPY backend/ ./backend/
COPY --from=web /src/frontend/build/web ./backend/public/

ENV NODE_ENV=production
ENV PLAYWRIGHT_BROWSERS_PATH=/ms-playwright
WORKDIR /app/backend

EXPOSE 3001
CMD ["npm", "start"]
