/**
 * The single choke point every WhatsApp Web lookup passes through —
 * whether it's the bulk "Validate WhatsApp" job or an inline check made
 * the moment a new lead is found during scanning. There's exactly one
 * linked WhatsApp account behind this whole app; every automated
 * interaction with it needs to look, cumulatively, like a human doing a
 * few lookups here and there, not a script running nonstop. That means:
 *
 *   - A hard daily cap, persisted to disk (not memory — this dev server
 *     restarts on every file save via `node --watch`, and an in-memory
 *     counter would reset right along with it).
 *   - A much lower cap and slower pacing for the first few days after a
 *     *fresh* QR-code link, since a brand-new linked device immediately
 *     doing bulk automated lookups is a classic signal that gets accounts
 *     flagged.
 *   - Real delays between checks, plus a longer "went and did something
 *     else for a bit" pause every so often, instead of a metronome.
 *   - A circuit breaker: if WhatsApp starts refusing/timing out lookups
 *     in a row, that's a sign to stop entirely for a while, not to keep
 *     hammering a session that may already be restricted.
 *   - One global mutex, so this is true regardless of how many things are
 *     concurrently trying to check numbers (the multi-category worker
 *     pool included) — they queue for the same slow-paced turnstile.
 */

import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import * as whatsappWeb from './whatsappWebService.js';
import { Mutex } from '../utils/asyncMutex.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const STORE_PATH = path.resolve(__dirname, '../../data/whatsapp-safety.json');

const DAILY_CAP = 150;
const WARMUP_DAILY_CAP = 30;
const WARMUP_DAYS = 3;

const NORMAL_DELAY_MS = [6000, 12000];
const WARMUP_DELAY_MS = [12000, 25000];
const LONG_BREAK_EVERY = 15;
const LONG_BREAK_MS = [90000, 180000];

const JOB_COOLDOWN_MS = 3 * 60 * 1000;
const CIRCUIT_FAILURE_THRESHOLD = 3;
const CIRCUIT_RESET_MS = 10 * 60 * 1000;

const mutex = new Mutex();

// Overridable only by tests, so day-rollover/warm-up/cooldown logic can be
// exercised without waiting real time.
let _now = () => Date.now();
let _storePath = STORE_PATH;

function today() {
  return new Date(_now()).toISOString().slice(0, 10);
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function randomBetween([min, max]) {
  return min + Math.random() * (max - min);
}

function loadState() {
  try {
    const raw = fs.readFileSync(_storePath, 'utf8');
    return JSON.parse(raw);
  } catch {
    return { checksByDay: {}, lastJobFinishedAt: null, linkedSince: null, consecutiveFailures: 0, circuitOpenedAt: null };
  }
}

function saveState(state) {
  try {
    fs.mkdirSync(path.dirname(_storePath), { recursive: true });
    fs.writeFileSync(_storePath, JSON.stringify(state, null, 2));
  } catch (err) {
    console.error('Failed to persist WhatsApp safety state:', err.message);
  }
}

function isWarmingUp(state) {
  if (!state.linkedSince) return false;
  const daysSinceLink = (_now() - state.linkedSince) / (24 * 60 * 60 * 1000);
  return daysSinceLink < WARMUP_DAYS;
}

function checksToday(state) {
  return state.checksByDay[today()] || 0;
}

function dailyCapFor(state) {
  return isWarmingUp(state) ? WARMUP_DAILY_CAP : DAILY_CAP;
}

function isCircuitOpen(state) {
  if (state.consecutiveFailures < CIRCUIT_FAILURE_THRESHOLD) return false;
  if (!state.circuitOpenedAt) return false;
  return _now() - state.circuitOpenedAt < CIRCUIT_RESET_MS;
}

/** Called once, the moment a *fresh* QR scan succeeds (not a restored session). */
export function markFreshLink() {
  const state = loadState();
  state.linkedSince = _now();
  state.consecutiveFailures = 0;
  state.circuitOpenedAt = null;
  saveState(state);
}

export function getSafetyStatus() {
  const state = loadState();
  const cap = dailyCapFor(state);
  const used = checksToday(state);
  const cooldownRemainingMs = state.lastJobFinishedAt
    ? Math.max(0, JOB_COOLDOWN_MS - (_now() - state.lastJobFinishedAt))
    : 0;
  const warmingUp = isWarmingUp(state);
  const circuitOpen = isCircuitOpen(state);

  return {
    checksToday: used,
    dailyCap: cap,
    remainingToday: Math.max(0, cap - used),
    warmUp: warmingUp
      ? {
          active: true,
          daysRemaining: Math.max(
            0,
            Math.ceil(WARMUP_DAYS - (_now() - state.linkedSince) / (24 * 60 * 60 * 1000))
          ),
        }
      : { active: false, daysRemaining: 0 },
    cooldown: { active: cooldownRemainingMs > 0, remainingMs: cooldownRemainingMs },
    circuitOpen,
    circuitResetInMs: circuitOpen ? Math.max(0, CIRCUIT_RESET_MS - (_now() - state.circuitOpenedAt)) : 0,
  };
}

/** Gate for starting a *bulk* validation run — not applied to inline checks, which are already self-pacing. */
export function canStartBulkJob() {
  const state = loadState();
  if (isCircuitOpen(state)) {
    return { allowed: false, reason: 'WhatsApp checks are paused — recent lookups failed repeatedly, which can mean the session is being rate-limited. Try again later.' };
  }
  const cap = dailyCapFor(state);
  const used = checksToday(state);
  if (used >= cap) {
    return { allowed: false, reason: `Daily WhatsApp check limit reached (${cap}). Resets at midnight UTC.` };
  }
  const cooldownRemainingMs = state.lastJobFinishedAt
    ? Math.max(0, JOB_COOLDOWN_MS - (_now() - state.lastJobFinishedAt))
    : 0;
  if (cooldownRemainingMs > 0) {
    return { allowed: false, reason: `Cooling down between validation runs — wait ${Math.ceil(cooldownRemainingMs / 1000)}s.` };
  }
  return { allowed: true, reason: null };
}

export function recordJobFinished() {
  const state = loadState();
  state.lastJobFinishedAt = _now();
  saveState(state);
}

/**
 * The one function anything that wants to check a number should call —
 * whether from the bulk job or inline during a scan. Serializes globally,
 * enforces the daily cap and circuit breaker, and paces itself (the delay
 * happens *inside* the lock, so the next caller — bulk or inline, doesn't
 * matter — waits its turn regardless of who's asking).
 *
 * @returns {Promise<{checked: boolean, valid: boolean, whatsappId: string|null, error: string|null, skipped: boolean}>}
 *   `skipped: true` means no attempt was made at all (cap/circuit) — as
 *   opposed to `checked: false`, which means an attempt was made and it
 *   failed/timed out.
 */
export async function guardedCheck(phone) {
  return mutex.runExclusive(async () => {
    const state = loadState();

    if (isCircuitOpen(state)) {
      return { checked: false, valid: false, whatsappId: null, error: 'WhatsApp checks paused (recent failures)', skipped: true };
    }
    const cap = dailyCapFor(state);
    const used = checksToday(state);
    if (used >= cap) {
      return { checked: false, valid: false, whatsappId: null, error: 'Daily WhatsApp check limit reached', skipped: true };
    }

    const result = await whatsappWeb.checkNumber(phone);

    const fresh = loadState(); // re-read: another path (rare) may have written meanwhile
    const day = today();
    fresh.checksByDay[day] = (fresh.checksByDay[day] || 0) + 1;

    if (result.checked) {
      fresh.consecutiveFailures = 0;
      fresh.circuitOpenedAt = null;
    } else {
      fresh.consecutiveFailures = (fresh.consecutiveFailures || 0) + 1;
      if (fresh.consecutiveFailures >= CIRCUIT_FAILURE_THRESHOLD && !fresh.circuitOpenedAt) {
        fresh.circuitOpenedAt = _now();
      }
    }
    saveState(fresh);

    const warmingUp = isWarmingUp(fresh);
    const totalChecks = fresh.checksByDay[day];
    const delayRange = warmingUp ? WARMUP_DELAY_MS : NORMAL_DELAY_MS;
    const delay =
      totalChecks % LONG_BREAK_EVERY === 0 ? randomBetween(LONG_BREAK_MS) : randomBetween(delayRange);
    await sleep(delay);

    return { ...result, skipped: false };
  });
}

/** Exposed for tests only. */
export function _configureForTests({ now, storePath } = {}) {
  if (now) _now = now;
  if (storePath) _storePath = storePath;
}

/** Clears whatever store `_storePath` currently points to — deliberately
 * never touches the real `STORE_PATH` unless a test explicitly configured
 * it that way, so a stray test run can't wipe real persisted safety state. */
export function _resetForTests() {
  try {
    fs.rmSync(_storePath, { force: true });
  } catch {
    // ignore
  }
}
