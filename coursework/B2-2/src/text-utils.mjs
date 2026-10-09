export function slug(text) {
  return text.normalize("NFKD").replace(/\p{M}/gu, "").toLowerCase()
    .replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");
}

export function compactWhitespace(text) {
  return text.trim().replace(/\s+/gu, " ");
}

export function initials(name) {
  return compactWhitespace(name).split(" ").filter(Boolean)
    .map((part) => [...part][0].toLocaleUpperCase("en-US")).join("");
}
