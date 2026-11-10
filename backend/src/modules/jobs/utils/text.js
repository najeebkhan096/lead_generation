/** Text helpers: HTML -> readable text, accent folding, safe truncation. */

import * as cheerio from 'cheerio';

/** "Zürich" -> "Zurich", "São Paulo" -> "Sao Paulo". */
export function foldAccents(text) {
  return String(text ?? '')
    .normalize('NFKD')
    .replace(/[̀-ͯ]/g, '')
    .replace(/ß/g, 'ss')
    .replace(/ø/g, 'o')
    .replace(/Ø/g, 'O')
    .replace(/æ/g, 'ae')
    .replace(/Æ/g, 'AE');
}

/** Lowercase, accent-free, punctuation-free, single-spaced: a comparison key. */
export function fold(text) {
  return foldAccents(text)
    .toLowerCase()
    .replace(/&/g, ' and ')
    .replace(/[^\p{L}\p{N}+#.\s]/gu, ' ')
    .replace(/(?<![\p{L}\p{N}])\.|\.(?![\p{L}\p{N}])/gu, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

const BLOCK_TAGS = 'p,div,section,article,ul,ol,li,h1,h2,h3,h4,h5,h6,tr,br,blockquote,pre,table';

/**
 * Converts job-description HTML to plain text, keeping paragraph breaks and
 * turning list items into "- " lines (the section parser relies on that).
 * Source payloads are sometimes HTML-escaped twice (Greenhouse), so one
 * round of entity decoding is tried when no tags are present.
 */
export function htmlToText(html) {
  let input = String(html ?? '');
  if (!input.trim()) return '';
  if (!/<[a-z][\s\S]*>/i.test(input) && /&lt;[a-z]/i.test(input)) {
    input = cheerio.load(`<body>${input}</body>`).text();
  }
  const $ = cheerio.load(`<body>${input}</body>`, null, false);
  $('script,style,noscript,template').remove();
  $('li').each((_, el) => {
    $(el).prepend('- ');
  });
  $(BLOCK_TAGS).each((_, el) => {
    $(el).append('\n');
  });
  const text = $.root().text();
  return cleanText(text);
}

/** Collapses runs of whitespace but keeps single blank lines between paragraphs. */
export function cleanText(text) {
  return String(text ?? '')
    .replace(/ /g, ' ')
    .replace(/[\t\f\v\r]+/g, ' ')
    .replace(/[ ]+\n/g, '\n')
    .replace(/\n[ ]+/g, '\n')
    .replace(/[ ]{2,}/g, ' ')
    .replace(/\n{3,}/g, '\n\n')
    .trim();
}

export function truncate(text, max) {
  const s = String(text ?? '');
  return s.length <= max ? s : `${s.slice(0, max - 1).trimEnd()}…`;
}

/** Null for empty/whitespace/non-strings so "missing" is always `null`. */
export function textOrNull(value) {
  if (value === undefined || value === null) return null;
  const s = String(value).replace(/\s+/g, ' ').trim();
  return s ? s : null;
}

export function numberOrNull(value) {
  if (value === undefined || value === null || value === '') return null;
  const n = typeof value === 'number' ? value : Number(String(value).replace(/[, ]/g, ''));
  return Number.isFinite(n) ? n : null;
}

/** A valid Date from an ISO string / epoch ms / epoch s / Date, else null. */
export function dateOrNull(value) {
  if (value === undefined || value === null || value === '') return null;
  let d;
  if (value instanceof Date) d = value;
  else if (typeof value === 'number') d = new Date(value < 1e11 ? value * 1000 : value);
  else d = new Date(String(value));
  const t = d.getTime();
  // Reject nonsense (epoch 0, year 1, far future) rather than store it.
  if (!Number.isFinite(t) || t < Date.UTC(1990, 0, 1) || t > Date.now() + 3 * 365 * 86_400_000) return null;
  return d;
}
