/**
 * All 50 US states + DC. Each entry includes a dense metro for Maps search yield.
 * Query shape: "{category} in {city}, {state}"
 */

export const US_STATES = [
  { state: 'Alabama', city: 'Birmingham' },
  { state: 'Alaska', city: 'Anchorage' },
  { state: 'Arizona', city: 'Phoenix' },
  { state: 'Arkansas', city: 'Little Rock' },
  { state: 'California', city: 'Los Angeles' },
  { state: 'Colorado', city: 'Denver' },
  { state: 'Connecticut', city: 'Hartford' },
  { state: 'Delaware', city: 'Wilmington' },
  { state: 'Florida', city: 'Miami' },
  { state: 'Georgia', city: 'Atlanta' },
  { state: 'Hawaii', city: 'Honolulu' },
  { state: 'Idaho', city: 'Boise' },
  { state: 'Illinois', city: 'Chicago' },
  { state: 'Indiana', city: 'Indianapolis' },
  { state: 'Iowa', city: 'Des Moines' },
  { state: 'Kansas', city: 'Wichita' },
  { state: 'Kentucky', city: 'Louisville' },
  { state: 'Louisiana', city: 'New Orleans' },
  { state: 'Maine', city: 'Portland' },
  { state: 'Maryland', city: 'Baltimore' },
  { state: 'Massachusetts', city: 'Boston' },
  { state: 'Michigan', city: 'Detroit' },
  { state: 'Minnesota', city: 'Minneapolis' },
  { state: 'Mississippi', city: 'Jackson' },
  { state: 'Missouri', city: 'Kansas City' },
  { state: 'Montana', city: 'Billings' },
  { state: 'Nebraska', city: 'Omaha' },
  { state: 'Nevada', city: 'Las Vegas' },
  { state: 'New Hampshire', city: 'Manchester' },
  { state: 'New Jersey', city: 'Newark' },
  { state: 'New Mexico', city: 'Albuquerque' },
  { state: 'New York', city: 'New York City' },
  { state: 'North Carolina', city: 'Charlotte' },
  { state: 'North Dakota', city: 'Fargo' },
  { state: 'Ohio', city: 'Columbus' },
  { state: 'Oklahoma', city: 'Oklahoma City' },
  { state: 'Oregon', city: 'Portland' },
  { state: 'Pennsylvania', city: 'Philadelphia' },
  { state: 'Rhode Island', city: 'Providence' },
  { state: 'South Carolina', city: 'Charleston' },
  { state: 'South Dakota', city: 'Sioux Falls' },
  { state: 'Tennessee', city: 'Nashville' },
  { state: 'Texas', city: 'Houston' },
  { state: 'Utah', city: 'Salt Lake City' },
  { state: 'Vermont', city: 'Burlington' },
  { state: 'Virginia', city: 'Virginia Beach' },
  { state: 'Washington', city: 'Seattle' },
  { state: 'West Virginia', city: 'Charleston' },
  { state: 'Wisconsin', city: 'Milwaukee' },
  { state: 'Wyoming', city: 'Cheyenne' },
  { state: 'District of Columbia', city: 'Washington' },
];

export function locationQuery({ city, state }) {
  return `${city}, ${state}`;
}

/** Fisher–Yates shuffle (copy). */
export function shuffleStates(list = US_STATES) {
  const arr = [...list];
  for (let i = arr.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [arr[i], arr[j]] = [arr[j], arr[i]];
  }
  return arr;
}
