/**
 * The Google Maps place id inside a place link (`!1s0x...:0x...`), which is the
 * same for the same business whichever search listed it. Null if there is none.
 */
export function placeIdFromHref(href) {
  const m = String(href || '').match(/!1s(0x[0-9a-f]+:0x[0-9a-f]+)/i);
  return m ? m[1].toLowerCase() : null;
}
