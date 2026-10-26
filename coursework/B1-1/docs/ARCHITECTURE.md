# Architecture and Design Choices

## State-to-interface flow

| State | Input | Update | Rendering |
|---|---|---|---|
| Theme | button, system preference changes | optional explicit choice overrides system, optional persistence | `data-theme`, button name and pressed state |
| Menu | click, Escape, link, viewport width | open state | `aria-expanded`, visible class, focus |
| Projects | initial request, retry, filter | response list and selected language | loading/error/empty notices, cards, retry |
| Form | input, blur, submit | field validity | adjacent error, `aria-invalid`, result notice |
| Scroll | viewport movement | position conditions and intersection state | header surface, top button, reveal class |

`js/app.js` initializes each feature, and every module updates only the DOM it owns. This small page
does not need a state-management library or general component layer. HTML owns the base content and
semantic structure; JavaScript adds interaction. Template strings contain developer-authored markup
only, while API values enter the document as text.

The theme module keeps an explicit choice in memory as well as attempting to persist it. Until a
choice exists, system preference changes update the page. A denied storage write must not make a
later system change override a choice the visitor just made.

Reveal observers own the nodes passed to them. `initReveals()` returns a disposer, and the project
list calls it before replacing cards or starting another load. Static sections live for the page's
lifetime; dynamically replaced cards do not leave detached nodes under observation.

## Asynchronous behavior and failure

Because `fetch` does not reject HTTP error status codes, the project checks `response.ok`. It then
validates that JSON is an array and parses at most its first 100 entries. Each item's strings,
booleans, URL, and date must have acceptable shapes. Names cannot be blank; destinations must use
the HTTPS GitHub origin without embedded credentials. Blank optional metadata uses readable
defaults. Dates are displayed in UTC, so month boundaries do not depend on the visitor's timezone.

Forks are excluded before selecting up to 12 cards. Invalid entries are excluded with a visible
count rather than silently presenting an incomplete result. A response with no cards and rejected
entries is an error with retry, not an apparently empty account. An empty response or a valid
fork-only response is an empty state. Language filtering applies only to the selected candidates
and retains the invalid-entry notice.

An `AbortController` enforces the request deadline. Its timer is cleared in `finally`, and the error
state provides a retry action. The account is configured in the API URL in `js/projects.js` and the
profile link in `index.html`; changing it also requires updating the synthetic fixture route and
associated tests. Tests require no authentication token.

## Accessibility and progressive enhancement

Semantic elements, native input types, accessible names, and explicit labels take precedence over
custom behavior. Errors use text as well as color, and a failed submission focuses the first invalid
field. Without JavaScript, page content and links remain available while live projects display an
explanation and form submission stays disabled.

Fields are first validated on blur or submit. Once validated, every edit revalidates the field,
including edits that turn a valid value into an invalid one. Both the inline error and
`aria-invalid` reflect the current value; editing also clears the previous submission summary.

Reduced-motion preferences remove unnecessary animation. Component display rules preserve the native
`hidden` attribute contract. Automated axe checks cover only part of accessibility: screen-reader
announcements, practical zoom behavior, touch interaction, and content comprehension still require
human review.

## Isolation and reproducibility

- The application is static and does not depend on the monorepo root or a generated bundle.
- The static server runs non-root with a read-only root filesystem and no added capabilities.
- The test browser also runs non-root and accesses only the trusted local page and synthetic data on
  the verification network.
- The default Compose network is internal. Only the preview overlay publishes a host port.
- The VM uses its own Linux kernel under QEMU TCG without expanding host privileges.
- npm lockfile and image-digest updates should be made together with the relevant Docker and VM test
  updates. A disappeared pinned Alpine package should fail the build rather than silently select a
  newer version. Pinning is not a substitute for planned security updates.

## Images and privacy

`images/profile-notes.svg` is original line art created for this site, not a photograph of a real
person. The site includes no external fonts, tracking scripts, or analytics. In normal operation, the
only remote request is the browser's public GitHub API query. Contact-form content never leaves the
page.
