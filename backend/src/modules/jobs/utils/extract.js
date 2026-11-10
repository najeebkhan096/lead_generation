/**
 * Field extraction from posting text. Everything here is conservative: a
 * value is returned only when the text states it; otherwise `null`/`[]`.
 * Nothing is guessed from the job's industry or the searcher's query.
 */

import { fold } from './text.js';

// ------------------------------------------------------------------ salary

const CURRENCY_SYMBOLS = [
  [/US\$|\bUSD\b|\$/i, 'USD'],
  [/€|\bEUR\b/i, 'EUR'],
  [/£|\bGBP\b/i, 'GBP'],
  [/C\$|CA\$|\bCAD\b/i, 'CAD'],
  [/A\$|AU\$|\bAUD\b/i, 'AUD'],
  [/\bAED\b|د\.إ|\bDhs?\b/i, 'AED'],
  [/\bSAR\b|ر\.س/i, 'SAR'],
  [/\bQAR\b|\bQR\b|ر\.ق/i, 'QAR'],
  [/\bCHF\b/i, 'CHF'],
  [/\bINR\b|₹/i, 'INR'],
];

const PERIOD_WORDS = [
  [/\b(per\s+)?(year|yr|annum|annual(ly)?|p\.?a\.?|yearly|jahr|j[äa]hrlich)\b|\/\s*(yr|year)\b/i, 'year'],
  [/\b(per\s+)?(month|monthly|mo|pm|monat|monatlich)\b|\/\s*(mo|month)\b/i, 'month'],
  [/\b(per\s+)?(week|weekly|wk)\b|\/\s*(wk|week)\b/i, 'week'],
  [/\b(per\s+)?(day|daily|diem)\b|\/\s*day\b/i, 'day'],
  [/\b(per\s+)?(hour|hourly|hr|stunde)\b|\/\s*(hr|hour|h)\b/i, 'hour'],
];

function toAmount(raw, k) {
  const n = Number(String(raw).replace(/[,\s]/g, ''));
  if (!Number.isFinite(n)) return null;
  return k ? n * 1000 : n;
}

/**
 * Parses free-text pay such as "$80,000 - $100,000 a year", "£45k–55k",
 * "AED 10,000 monthly". Returns nulls for anything unclear.
 * @returns {{min:number|null, max:number|null, currency:string|null, period:string|null}}
 */
export function parseSalaryText(text) {
  const empty = { min: null, max: null, currency: null, period: null };
  const s = String(text ?? '').trim();
  if (!s) return empty;
  // Not a pay figure: "competitive", "negotiable", "DOE" and the like.
  const nums = [...s.matchAll(/(\d[\d,.\s]*\d|\d)\s*(k\b)?/gi)]
    .map((m) => ({ value: toAmount(m[1].replace(/\.(?=\d{3}\b)/g, ''), Boolean(m[2])), k: Boolean(m[2]) }))
    .filter((n) => n.value != null && n.value > 0);
  if (!nums.length) return empty;

  let currency = null;
  for (const [re, code] of CURRENCY_SYMBOLS) {
    if (re.test(s)) {
      currency = code;
      break;
    }
  }
  let period = null;
  for (const [re, p] of PERIOD_WORDS) {
    if (re.test(s)) {
      period = p;
      break;
    }
  }

  let [min, max] = [nums[0].value, nums.length > 1 ? nums[1].value : nums[0].value];
  // "45-55k": the k applies to both ends.
  if (nums.length > 1 && nums[1].k && !nums[0].k && nums[0].value < 1000) min = nums[0].value * 1000;
  if (min > max) [min, max] = [max, min];
  // Pay figures below 5 without a currency/period are almost certainly not pay (e.g. "3 years").
  if (max < 5 && !currency) return empty;
  return { min, max, currency, period };
}

/** Rough annual figure used only for range filtering, never shown as the salary. */
export function annualApprox(amount, period) {
  if (amount == null) return null;
  const factor = { year: 1, month: 12, week: 52, day: 260, hour: 2080 }[period];
  return factor ? Math.round(amount * factor) : null;
}

// ---------------------------------------------------------------- type etc.

export function detectEmploymentType(...texts) {
  const s = fold(texts.filter(Boolean).join(' '));
  if (!s) return null;
  const rules = [
    [/\b(intern|internship|praktikum|werkstudent|trainee|apprentice)\b/, 'internship'],
    [/\b(freelance|freelancer|self employed)\b/, 'freelance'],
    [/\b(part time|parttime|teilzeit)\b/, 'part_time'],
    [/\b(full time|fulltime|vollzeit|full-time)\b/, 'full_time'],
    [/\b(temporary|temp|seasonal|fixed term|befristet)\b/, 'temporary'],
    [/\b(contract|contractor|contract to hire|c2h)\b/, 'contract'],
    [/\b(permanent|unbefristet)\b/, 'permanent'],
  ];
  for (const [re, type] of rules) if (re.test(s)) return type;
  return null;
}

/** remote | hybrid | onsite from the first text that says so. */
export function detectWorkArrangement(...texts) {
  for (const t of texts) {
    const s = fold(t);
    if (!s) continue;
    if (/\bhybrid\b/.test(s)) return 'hybrid';
    if (/\b(fully remote|100 remote|remote first|remote friendly|work from home|wfh|telecommut\w*|remote)\b/.test(s)) return 'remote';
    if (/\b(on site|onsite|in office|in person)\b/.test(s)) return 'onsite';
  }
  return null;
}

export function detectExperienceLevel(title, text) {
  const t = fold(title);
  if (/\b(intern|internship|junior|jr|entry level|graduate|trainee|werkstudent)\b/.test(t)) return 'entry';
  if (/\b(chief|cto|ceo|cfo|vp|vice president|director|head of)\b/.test(t)) return 'executive';
  if (/\b(lead|principal|staff|architect|manager)\b/.test(t)) return 'lead';
  if (/\b(senior|sr)\b/.test(t)) return 'senior';
  if (/\b(mid level|mid-level|intermediate)\b/.test(t)) return 'mid';
  const s = fold(text);
  if (/\b(entry level|no experience required|recent graduate)\b/.test(s)) return 'entry';
  return null;
}

/**
 * "3+ years of experience", "2-4 years' experience" -> { years: 3, text }.
 * The sentence is kept as the evidence.
 */
export function extractExperience(text) {
  const s = String(text ?? '');
  const re = /(\d{1,2})\s*(?:\+|plus)?\s*(?:(?:-|–|to)\s*(\d{1,2})\s*)?(?:\+\s*)?(?:years?|yrs?)(?:['’]s?)?\s+(?:of\s+)?(?:[\w.+#/-]+\s+){0,3}?(?:experience|exp\b)/i;
  const m = s.match(re);
  if (!m) {
    const loose = s.match(/experience[^.\n]{0,40}?(\d{1,2})\s*(?:\+|plus)?\s*(?:years?|yrs?)/i);
    if (!loose) return { years: null, text: null };
    return { years: Number(loose[1]), text: sentenceAround(s, loose.index) };
  }
  return { years: Number(m[1]), text: sentenceAround(s, m.index) };
}

function sentenceAround(text, index) {
  const start = Math.max(text.lastIndexOf('\n', index), text.lastIndexOf('. ', index));
  let end = text.indexOf('\n', index);
  const dot = text.indexOf('. ', index);
  if (end === -1 || (dot !== -1 && dot < end)) end = dot;
  if (end === -1) end = text.length;
  return text.slice(start + 1, end + 1).replace(/^[\s\-•*]+/, '').trim().slice(0, 300) || null;
}

export function extractEducation(text) {
  const lines = String(text ?? '').split(/\n+/);
  const re = /\b(bachelor'?s?|b\.?sc\.?|b\.?eng\.?|b\.?a\.?|master'?s?|m\.?sc\.?|mba|ph\.?d\.?|doctorate|diploma|degree|abitur|ausbildung|high school|associate)\b/i;
  for (const raw of lines) {
    const line = raw.replace(/^[\s\-•*]+/, '').trim();
    if (re.test(line) && line.length < 300) return line;
  }
  return null;
}

// ------------------------------------------------------------------ sections

const SECTION_PATTERNS = {
  responsibilities: /^(?:key\s+)?(responsibilit\w*|what you(?:'|’)?ll do|what you will do|your role|the role|duties|day[- ]to[- ]day|your tasks|aufgaben|deine aufgaben|ihre aufgaben|in this role)/i,
  required: /^(requirements?|what we require|what we expect|we require|qualifications?|what you(?:'|’)?ll need|what we(?:'|’)?re looking for|what you bring|who you are|you have|must have|required skills?|skills required|minimum qualifications?|basic qualifications?|your profile|anforderungen|dein profil|ihr profil|about you)/i,
  preferred: /^(nice to have|preferred|bonus|good to have|plus(?:es)?|desirable|preferred qualifications?|pluses|it(?:'|’)?s a plus|wünschenswert|von vorteil)/i,
  other: /^(about (?:us|the (?:company|team))|who we are|benefits|perks|what we offer|we offer|compensation|salary|how to apply|equal opportunity|our (?:mission|values|culture)|why join|angebot|wir bieten)/i,
};

/**
 * Splits a plain-text description (as produced by htmlToText) into the
 * sections we care about. A heading is a short line, optionally ending with
 * ":", that matches one of the patterns above.
 * @returns {{responsibilities: string[], required: string[], preferred: string[], hasStructure: boolean}}
 */
export function parseSections(text) {
  const out = { responsibilities: [], required: [], preferred: [], hasStructure: false };
  let current = null;
  for (const raw of String(text ?? '').split('\n')) {
    const line = raw.trim();
    if (!line) continue;
    const heading = line.replace(/[:：]\s*$/, '').replace(/^[#*\s]+/, '').replace(/\*+$/, '').trim();
    const isHeadingShape = heading.length <= 60 && !/^[-•*]\s/.test(line) && (/[:：]\s*$/.test(line) || heading.split(' ').length <= 8);
    if (isHeadingShape) {
      let matched = null;
      for (const [name, re] of Object.entries(SECTION_PATTERNS)) {
        if (re.test(heading)) {
          matched = name;
          break;
        }
      }
      if (matched) {
        current = matched === 'other' ? null : matched;
        if (current) out.hasStructure = true;
        continue;
      }
    }
    if (current) out[current].push(line.replace(/^[-•*•]\s*/, '').trim());
  }
  return out;
}

/** Bullet-style lines from a section, capped. */
export function bulletList(lines, max = 25) {
  return lines.filter((l) => l.length > 3).slice(0, max).map((l) => l.slice(0, 400));
}

// -------------------------------------------------------------------- skills

/** canonical name -> alternative spellings found in text. */
const SKILLS = {
  Flutter: [], Dart: [], 'React Native': [], React: ['react.js', 'reactjs'], 'Next.js': ['nextjs'], 'Vue.js': ['vue', 'vuejs'],
  Angular: [], Svelte: [], TypeScript: [], JavaScript: ['js'], 'Node.js': ['node', 'nodejs'], Express: ['express.js'],
  NestJS: ['nest.js'], Python: [], Django: [], Flask: [], FastAPI: [], Java: [], Kotlin: [], Swift: [], SwiftUI: [],
  'Objective-C': [], 'C++': ['cpp'], 'C#': ['csharp'], '.NET': ['dotnet', 'asp.net'], Go: ['golang'], Rust: [], Ruby: [],
  'Ruby on Rails': ['rails'], PHP: [], Laravel: [], Scala: [], Elixir: [], SQL: [], PostgreSQL: ['postgres'], MySQL: [],
  MongoDB: [], Redis: [], Firebase: [], Firestore: [], GraphQL: [], 'REST APIs': ['rest api', 'restful', 'rest'], gRPC: [],
  Docker: [], Kubernetes: ['k8s'], Terraform: [], AWS: ['amazon web services'], Azure: [], 'Google Cloud': ['gcp'],
  Linux: [], Git: [], 'CI/CD': ['ci cd', 'cicd'], Jenkins: [], 'GitHub Actions': [], Kafka: [], RabbitMQ: [],
  Elasticsearch: [], Spark: ['apache spark'], Hadoop: [], Airflow: [], dbt: [], Snowflake: [], BigQuery: [], Tableau: [],
  'Power BI': ['powerbi'], Excel: [], 'Machine Learning': ['ml'], 'Deep Learning': [], TensorFlow: [], PyTorch: [],
  'Computer Vision': [], NLP: ['natural language processing'], 'Data Science': [], Pandas: [], NumPy: [], Android: [],
  iOS: [], 'Jetpack Compose': [], BLoC: [], Redux: [], Agile: [], Scrum: [], Jira: [], Figma: [], 'UI/UX': ['ux design', 'ui design'],
  'Unit Testing': ['unit tests'], 'Test Automation': ['test automation'], Selenium: [], Playwright: [], Cypress: [], Jest: [],
  'Project Management': [], 'Product Management': [], SEO: [], 'Digital Marketing': [], Salesforce: [], SAP: [], 'AutoCAD': [],
  Revit: [], 'Microsoft Office': ['ms office'], Accounting: [], 'Financial Analysis': [], 'Customer Service': [], Nursing: [],
  'Arabic': [], 'English': [], 'German': [], 'Cybersecurity': ['information security', 'infosec'], 'Penetration Testing': ['pentest'],
  'Network Engineering': [], 'DevOps': [], 'SRE': ['site reliability'],
};

// Skills whose canonical word is also an everyday word: matched case-sensitively.
const CASE_SENSITIVE = new Set(['Go', 'Express', 'Swift', 'Spark', 'React', 'Rust', 'Ruby', 'Git', 'SAP', 'Excel', 'Arabic', 'English', 'German', 'Android', 'Agile', 'Scrum', 'Jira', 'Flask', 'Java', 'REST APIs']);

const escapeRe = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
const SKILL_MATCHERS = Object.entries(SKILLS).map(([name, aliases]) => {
  const names = [name, ...aliases];
  const body = names.map((n) => escapeRe(n)).join('|');
  const flags = CASE_SENSITIVE.has(name) ? 'u' : 'iu';
  // Letter-or-digit boundaries so "Java" doesn't match inside "JavaScript" and "Go" not inside "Google".
  const re = new RegExp(`(?<![\\p{L}\\p{N}+#])(?:${body})(?![\\p{L}\\p{N}]|[+#])`, flags);
  return { name, re };
});

/** Skills explicitly mentioned in [text], in dictionary order. */
export function extractSkills(text) {
  const s = String(text ?? '');
  if (!s) return [];
  const found = [];
  for (const { name, re } of SKILL_MATCHERS) if (re.test(s)) found.push(name);
  // "Java" must not also be reported when only "JavaScript" is present — handled by the boundary above.
  return found;
}

/**
 * Required vs preferred skills. Skills in a "nice to have" section are
 * preferred; skills in a requirements section are required; if the posting
 * has no recognisable sections, mentioned skills are required (and
 * `skillsBasis` says so).
 */
export function classifySkills(description, extraSkills = []) {
  const sections = parseSections(description);
  const requiredText = sections.required.join('\n');
  const preferredText = sections.preferred.join('\n');
  const tagged = [...new Set(extraSkills.filter(Boolean).map(String))];
  if (sections.required.length || sections.preferred.length) {
    const preferred = extractSkills(preferredText);
    const required = [...new Set([...extractSkills(`${requiredText}\n${sections.responsibilities.join('\n')}`), ...tagged])].filter((k) => !preferred.includes(k) || extractSkills(requiredText).includes(k));
    return { requiredSkills: required, preferredSkills: preferred.filter((k) => !required.includes(k)), skillsBasis: 'sections' };
  }
  const mentioned = extractSkills(description);
  return { requiredSkills: [...new Set([...mentioned, ...tagged])], preferredSkills: [], skillsBasis: mentioned.length || tagged.length ? 'mentions' : null };
}
