/**
 * Personalized web-development outreach copy. Uses an OpenAI-compatible
 * API when OPENAI_API_KEY is set; otherwise a conservative template that
 * only mentions observations actually present in the analysis.
 */

import { outreachLog } from './logger.js';

const FALLBACK_MODEL = 'template';

function sanitizeName(name) {
  const trimmed = String(name || '').trim();
  return trimmed || 'your business';
}

function firstIssue(analysis) {
  const issues = analysis?.issues;
  if (!Array.isArray(issues) || !issues.length) return null;
  return issues[0];
}

function firstOpportunity(analysis) {
  const ops = analysis?.opportunities;
  if (!Array.isArray(ops) || !ops.length) return null;
  return ops[0];
}

export function buildTemplateEmail({ business, category, location, analysis, senderName }) {
  const name = sanitizeName(business);
  const issue = firstIssue(analysis);
  const opportunity = firstOpportunity(analysis);
  const sender = String(senderName || 'Najeeb').trim() || 'Najeeb';

  let observation;
  if (analysis?.signals?.hasWebsite === false) {
    observation = 'your Google listing does not currently show a website';
  } else if (issue?.title) {
    observation = issue.title.toLowerCase();
  } else {
    observation = 'a few straightforward improvements that would make the site easier for customers to use';
  }

  const service = opportunity?.title
    ? opportunity.title.toLowerCase()
    : analysis?.signals?.hasWebsite === false
      ? 'a simple business website'
      : 'clearer contact paths and a stronger call to action';

  const locationBit = location ? ` in ${location}` : '';
  const categoryBit = category ? `${category} ` : '';

  const subject = `A quick idea for ${name}'s website`;
  const body = [
    `Hi ${name} team,`,
    '',
    `I came across your ${categoryBit}listing${locationBit} and noticed ${observation}.`,
    '',
    `I'm a developer who helps businesses improve their websites and digital customer experience, including ${service}.`,
    '',
    `I'd be happy to share a few ideas for ${name} if you're interested.`,
    '',
    'Would you be open to a quick conversation?',
    '',
    'Best,',
    sender,
  ].join('\n');

  return { subject, body, model: FALLBACK_MODEL };
}

function buildPrompt({ business, category, location, website, analysis, senderName }) {
  const issueLines = (analysis?.issues || [])
    .slice(0, 5)
    .map((i) => `- ${i.title}: ${i.description}`)
    .join('\n') || '- (none with evidence)';
  const oppLines = (analysis?.opportunities || [])
    .slice(0, 5)
    .map((i) => `- ${i.title}: ${i.description}`)
    .join('\n') || '- (none with evidence)';

  return `Write a short, human web-development outreach email.

Business name: ${business || 'Unknown'}
Category: ${category || 'Unknown'}
Location: ${location || 'Unknown'}
Website: ${website || '(none on listing)'}
Website score: ${analysis?.score ?? 'n/a'}

Evidence-based issues:
${issueLines}

Evidence-based opportunities:
${oppLines}

Rules:
- Concise (under 140 words).
- Sound like a person, not a campaign.
- Mention at most one observation that appears in the issues/opportunities lists. If the list is empty, do not invent a website problem — say you help businesses with websites generally.
- Clearly state that ${senderName || 'Najeeb'} provides web-development services.
- Simple call to action (open to a conversation).
- No exaggerated claims, fake urgency, or spam language.
- Do not pretend the analysis was a manual audit.
- Do not fabricate business facts.
- Sign off as ${senderName || 'Najeeb'}.
- Return JSON only: {"subject":"...","body":"..."} with body using \\n newlines.`;
}

export async function generateOutreachEmail(input) {
  const senderName = input.senderName || process.env.OUTREACH_SENDER_NAME || 'Najeeb';
  const apiKey = process.env.OPENAI_API_KEY?.trim() || process.env.AI_API_KEY?.trim();
  const template = buildTemplateEmail({ ...input, senderName });

  if (!apiKey) {
    outreachLog('ai_email_generated', { model: FALLBACK_MODEL, reason: 'no_api_key' });
    return template;
  }

  const baseUrl = (process.env.OPENAI_BASE_URL || 'https://api.openai.com/v1').replace(/\/$/, '');
  const model = process.env.OPENAI_MODEL || 'gpt-4o-mini';
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 25000);

  try {
    const res = await fetch(`${baseUrl}/chat/completions`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${apiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model,
        temperature: 0.4,
        response_format: { type: 'json_object' },
        messages: [
          { role: 'system', content: 'You write careful, honest B2B emails. Never invent website problems.' },
          { role: 'user', content: buildPrompt({ ...input, senderName }) },
        ],
      }),
      signal: controller.signal,
    });
    if (!res.ok) {
      const errText = await res.text().catch(() => '');
      outreachLog('ai_email_generated', { model, ok: false, status: res.status });
      return { ...template, model: `${model}_fallback`, lastError: `AI HTTP ${res.status} ${errText.slice(0, 180)}` };
    }
    const json = await res.json();
    const content = json.choices?.[0]?.message?.content || '';
    const parsed = JSON.parse(content);
    const subject = String(parsed.subject || '').trim() || template.subject;
    const body = String(parsed.body || '').trim() || template.body;
    outreachLog('ai_email_generated', { model, ok: true });
    return { subject, body, model };
  } catch (err) {
    outreachLog('ai_email_generated', { model, ok: false, error: err.message || String(err) });
    return { ...template, model: `${model}_fallback`, lastError: err.message || String(err) };
  } finally {
    clearTimeout(timer);
  }
}
