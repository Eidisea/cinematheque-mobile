// Staff accounts (Phase 9). Only active staff may manage them, through the server: a
// Firebase Auth account (email + password) plus its staff/{uid} record. AVT and PDO have
// the same access; the position is descriptive. Deactivating disables sign-in AND the
// record, so the staff app signs that person out at once.

import { Timestamp } from 'firebase-admin/firestore';

export class StaffAccountError extends Error {
  /** @param {'validation'|'not_found'|'self'} code */
  constructor(code, fields = {}) {
    super(code);
    this.name = 'StaffAccountError';
    this.code = code;
    this.fields = fields;
  }
}

const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const POSITIONS = ['AVT', 'PDO'];

/** Checks and tidies the form. [creating] makes the password required. */
export function validateStaffAccount(input, { creating }) {
  const errors = {};
  const text = (v) => (typeof v === 'string' ? v.trim() : '');
  const value = {
    firstName: text(input.firstName),
    middleName: text(input.middleName) || null,
    lastName: text(input.lastName),
    email: text(input.email).toLowerCase(),
    position: text(input.position).toUpperCase(),
    password: typeof input.password === 'string' && input.password !== '' ? input.password : null,
  };
  if (!value.firstName || value.firstName.length > 50) errors.firstName = 'Enter a first name (up to 50 characters).';
  if (value.middleName && value.middleName.length > 50) errors.middleName = 'Use at most 50 characters.';
  if (!value.lastName || value.lastName.length > 50) errors.lastName = 'Enter a last name (up to 50 characters).';
  if (!EMAIL.test(value.email) || value.email.length > 100) errors.email = 'Enter a valid email address.';
  if (!POSITIONS.includes(value.position)) errors.position = 'Choose AVT or PDO.';
  if (creating && !value.password) errors.password = 'Enter a password of at least 8 characters.';
  if (value.password && (value.password.length < 8 || value.password.length > 128)) {
    errors.password = 'Use at least 8 characters.';
  }
  return { value, errors };
}

const displayName = (v) => `${v.firstName} ${v.lastName}`;

export async function createStaffAccount(db, auth, input, { now = new Date() } = {}) {
  const { value, errors } = validateStaffAccount(input, { creating: true });
  if (Object.keys(errors).length) throw new StaffAccountError('validation', errors);
  const uid = await auth.createUser({ email: value.email, password: value.password, displayName: displayName(value) });
  await db.collection('staff').doc(uid).set({
    firstName: value.firstName,
    middleName: value.middleName,
    lastName: value.lastName,
    email: value.email,
    position: value.position,
    isActive: true,
    createdAt: Timestamp.fromDate(now),
  });
  return { uid };
}

/** Name, email, position, and optionally a new password. */
export async function updateStaffAccount(db, auth, uid, input) {
  const ref = db.collection('staff').doc(uid);
  if (!(await ref.get()).exists) throw new StaffAccountError('not_found');
  const { value, errors } = validateStaffAccount(input, { creating: false });
  if (Object.keys(errors).length) throw new StaffAccountError('validation', errors);
  await auth.updateUser(uid, {
    email: value.email,
    displayName: displayName(value),
    ...(value.password ? { password: value.password } : {}),
  });
  await ref.update({
    firstName: value.firstName,
    middleName: value.middleName,
    lastName: value.lastName,
    email: value.email,
    position: value.position,
  });
  return { uid };
}

/** Turns sign-in on or off. Staff cannot deactivate themselves (no locking everyone out). */
export async function setStaffActive(db, auth, uid, active, { by }) {
  if (uid === by && !active) throw new StaffAccountError('self');
  const ref = db.collection('staff').doc(uid);
  if (!(await ref.get()).exists) throw new StaffAccountError('not_found');
  await auth.updateUser(uid, { disabled: !active });
  await ref.update({ isActive: active });
  return { uid, isActive: active };
}
