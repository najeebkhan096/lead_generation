/**
 * A real, authenticated WhatsApp Web session — the only way to actually
 * know whether a number is registered on WhatsApp, since WhatsApp exposes
 * no public API for that. This drives the real web.whatsapp.com client
 * (via whatsapp-web.js, a headless-browser wrapper around it) under an
 * account you link yourself by scanning a QR code, exactly like adding a
 * linked device in a browser.
 *
 * Unofficial and against WhatsApp's Terms of Service — WhatsApp can rate
 * limit or ban the linked number if it looks automated. Keep checks slow
 * and infrequent (see whatsappValidationJob.js), and expect this to break
 * whenever WhatsApp changes their web client until whatsapp-web.js catches
 * up (this happens periodically — see their GitHub issues).
 *
 * One session for the whole server, matching the rest of this app's
 * "one thing running at a time" model.
 */

import fs from 'fs';
import os from 'os';
import path from 'path';
import { fileURLToPath } from 'url';
import pkg from 'whatsapp-web.js';
import QRCode from 'qrcode';
import * as whatsappSafety from './whatsappSafety.js';

const { Client, LocalAuth } = pkg;

const CHECK_TIMEOUT_MS = 20_000;
/** Give WhatsApp Web time to boot; Puppeteer's default 180s CDP timeout is
 * what produced the stuck "Starting session…" spinner. */
const PROTOCOL_TIMEOUT_MS = 120_000;
const AUTH_TIMEOUT_MS = 90_000;
const INIT_WATCHDOG_MS = 120_000;

const AUTH_DIR = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../.wwebjs_auth');
const CACHE_DIR = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../.wwebjs_cache');

/** @type {import('whatsapp-web.js').Client | null} */
let client = null;

/** True once this connect() has actually shown a QR code — distinguishes a
 * fresh device link (which resets the warm-up clock) from LocalAuth simply
 * restoring an already-linked session. */
let sawFreshQrThisConnect = false;

/** @type {ReturnType<typeof setTimeout> | null} */
let initWatchdog = null;

/** Bumped whenever a connect attempt is superseded so an in-flight
 * `initialize()` rejection does not clobber the next attempt. */
let initGeneration = 0;

const state = {
  status: 'disconnected', // disconnected | initializing | qr | authenticated | ready | auth_failure | error
  qrDataUrl: null,
  error: null,
  phoneNumber: null,
  pushname: null,
  readyAt: null,
};

function resetState() {
  state.status = 'disconnected';
  state.qrDataUrl = null;
  state.error = null;
  state.phoneNumber = null;
  state.pushname = null;
  state.readyAt = null;
}

function clearInitWatchdog() {
  if (initWatchdog) {
    clearTimeout(initWatchdog);
    initWatchdog = null;
  }
}

function armInitWatchdog() {
  clearInitWatchdog();
  initWatchdog = setTimeout(() => {
    if (state.status === 'initializing' || state.status === 'authenticated') {
      failInitialize(
        new Error(
          'WhatsApp Web took too long to start. A saved session is often frozen — click Try again for a fresh QR code.'
        ),
        { wipeSession: true }
      );
    }
  }, INIT_WATCHDOG_MS);
}

function resolveChromePath() {
  const fromEnv = process.env.PUPPETEER_EXECUTABLE_PATH || process.env.CHROME_PATH;
  if (fromEnv) return fromEnv;
  if (os.platform() === 'darwin') {
    const macChrome = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
    if (fs.existsSync(macChrome)) return macChrome;
  }
  return undefined;
}

function wipeAuthArtifacts() {
  for (const dir of [AUTH_DIR, CACHE_DIR]) {
    try {
      fs.rmSync(dir, { recursive: true, force: true });
    } catch (err) {
      console.warn(`[whatsapp-web] could not remove ${dir}:`, err.message);
    }
  }
}

function isStaleSessionError(err) {
  const message = String(err?.message || err || '');
  return /protocolTimeout|callFunctionOn timed out|auth timeout|took too long|Target closed|Session closed|Navigation timeout/i.test(
    message
  );
}

function friendlyError(err) {
  const message = String(err?.message || err || 'Failed to start WhatsApp Web session');
  if (isStaleSessionError(err)) {
    return (
      'WhatsApp Web froze while starting (usually a stale saved session). ' +
      'Click Try again — a QR code should appear so you can link the device again.'
    );
  }
  return message;
}

async function destroyQuietly(c) {
  if (!c) return;
  try {
    await c.destroy();
  } catch {
    // ignore — tearing down a hung Chromium is best-effort
  }
}

function failInitialize(err, { wipeSession = false } = {}) {
  initGeneration += 1;
  clearInitWatchdog();
  const c = client;
  client = null;
  state.status = 'error';
  state.qrDataUrl = null;
  state.error = friendlyError(err);
  console.error('[whatsapp-web] initialize failed:', err?.message || err);
  void destroyQuietly(c).then(() => {
    if (wipeSession || isStaleSessionError(err)) wipeAuthArtifacts();
  });
}

function buildClient() {
  const executablePath = resolveChromePath();
  const c = new Client({
    authStrategy: new LocalAuth({ dataPath: AUTH_DIR }),
    authTimeoutMs: AUTH_TIMEOUT_MS,
    takeoverOnConflict: true,
    puppeteer: {
      headless: true,
      protocolTimeout: PROTOCOL_TIMEOUT_MS,
      ...(executablePath ? { executablePath } : {}),
      args: [
        '--no-sandbox',
        '--disable-setuid-sandbox',
        '--disable-dev-shm-usage',
        '--disable-gpu',
        '--no-first-run',
        '--disable-extensions',
      ],
    },
  });

  c.on('loading_screen', (percent, message) => {
    console.log(`[whatsapp-web] loading ${percent}% ${message || ''}`.trim());
  });

  c.on('qr', async (qr) => {
    clearInitWatchdog();
    sawFreshQrThisConnect = true;
    try {
      state.status = 'qr';
      state.qrDataUrl = await QRCode.toDataURL(qr, { margin: 1, scale: 6 });
      state.error = null;
    } catch (err) {
      state.status = 'error';
      state.error = `Failed to render QR code: ${err.message}`;
    }
  });

  c.on('authenticated', () => {
    state.status = 'authenticated';
    state.qrDataUrl = null;
  });

  c.on('auth_failure', (message) => {
    clearInitWatchdog();
    state.status = 'auth_failure';
    state.error = message || 'Authentication failed';
    state.qrDataUrl = null;
    wipeAuthArtifacts();
  });

  c.on('ready', () => {
    clearInitWatchdog();
    state.status = 'ready';
    state.qrDataUrl = null;
    state.error = null;
    state.readyAt = Date.now();
    state.phoneNumber = c.info?.wid?.user || null;
    state.pushname = c.info?.pushname || null;
    if (sawFreshQrThisConnect) {
      whatsappSafety.markFreshLink();
    }
  });

  c.on('disconnected', (reason) => {
    clearInitWatchdog();
    resetState();
    state.error = reason && reason !== 'LOGOUT' ? `Disconnected: ${reason}` : null;
    client = null;
  });

  return c;
}

async function startClient({ allowRetry = true } = {}) {
  const generation = ++initGeneration;
  client = buildClient();
  armInitWatchdog();
  try {
    await client.initialize();
  } catch (err) {
    if (generation !== initGeneration) return;
    const retry = allowRetry && isStaleSessionError(err);
    await destroyQuietly(client);
    client = null;
    clearInitWatchdog();
    if (generation !== initGeneration) return;
    if (retry) {
      console.warn('[whatsapp-web] initialize failed; wiping session and retrying once:', err.message || err);
      wipeAuthArtifacts();
      state.status = 'initializing';
      state.error = null;
      sawFreshQrThisConnect = false;
      return startClient({ allowRetry: false });
    }
    failInitialize(err, { wipeSession: true });
  }
}

/** Idempotent — safe to call repeatedly while already connecting/connected. */
export function connect() {
  if (state.status === 'ready' && client) {
    return { alreadyStarted: true };
  }
  if (
    client &&
    (state.status === 'initializing' || state.status === 'qr' || state.status === 'authenticated')
  ) {
    return { alreadyStarted: true };
  }

  const shouldWipe = state.status === 'error' || state.status === 'auth_failure';
  const leftover = client;
  client = null;
  if (leftover) void destroyQuietly(leftover);
  if (shouldWipe) wipeAuthArtifacts();

  state.status = 'initializing';
  state.error = null;
  state.qrDataUrl = null;
  sawFreshQrThisConnect = false;
  void startClient();
  return { alreadyStarted: false };
}

export async function disconnectSession() {
  clearInitWatchdog();
  const c = client;
  client = null;
  resetState();
  if (!c) return;
  try {
    await c.logout();
  } catch {
    // ignore — we're tearing it down regardless
  }
  try {
    await c.destroy();
  } catch {
    // ignore
  }
}

export function getStatus() {
  return {
    status: state.status,
    qrDataUrl: state.qrDataUrl,
    error: state.error,
    phoneNumber: state.phoneNumber,
    pushname: state.pushname,
    readyAt: state.readyAt,
  };
}

function pageIsUsable() {
  try {
    return Boolean(client?.pupPage) && !client.pupPage.isClosed();
  } catch {
    return false;
  }
}

export function isReady() {
  return state.status === 'ready' && client != null && pageIsUsable();
}

function markSessionBroken(err) {
  const message = String(err?.message || err || 'WhatsApp Web disconnected');
  console.error('[whatsapp-web] session died during check:', message);
  state.status = 'error';
  state.error =
    'WhatsApp Web disconnected mid-check (the browser tab closed). Connect it again from the WhatsApp Tool page.';
}

/**
 * One round-trip into WhatsApp Web. The library's `getNumberId` is not used:
 * after the LID migration it returns null whenever `result.wid` is missing
 * even if `result.lid` is a real registered user.
 */
async function lookupRegisteredId(digits) {
  const page = client?.pupPage;
  if (!page || !pageIsUsable()) return null;

  return page.evaluate(async (digits) => {
    const plus = `+${digits}`;
    const asUser = `${digits}@c.us`;
    const pick = (result) => {
      if (result == null || result === false) return null;
      if (result === true) return asUser;
      if (typeof result === 'string') return result.includes('@') ? result : null;
      const wid = result.wid ?? result.lid ?? result.pn;
      if (wid) {
        if (typeof wid === 'string') return wid;
        if (wid._serialized) return wid._serialized;
        if (wid.user && wid.server) return `${wid.user}@${wid.server}`;
      }
      if (result._serialized) return result._serialized;
      if (result.user && result.server) return `${result.user}@${result.server}`;
      if (result.exists === true) return asUser;
      return null;
    };

    const job = window.require('WAWebQueryExistsJob');
    if (typeof job?.queryPhoneExists === 'function') {
      try {
        const id = pick(await job.queryPhoneExists(plus));
        if (id) return id;
      } catch {
        // fall through to wid query
      }
    }

    const factory = window.require('WAWebWidFactory');
    const r = await job.queryWidExists(factory.createWid(asUser));
    return pick(r);
  }, digits);
}

/**
 * @param {string} phoneDigits - country code + number, digits only, no '+'
 * @returns {Promise<{ checked: boolean, valid: boolean, whatsappId: string|null, error: string|null, sessionFailure?: boolean }>}
 */
export async function checkNumber(phoneDigits) {
  if (!isReady()) {
    return {
      checked: false,
      valid: false,
      whatsappId: null,
      error: 'WhatsApp Web is not connected',
      sessionFailure: true,
    };
  }
  const digits = String(phoneDigits || '').replace(/\D/g, '');
  if (!digits) {
    return { checked: false, valid: false, whatsappId: null, error: 'No phone number', sessionFailure: false };
  }

  try {
    const whatsappId = await Promise.race([
      lookupRegisteredId(digits),
      new Promise((_, reject) =>
        setTimeout(() => reject(new Error('Timed out waiting for WhatsApp')), CHECK_TIMEOUT_MS)
      ),
    ]);
    if (whatsappId) {
      console.log(`[whatsapp-web] registered +${digits}`);
    }
    return {
      checked: true,
      valid: Boolean(whatsappId),
      whatsappId: whatsappId || null,
      error: null,
    };
  } catch (err) {
    const message = String(err?.message || err);
    if (/invalid wid/i.test(message)) {
      return { checked: true, valid: false, whatsappId: null, error: null, sessionFailure: false };
    }
    console.warn(`[whatsapp-web] lookup failed +${digits}:`, message);
    if (/Target closed|Session closed|Protocol error|not connected/i.test(message)) {
      markSessionBroken(err);
    }
    return {
      checked: false,
      valid: false,
      whatsappId: null,
      error: err.message,
      sessionFailure: true,
    };
  }
}
