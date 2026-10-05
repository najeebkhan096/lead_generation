/**
 * Outbound email. SMTP (nodemailer) when SMTP_HOST is set; Resend when
 * RESEND_API_KEY is set. Credentials stay on the backend.
 */

import { outreachLog } from './logger.js';

export class EmailSenderService {
  async sendEmail(_opts) {
    throw new Error('EmailSenderService.sendEmail must be implemented');
  }
}

export class DisabledEmailSender extends EmailSenderService {
  async sendEmail() {
    const err = new Error('No email provider configured. Set SMTP_HOST or RESEND_API_KEY.');
    err.status = 503;
    throw err;
  }
}

export class SmtpEmailSender extends EmailSenderService {
  constructor(env = process.env) {
    super();
    this.env = env;
  }

  async sendEmail({ recipient, subject, body, from, replyTo, headers = {} }) {
    const nodemailer = await import('nodemailer');
    const transporter = nodemailer.createTransport({
      host: this.env.SMTP_HOST,
      port: Number(this.env.SMTP_PORT || 587),
      secure: this.env.SMTP_SECURE === 'true',
      auth: this.env.SMTP_USER
        ? { user: this.env.SMTP_USER, pass: this.env.SMTP_PASS || '' }
        : undefined,
    });
    const info = await transporter.sendMail({
      from,
      to: recipient,
      subject,
      text: body,
      replyTo,
      headers,
    });
    outreachLog('email_sent', { provider: 'smtp', recipientDomain: recipient.split('@')[1] });
    return { provider: 'smtp', messageId: info.messageId || null };
  }
}

export class ResendEmailSender extends EmailSenderService {
  constructor(env = process.env) {
    super();
    this.apiKey = env.RESEND_API_KEY;
    this.env = env;
  }

  async sendEmail({ recipient, subject, body, from, replyTo, headers = {} }) {
    const res = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${this.apiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        from,
        to: [recipient],
        subject,
        text: body,
        reply_to: replyTo,
        headers,
      }),
    });
    const json = await res.json().catch(() => ({}));
    if (!res.ok) {
      const err = new Error(json.message || `Resend HTTP ${res.status}`);
      err.status = res.status;
      throw err;
    }
    outreachLog('email_sent', { provider: 'resend' });
    return { provider: 'resend', messageId: json.id || null };
  }
}

export function isEmailSenderConfigured(env = process.env) {
  return Boolean(env.RESEND_API_KEY?.trim() || env.SMTP_HOST?.trim());
}

export function createEmailSenderService(env = process.env) {
  if (env.RESEND_API_KEY?.trim()) return new ResendEmailSender(env);
  if (env.SMTP_HOST?.trim()) return new SmtpEmailSender(env);
  return new DisabledEmailSender();
}

export function isTemporarySendFailure(err) {
  const status = err?.status || err?.responseCode || 0;
  const msg = String(err?.message || '').toLowerCase();
  if (status >= 500 || status === 429) return true;
  return /timeout|temporar|try again|rate limit|econnreset|etimedout|socket/.test(msg);
}
