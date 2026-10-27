/**
 * @template {Element} T
 * @param {ParentNode} root
 * @param {string} selector
 * @param {new () => T} expected
 * @returns {T}
 */
export function requiredElement(root, selector, expected) {
  const element = root.querySelector(selector);
  if (!(element instanceof expected)) {
    throw new TypeError(`Required authored element is missing or has the wrong kind: ${selector}`);
  }
  return element;
}
