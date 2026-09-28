import { randomBytes, randomInt } from 'node:crypto';

// No 0/O, 1/I/L: easy to read aloud at the door and to type.
const REFERENCE_ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

/** e.g. "CCD-7KQ2M9XA" — 31^8 ≈ 850 billion combinations, cryptographically random. */
export function newBookingReference() {
  let code = '';
  for (let i = 0; i < 8; i++) code += REFERENCE_ALPHABET[randomInt(REFERENCE_ALPHABET.length)];
  return `CCD-${code}`;
}

/** Long secret that lets ONE phone read ONE booking view. Never shown to people. */
export function newAccessKey() {
  return randomBytes(32).toString('base64url');
}

/** Accepts "ccd-7kq2m9xa", " CCD-7KQ2M9XA ", "CCD 7KQ2M9XA" … → "CCD-7KQ2M9XA", or null. */
export function normalizeBookingReference(input) {
  if (typeof input !== 'string') return null;
  const compact = input.trim().toUpperCase().replace(/[\s-]/g, '');
  const code = compact.startsWith('CCD') ? compact.slice(3) : compact;
  if (code.length !== 8 || [...code].some((c) => !REFERENCE_ALPHABET.includes(c))) return null;
  return `CCD-${code}`;
}
