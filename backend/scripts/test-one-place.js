import { searchBusinesses } from '../src/scraper/googleMapsScraper.js';
import { filterRecentOneStarLeads } from '../src/services/reviewFilter.js';

const started = Date.now();
const businesses = await searchBusinesses('Dentist', 'New York', {
  maxResults: 3,
  onProgress: (m) => console.log(`[${Math.round((Date.now() - started) / 1000)}s]`, m),
});

console.log('businesses', businesses.length);
for (const b of businesses) {
  console.log('-', b.name, '| 1★:', b.reviews?.length, '| rating:', b.rating);
  if (b.reviews?.[0]) {
    console.log('  ', b.reviews[0].date, '|', b.reviews[0].text?.slice(0, 90));
  }
}
const leads = filterRecentOneStarLeads(businesses, { dateRange: '365' });
console.log('LEADS (365d):', leads.length);
console.log(JSON.stringify(leads.slice(0, 2), null, 2));
