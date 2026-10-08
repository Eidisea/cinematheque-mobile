// Server-side validation of the reservation form. The app checks the same things for a
// friendly experience, but THIS is what counts: anything can be sent to an API.
// Only known fields are kept; text is trimmed; empty optional text becomes null.

import { MAX_SEATS_PER_RESERVATION, SEAT_LABEL_PATTERN } from './booking-rules.js';

const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;

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

/**
 * Philippine mobile number → "+639XXXXXXXXX". The app sends "+63" and the 10 digits after it;
 * 09XXXXXXXXX, 639…, spaces and dashes are accepted too.
 */
function mobile(errors, field, value) {
  const raw = typeof value === 'string' ? value.replace(/[\s\-().]/g, '') : '';
  if (!raw) {
    errors[field] = 'This field is required.';
    return null;
  }
  const m = /^(?:\+?63|0)?(9\d{9})$/.exec(raw);
  if (!m) {
    errors[field] = 'Enter a mobile number: +63 and 10 digits starting with 9.';
    return null;
  }
  return `+63${m[1]}`;
}

function person(errors, prefix, p, { bookerFields }) {
  const o = p && typeof p === 'object' ? p : {};
  const out = {
    firstName: text(errors, `${prefix}.firstName`, o.firstName, { required: true, max: 50 }),
    middleName: text(errors, `${prefix}.middleName`, o.middleName, { max: 50 }),
    lastName: text(errors, `${prefix}.lastName`, o.lastName, { required: true, max: 50 }),
  };
  if (bookerFields) {
    out.contactNo = mobile(errors, `${prefix}.contactNo`, o.contactNo);
    out.email = text(errors, `${prefix}.email`, o.email, {
      required: true, max: 100, pattern: EMAIL, message: 'Enter a valid email address.',
    });
    return out;
  }

  // Attendee (logsheet) details: every moviegoer gives them. Only the middle name, the
  // senior citizen card number and PWD are optional.
  let age = null;
  if (o.age === undefined || o.age === null || o.age === '') errors[`${prefix}.age`] = 'This field is required.';
  else if (Number.isInteger(o.age) && o.age >= 0 && o.age <= 120) age = o.age;
  else errors[`${prefix}.age`] = 'Enter an age from 0 to 120.';
  let sex = null;
  if (o.sex === undefined || o.sex === null || o.sex === '') errors[`${prefix}.sex`] = 'This field is required.';
  else if (o.sex === 'M' || o.sex === 'F') sex = o.sex;
  else errors[`${prefix}.sex`] = 'Invalid value.';
  if (o.isPwd !== undefined && o.isPwd !== null && typeof o.isPwd !== 'boolean') errors[`${prefix}.isPwd`] = 'Invalid value.';

  return {
    ...out,
    age,
    sex,
    companySchool: text(errors, `${prefix}.companySchool`, o.companySchool, { required: true, max: 150 }),
    contactNo: mobile(errors, `${prefix}.contactNo`, o.contactNo),
    email: text(errors, `${prefix}.email`, o.email, {
      required: true, max: 100, pattern: EMAIL, message: 'Enter a valid email address.',
    }),
    seniorCardNo: text(errors, `${prefix}.seniorCardNo`, o.seniorCardNo, { max: 30 }),
    isPwd: o.isPwd === true,
  };
}

/**
 * Body: { screeningId, seats: ["A1", …], bookerSeat?: "A1",
 *         booker: { firstName, middleName?, lastName, contactNo, email },
 *         attendees: { "A1": { firstName, middleName?, lastName, age, sex, companySchool,
 *                              contactNo, email, seniorCardNo?, isPwd? }, … } }
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
