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

import pkg from 'whatsapp-web.js';
import QRCode from 'qrcode';
import * as whatsappSafety from './whatsappSafety.js';

const { Client, LocalAuth } = pkg;

const CHECK_TIMEOUT_MS = 20_000;

/** @type {import('whatsapp-web.js').Client | null} */
let client = null;

/** True once this connect() has actually shown a QR code — distinguishes a
 * fresh device link (which resets the warm-up clock) from LocalAuth simply
 * restoring an already-linked session. */
let sawFreshQrThisConnect = false;

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

function buildClient() {
  const c = new Client({
    authStrategy: new LocalAuth({ dataPath: '.wwebjs_auth' }),
    puppeteer: {
      headless: true,
      args: ['--no-sandbox', '--disable-setuid-sandbox'],
    },
  });

  c.on('qr', async (qr) => {
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
    state.status = 'auth_failure';
    state.error = message || 'Authentication failed';
    state.qrDataUrl = null;
  });

  c.on('ready', () => {
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
    resetState();
    state.error = reason && reason !== 'LOGOUT' ? `Disconnected: ${reason}` : null;
    client = null;
  });

  return c;
}

/** Idempotent — safe to call repeatedly while already connecting/connected. */
export function connect() {
  if (client || state.status === 'ready') {
    return { alreadyStarted: true };
  }
  state.status = 'initializing';
  state.error = null;
  sawFreshQrThisConnect = false;
  client = buildClient();
  client.initialize().catch((err) => {
    state.status = 'error';
    state.error = err.message || 'Failed to start WhatsApp Web session';
    client = null;
  });
  return { alreadyStarted: false };
}

export async function disconnectSession() {
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

export function isReady() {
  return state.status === 'ready' && client != null;
}

/**
 * @param {string} phoneDigits - country code + number, digits only, no '+'
 * @returns {Promise<{ checked: boolean, valid: boolean, whatsappId: string|null, error: string|null }>}
 */
export async function checkNumber(phoneDigits) {
  if (!isReady()) {
    return { checked: false, valid: false, whatsappId: null, error: 'WhatsApp Web is not connected' };
  }
  const digits = String(phoneDigits || '').replace(/\D/g, '');
  if (!digits) {
    return { checked: false, valid: false, whatsappId: null, error: 'No phone number' };
  }

  try {
    const result = await Promise.race([
      client.getNumberId(digits),
      new Promise((_, reject) =>
        setTimeout(() => reject(new Error('Timed out waiting for WhatsApp')), CHECK_TIMEOUT_MS)
      ),
    ]);
    return {
      checked: true,
      valid: Boolean(result),
      whatsappId: result?._serialized || null,
      error: null,
    };
  } catch (err) {
    return { checked: false, valid: false, whatsappId: null, error: err.message };
  }
}
