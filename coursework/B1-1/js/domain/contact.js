export const CONTACT_FIELDS = /** @type {const} */ (["name", "email", "message"]);
/** @typedef {(typeof CONTACT_FIELDS)[number]} ContactField */
/** @typedef {"required" | "email-format" | null} ContactIssue */

// HTML email syntax permits local domains such as a@b; a dotted domain is not required.
const EMAIL_PATTERN =
  /^[\w.!#$%&'*+/=?^`{|}~-]+@[a-z\d](?:[a-z\d-]{0,61}[a-z\d])?(?:\.[a-z\d](?:[a-z\d-]{0,61}[a-z\d])?)*$/i;

/** @param {ContactField} field @param {string} value @returns {ContactIssue} */
export function contactFieldError(field, value) {
  if (!CONTACT_FIELDS.includes(field)) throw new TypeError(`Unknown contact field: ${field}`);
  const trimmed = value.trim();
  if (!trimmed) return "required";
  if (field === "email" && !EMAIL_PATTERN.test(trimmed)) return "email-format";
  return null;
}
