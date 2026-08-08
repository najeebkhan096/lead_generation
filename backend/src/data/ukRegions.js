/**
 * UK regions (9 English regions + Scotland, Wales, Northern Ireland).
 * Each entry includes a dense city for Maps search yield.
 * Query shape: "{category} in {city}, {state}"
 */

export const UK_REGIONS = [
  { state: 'London', city: 'London' },
  { state: 'South East England', city: 'Brighton' },
  { state: 'South West England', city: 'Bristol' },
  { state: 'East of England', city: 'Cambridge' },
  { state: 'East Midlands', city: 'Nottingham' },
  { state: 'West Midlands', city: 'Birmingham' },
  { state: 'Yorkshire and the Humber', city: 'Leeds' },
  { state: 'North West England', city: 'Manchester' },
  { state: 'North East England', city: 'Newcastle upon Tyne' },
  { state: 'Scotland', city: 'Glasgow' },
  { state: 'Wales', city: 'Cardiff' },
  { state: 'Northern Ireland', city: 'Belfast' },
];
