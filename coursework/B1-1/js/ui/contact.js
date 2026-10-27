import { CONTACT_FIELDS, contactFieldError } from "../domain/contact.js";
import { requiredElement } from "./elements.js";

/** @typedef {import("../domain/contact.js").ContactField} ContactField */
/** @satisfies {Record<ContactField, string>} */
const REQUIRED_MESSAGES = {
  name: "Please enter your name.",
  email: "Please enter your email.",
  message: "Please add a short message.",
};

/**
 * @typedef {object} ContactEntry
 * @property {ContactField} name
 * @property {HTMLInputElement | HTMLTextAreaElement} input
 * @property {HTMLElement} error
 */

/** @param {ContactEntry} entry */
function validateEntry(entry) {
  const issue = contactFieldError(entry.name, entry.input.value);
  const messages = {
    required: REQUIRED_MESSAGES[entry.name],
    "email-format": "Enter an email in the form name@example.com.",
  };
  entry.error.textContent = issue === null ? "" : messages[issue];
  entry.input.setAttribute("aria-invalid", String(issue !== null));
  return issue === null;
}

export function initContactForm() {
  const form = requiredElement(document, "#contact-form", HTMLFormElement);
  const status = requiredElement(document, "#form-status", HTMLElement);
  const submit = requiredElement(form, 'button[type="submit"]', HTMLButtonElement);
  const entries = CONTACT_FIELDS.map((name) => {
    const selector = `#field-${name}`;
    return {
      name,
      input:
        name === "message"
          ? requiredElement(form, selector, HTMLTextAreaElement)
          : requiredElement(form, selector, HTMLInputElement),
      error: requiredElement(form, `#error-${name}`, HTMLElement),
    };
  });
  submit.disabled = false;

  for (const entry of entries) {
    entry.input.addEventListener("input", () => {
      if (entry.input.hasAttribute("aria-invalid")) validateEntry(entry);
      status.textContent = "";
      delete status.dataset.state;
    });
    entry.input.addEventListener("blur", () => validateEntry(entry));
  }

  form.addEventListener("submit", (event) => {
    event.preventDefault();
    const results = entries.map(validateEntry);
    if (results.every(Boolean)) {
      status.dataset.state = "success";
      status.textContent =
        "Your note is complete. This portfolio does not send messages, so nothing was submitted.";
      return;
    }
    status.dataset.state = "error";
    status.textContent = "Please correct the marked fields.";
    entries.find(({ input }) => input.getAttribute("aria-invalid") === "true")?.input.focus();
  });
}
