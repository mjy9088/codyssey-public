const fields = {
  name: { input: "#field-name", error: "#error-name", empty: "Please enter your name." },
  email: { input: "#field-email", error: "#error-email", empty: "Please enter your email." },
  message: { input: "#field-message", error: "#error-message", empty: "Please add a short message." },
};

const getElements = (config) => {
  const input = document.querySelector(config.input);
  const error = document.querySelector(config.error);
  return input instanceof HTMLElement && error instanceof HTMLElement ? { input, error } : null;
};

const validate = (name, entry) => {
  const value = entry.input instanceof HTMLInputElement || entry.input instanceof HTMLTextAreaElement ? entry.input.value.trim() : "";
  let message = value ? "" : fields[name].empty;
  if (!message && name === "email" && entry.input instanceof HTMLInputElement && !entry.input.validity.valid) message = "Enter an email in the form name@example.com.";
  entry.error.textContent = message;
  entry.input.setAttribute("aria-invalid", String(Boolean(message)));
  return !message;
};

export const initContactForm = () => {
  const form = document.querySelector("#contact-form");
  const status = document.querySelector("#form-status");
  const submit = form?.querySelector('button[type="submit"]');
  if (!(form instanceof HTMLFormElement) || !(status instanceof HTMLElement) || !(submit instanceof HTMLButtonElement)) return;
  const entries = Object.fromEntries(Object.entries(fields).map(([name, config]) => [name, getElements(config)]));
  if (Object.values(entries).some((entry) => !entry)) return;
  submit.disabled = false;

  Object.entries(entries).forEach(([name, entry]) => {
    if (!entry) return;
    entry.input.addEventListener("input", () => {
      if (entry.input.getAttribute("aria-invalid") === "true") validate(name, entry);
      status.textContent = "";
    });
    entry.input.addEventListener("blur", () => validate(name, entry));
  });

  form.addEventListener("submit", (event) => {
    event.preventDefault();
    const results = Object.entries(entries).map(([name, entry]) => entry ? validate(name, entry) : false);
    if (results.every(Boolean)) {
      status.textContent = "Your note is complete. This portfolio does not send messages, so nothing was submitted.";
      return;
    }
    status.textContent = "Please correct the marked fields.";
    const firstInvalid = form.querySelector('[aria-invalid="true"]');
    if (firstInvalid instanceof HTMLElement) firstInvalid.focus();
  });
};
