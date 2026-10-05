const SECRET_KEYS = /api[_-]?key|password|secret|token|authorization|credential/i;

function redact(value) {
  if (value && typeof value === 'object') {
    const out = Array.isArray(value) ? [] : {};
    for (const [k, v] of Object.entries(value)) {
      out[k] = SECRET_KEYS.test(k) ? '[redacted]' : redact(v);
    }
    return out;
  }
  return value;
}

export function outreachLog(event, details = {}) {
  const line = {
    ts: new Date().toISOString(),
    module: 'outreach',
    event,
    ...redact(details),
  };
  console.log(`[outreach] ${event}`, line);
}
