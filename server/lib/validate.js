// Server-side validation of the reservation form. The app checks the same things for a
// friendly experience, but THIS is what counts: anything can be sent to an API.
// Only known fields are kept; text is trimmed; empty optional text becomes null.

import { MAX_SEATS_PER_RESERVATION, SEAT_LABEL_PATTERN } from './booking-rules.js';

const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;
const PHONE = /^[0-9+()\-\s]{7,20}$/;

function text(errors, field, value, { required = false, max, pattern, message } = {}) {
  const v = typeof value === 'string' ? value.trim() : value == null ? '' : null;
  if (v === null) {
    errors[field] = 'Invalid value.';
    return null;
  }
  if (!v) {
    if (required) errors[field] = 'This field is required.';
    return null;
  }
  if (max && v.length > max) {
    errors[field] = `Use at most ${max} characters.`;
    return null;
  }
  if (pattern && !pattern.test(v)) {
    errors[field] = message ?? 'Invalid format.';
    return null;
  }
  return v;
}

function person(errors, prefix, p, { bookerFields }) {
  const o = p && typeof p === 'object' ? p : {};
  const out = {
    firstName: text(errors, `${prefix}.firstName`, o.firstName, { required: true, max: 50 }),
    middleName: text(errors, `${prefix}.middleName`, o.middleName, { max: 50 }),
    lastName: text(errors, `${prefix}.lastName`, o.lastName, { required: true, max: 50 }),
  };
  if (bookerFields) {
    out.contactNo = text(errors, `${prefix}.contactNo`, o.contactNo, {
      required: true, max: 20, pattern: PHONE, message: 'Enter a valid contact number.',
    });
    out.email = text(errors, `${prefix}.email`, o.email, {
      required: true, max: 100, pattern: EMAIL, message: 'Enter a valid email address.',
    });
    return out;
  }

  // Attendee (logsheet) details — all optional except the name.
  let age = null;
  if (o.age !== undefined && o.age !== null && o.age !== '') {
    if (Number.isInteger(o.age) && o.age >= 0 && o.age <= 120) age = o.age;
    else errors[`${prefix}.age`] = 'Enter an age from 0 to 120.';
  }
  let sex = null;
  if (o.sex !== undefined && o.sex !== null && o.sex !== '') {
    if (o.sex === 'M' || o.sex === 'F') sex = o.sex;
    else errors[`${prefix}.sex`] = 'Invalid value.';
  }
  if (o.isPwd !== undefined && o.isPwd !== null && typeof o.isPwd !== 'boolean') errors[`${prefix}.isPwd`] = 'Invalid value.';

  return {
    ...out,
    age,
    sex,
    companySchool: text(errors, `${prefix}.companySchool`, o.companySchool, { max: 150 }),
    contactNo: text(errors, `${prefix}.contactNo`, o.contactNo, { max: 20, pattern: PHONE, message: 'Enter a valid contact number.' }),
    email: text(errors, `${prefix}.email`, o.email, { max: 100, pattern: EMAIL, message: 'Enter a valid email address.' }),
    seniorCardNo: text(errors, `${prefix}.seniorCardNo`, o.seniorCardNo, { max: 30 }),
    isPwd: o.isPwd === true,
  };
}

/**
 * Body: { screeningId, seats: ["A1", …], bookerSeat?: "A1",
 *         booker: { firstName, middleName?, lastName, contactNo, email },
 *         attendees: { "A1": { firstName, middleName?, lastName, age?, sex?, companySchool?,
 *                              contactNo?, email?, seniorCardNo?, isPwd? }, … } }
 * Returns { value, errors } — errors is empty when valid.
 */
export function validateCreateReservation(body) {
  const errors = {};
  const b = body && typeof body === 'object' ? body : {};

  const screeningId = text(errors, 'screeningId', b.screeningId, { required: true, max: 100 });

  let seats = [];
  if (!Array.isArray(b.seats) || b.seats.length === 0) {
    errors.seats = 'Choose at least one seat.';
  } else if (b.seats.length > MAX_SEATS_PER_RESERVATION) {
    errors.seats = `Choose at most ${MAX_SEATS_PER_RESERVATION} seats.`;
  } else if (b.seats.some((s) => typeof s !== 'string' || !SEAT_LABEL_PATTERN.test(s))) {
    errors.seats = 'Invalid seat.';
  } else if (new Set(b.seats).size !== b.seats.length) {
    errors.seats = 'A seat was chosen twice.';
  } else {
    seats = [...b.seats];
  }

  const booker = person(errors, 'booker', b.booker, { bookerFields: true });

  let bookerSeat = null;
  if (b.bookerSeat !== undefined && b.bookerSeat !== null && b.bookerSeat !== '') {
    if (seats.includes(b.bookerSeat)) bookerSeat = b.bookerSeat;
    else errors.bookerSeat = 'Choose one of your selected seats.';
  }

  // Exactly one declared attendee per selected seat.
  const attendees = {};
  const given = b.attendees && typeof b.attendees === 'object' && !Array.isArray(b.attendees) ? b.attendees : {};
  const extra = Object.keys(given).filter((k) => !seats.includes(k));
  if (extra.length) errors.attendees = 'Every attendee must belong to a selected seat.';
  for (const seat of seats) {
    if (!given[seat]) errors[`attendees.${seat}`] = 'Enter the details of the person using this seat.';
    attendees[seat] = person(errors, `attendees.${seat}`, given[seat], { bookerFields: false });
  }

  return { value: { screeningId, seats, bookerSeat, booker, attendees }, errors };
}
