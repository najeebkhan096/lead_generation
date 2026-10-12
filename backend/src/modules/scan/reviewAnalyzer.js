/**
 * Optional AI-ready module (no paid API required).
 * Uses simple keyword heuristics by default.
 * Swap analyzeReview() to call an LLM later if desired.
 */

const CATEGORIES = [
  {
    key: 'Bad service',
    keywords: ['service', 'rude', 'unprofessional', 'terrible', 'awful', 'worst', 'horrible', 'attitude'],
  },
  {
    key: 'Pricing issue',
    keywords: ['price', 'pricing', 'expensive', 'overcharge', 'cost', 'bill', 'money', 'scam', 'ripoff', 'rip-off'],
  },
  {
    key: 'Staff behavior',
    keywords: ['staff', 'employee', 'manager', 'doctor', 'dentist', 'receptionist', 'nurse', 'tech'],
  },
  {
    key: 'Delivery problem',
    keywords: ['delivery', 'late', 'never arrived', 'shipping', 'wait', 'waiting', 'delay', 'appointment'],
  },
  {
    key: 'Cleanliness',
    keywords: ['dirty', 'filthy', 'unclean', 'hygiene', 'smell', 'messy'],
  },
  {
    key: 'Quality issue',
    keywords: ['quality', 'broken', 'defective', 'poor', 'fake', 'wrong'],
  },
];

/**
 * @param {string} reviewText
 * @returns {{ category: string, confidence: string, outreachMessage: string }}
 */
export function analyzeReview(reviewText, businessName = 'there') {
  const text = (reviewText || '').toLowerCase();
  let best = { key: 'Bad service', score: 0 };

  for (const cat of CATEGORIES) {
    let score = 0;
    for (const kw of cat.keywords) {
      if (text.includes(kw)) score += 1;
    }
    if (score > best.score) {
      best = { key: cat.key, score };
    }
  }

  const category = best.score > 0 ? best.key : 'General complaint';
  const confidence = best.score >= 3 ? 'high' : best.score >= 1 ? 'medium' : 'low';

  return {
    category,
    confidence,
    outreachMessage: generateOutreachMessage(businessName, category),
  };
}

export function generateOutreachMessage(businessName, complaintCategory = 'recent complaints') {
  const name = businessName || 'there';
  return (
    `Hi ${name},\n` +
    `I noticed some recent customer complaints online (${complaintCategory.toLowerCase()}). ` +
    `We help businesses improve their online reputation and recover customer trust.`
  );
}

/**
 * Enrich a lead with optional analysis fields (in-memory only).
 */
export function enrichLeadWithAnalysis(lead) {
  const analysis = analyzeReview(lead.badReview?.text, lead.business);
  return {
    ...lead,
    analysis,
  };
}
