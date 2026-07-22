/**
 * Parse relative / absolute review dates and check against a range.
 */

const DAY_MS = 24 * 60 * 60 * 1000;

export function daysForRange(range) {
  if (range == null) return 30;
  const raw = String(range).trim().toLowerCase();

  if (raw === 'last_7_days') return 7;
  if (raw === 'last_30_days') return 30;
  if (raw === 'last_90_days') return 90;

  const n = Number(raw);
  if (!Number.isNaN(n) && n > 0) return n;

  return 30;
}

/**
 * Convert Google/Bing relative dates like "2 days ago", "Edited a week ago" to Date.
 */
export function parseRelativeDate(text) {
  if (!text || typeof text !== 'string') return null;

  let cleaned = text.trim().toLowerCase();
  cleaned = cleaned.replace(/^edited\s+/i, '').trim();

  const now = new Date();

  if (cleaned.includes('just now') || cleaned.includes('a moment')) {
    return now;
  }

  const hourMatch = cleaned.match(/(\d+)\s*hours?\s*ago/);
  if (hourMatch) {
    return new Date(now.getTime() - Number(hourMatch[1]) * 60 * 60 * 1000);
  }

  if (cleaned.includes('an hour ago') || cleaned.includes('a hour ago')) {
    return new Date(now.getTime() - DAY_MS / 24);
  }

  const dayMatch = cleaned.match(/(\d+)\s*days?\s*ago/);
  if (dayMatch) {
    return new Date(now.getTime() - Number(dayMatch[1]) * DAY_MS);
  }

  if (cleaned.includes('a day ago') || cleaned.includes('yesterday')) {
    return new Date(now.getTime() - DAY_MS);
  }

  const weekMatch = cleaned.match(/(\d+)\s*weeks?\s*ago/);
  if (weekMatch) {
    return new Date(now.getTime() - Number(weekMatch[1]) * 7 * DAY_MS);
  }

  if (cleaned.includes('a week ago')) {
    return new Date(now.getTime() - 7 * DAY_MS);
  }

  const monthMatch = cleaned.match(/(\d+)\s*months?\s*ago/);
  if (monthMatch) {
    return new Date(now.getTime() - Number(monthMatch[1]) * 30 * DAY_MS);
  }

  if (cleaned.includes('a month ago')) {
    return new Date(now.getTime() - 30 * DAY_MS);
  }

  const yearMatch = cleaned.match(/(\d+)\s*years?\s*ago/);
  if (yearMatch) {
    return new Date(now.getTime() - Number(yearMatch[1]) * 365 * DAY_MS);
  }

  if (cleaned.includes('a year ago')) {
    return new Date(now.getTime() - 365 * DAY_MS);
  }

  const absolute = Date.parse(text);
  if (!Number.isNaN(absolute)) {
    return new Date(absolute);
  }

  return null;
}

export function isWithinRange(dateText, rangeKey) {
  const days = daysForRange(rangeKey);
  const parsed = parseRelativeDate(dateText);
  if (!parsed) {
    // Unknown formats: keep for MVP recall
    return true;
  }
  const cutoff = Date.now() - days * DAY_MS;
  return parsed.getTime() >= cutoff;
}
