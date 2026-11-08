# Architecture and Design Choices

## State-to-interface flow

| State | Input | Update | Rendering |
|---|---|---|---|
| Theme | button, system preference changes | optional explicit choice overrides system, optional persistence | `data-theme`, button name and pressed state |
| Menu | click, Escape, link, viewport width | open state | `aria-expanded`, visible class, focus |
| Projects | initial request, retry, filter | response list and selected language | loading/error/empty notices, cards, retry |
| Form | input, blur, submit | field validity | adjacent error, `aria-invalid`, result notice |
| Scroll | viewport movement | position conditions and intersection state | header surface, top button, reveal class |

## Dependency and ownership contract

```text
app.js (composition)
  ├── data/ ──→ domain/
  └── ui/   ──→ domain/
```

`domain/` owns plain-value validation, repository normalization/selection, and theme preference rules. These modules
must import without a DOM, storage, network, media query, or feature initialization. Their Node tests
exercise actual input/output values rather than installing browser globals to make the rules work.

`data/` owns the GitHub transport, deadline, response decoding, expected request failures, and browser
preference storage/observation. It may
call domain parsing, but never imports a view. `ui/` owns authored markup, event binding, rendering,
focus, ARIA, and observer lifetimes. It receives request operations from `app.js`; a view cannot
import an HTTP adapter. Known request failures become UI states, while broken authored DOM contracts
and unexpected programming errors are not silently converted into apparently valid empty results.

A feature capsule containing HTTP, validation, and DOM code offers locality but obscures these
independently changing decisions. A generic store/controller/service framework adds indirection
without hiding useful complexity here. The chosen interfaces keep the normal call chains short:
contact event to rule to rendering, or load/retry to request adapter to parsed result to rendering.

HTML owns the base content and semantic structure. Template strings contain developer-authored markup
only; API values enter the document as text. The page needs neither a state-management library nor
a general component framework.

### Intended module ownership

This is the stable responsibility contract, not a revision-specific review report. Independent
reviewers must discover the current runtime, examine every module/caller, and produce their own
coverage and separate functionality/architecture verdicts under the root quality standard.

| Module | Owned decisions / mechanics | I/O and resources | State authority / projection | Expected proof |
|---|---|---|---|---|
| `app.js` | Startup and dependency composition; no feature rules | Creates adapters and initializes page-lifetime features | No feature state | Import graph, packaged runtime, browser startup/fault fallback |
| `domain/contact.js` | Field membership, required text, email acceptance | None | Plain input values and issue codes | Node contact rules and native-input browser comparison |
| `domain/projects.js` | Neutral candidate acceptance/normalization, destinations, forks, intake budget, recency ranking, display cap, language selection | None; URL and numeric-instant validation only | Plain candidates with epoch-millisecond update times; selected values, not wire records or DOM | Node candidate/shuffled-order cases and browser selection/content-safety cases |
| `domain/project-load.js` | Shared expected load-failure categories | None | Typed failure contract, no UI state | Adapter classification and browser error/retry scenarios |
| `domain/theme.js` | Choice parsing, initial precedence, toggle, explicit choice versus system changes | None | Immutable theme/explicit-choice values | Node theme transitions without DOM or storage |
| `data/github.js` | Fixed request protocol, JSON/field/timestamp decoding and expected failure translation | Fetch, body lifetime, timer, abort controller; lazy candidate decoder | Request/deadline state and neutral inputs; API sort is acquisition optimization, not ranking authority | Wire mapping/types/budget, native streaming, timeout and injected-error tests |
| `data/theme-preferences.js` | Stored-value and native media-event adaptation; known storage-failure handling | `localStorage`, media subscription and its disposer | Initial input snapshot and observed external values; no preference precedence | Denied/quota storage and native subscription-disposal browser cases |
| `ui/theme.js` | Event orchestration, DOM/ARIA/label/metadata projection, readiness and disposal | Injected preference port; DOM and computed style | Holds pure policy state; never derives the next theme from rendered attributes | Full-page theme behavior, metadata, persistence, storage failure and disposal cases |
| `ui/contact.js` | Validation timing, issue wording, error/status display, focus | DOM fields/events; no message transport | Native field values and validation-display markers, not validation rules | Blur/edit/submit, first-invalid focus, no-network success and accessibility cases |
| `ui/projects.js` | Authored cards, UTC presentation, notices, pending controls, retry focus, reveal lifetime | Injected loader and reveal initializer; DOM | Parsed repositories/rejected count in closure; native filter value and focus | Loading/filter/retry/empty/content-safety and focus/observer cases |
| `ui/navigation.js` | Menu, destination/escape focus, viewport visibility, motion-aware scrolling | DOM, scroll and layout media events; page lifetime | Native `aria-expanded` menu state; classes/labels project that UI state | Keyboard/mobile/scroll and initialization-fallback cases |
| `ui/reveals.js` | Enrollment, one-shot reveal threshold and reduced-motion presentation | DOM, intersection observer and disposer | Observed node visibility; no business or preference precedence | Normal/reduced motion, observer cleanup and failure visibility |
| `ui/elements.js` | Authored DOM element contract | DOM lookup | No feature state | Checked element use and authored-markup/failure scenarios |

The contact form's validation-display flags and navigation's expanded state may remain native UI
state because they describe that view's own interaction mechanics. Scroll thresholds, responsive
queries and reveal enrollment similarly belong to a rendering lifecycle, not an independent
selection policy. Their browser execution is intentional; extracting a pure helper for each
comparison would not separate a changing responsibility. Theme precedence is different: it remains
meaningful with another renderer or storage mechanism and therefore has a plain-value owner.

## CSS ownership

`base.css` is a neutral reset: no project token references, feature classes, or imports. Tokens own
theme values. The themed foundation owns document typography, colors, and focus treatment; reusable
presentation, feature components, and page composition are separate from that reset.

Reveal motion owns entrance opacity and translation, not a component's hover transform or transition
list. A revealed project card must retain its border transition and four-pixel hover/focus lift.
Reduced motion keeps that card stationary. These combined states are checked through computed
browser styles, not by searching CSS for a declaration that might lose the cascade.

The theme policy keeps the resolved theme and whether the choice is explicit in an immutable value.
Until a choice exists, system preference changes update that value. The browser adapter supplies
stored/system inputs and best-effort persistence; a denied or quota-exceeded write must not make a
later system change override an in-memory choice. The UI projects the policy value into the DOM;
computed canvas color is read only to update browser theme metadata, not to choose the next theme.
Theme initialization returns a disposer that releases its native subscription and click handler and
hides the unavailable control. The composition root retains the normal static page lifetime.

Reveal observers own the nodes passed to them. `initReveals()` returns a disposer, and the project
list calls it before replacing cards or starting another load. Static sections live for the page's
lifetime; dynamically replaced cards do not leave detached nodes under observation.
Only successfully observed nodes receive the pending reveal class. Disposing an observer removes
that pending state; feature-initialization failures do not globally conceal the static page.

## Asynchronous behavior and failure

Because `fetch` does not reject HTTP error status codes, the adapter checks `response.ok`. It owns
the JSON array/field contract, including `html_url`, `updated_at`, primitive/null types, and wire
timestamp parsing. It supplies neutral candidates with `url` and epoch-millisecond `updatedAt`
values, or an invalid-record marker. A lazy iterator lets the domain's single 100-input budget stop
decoding before a later wire record is inspected; the adapter does not duplicate that budget.

The domain owns semantic acceptance and normalization. Names cannot be blank; destinations must use
the HTTPS GitHub origin without embedded credentials, and numeric update instants must be valid.
Blank optional metadata uses readable defaults. Accepted non-forks are ranked by update instant,
newest first, before applying the 12-card cap. Equal update instants retain their input order to
preserve the existing tie behavior. The API's `sort=updated` helps obtain a recent bounded sample;
it is not the selection rule's authority. Dates are displayed in UTC, so month boundaries do not
depend on the visitor's timezone.

Forks are excluded before selecting up to 12 cards. Invalid entries are excluded with a visible
count rather than silently presenting an incomplete result. A response with no cards and rejected
entries is an error with retry, not an apparently empty account. An empty response or a valid
fork-only response is an empty state. Language filtering applies only to the selected candidates
and retains the invalid-entry notice.

An `AbortController` enforces the request deadline. Its timer is cleared and its signal aborted in
`finally`, including non-OK responses whose streaming body has not been consumed. Native fetch and JSON
decoding classify their own expected failures. The injectable request operation returns decoded
provider JSON, not a `Response`; its implementation errors propagate unchanged instead of being
guessed from a broad `TypeError` catch. The GitHub boundary decodes the wire representation before
the plain-value selection rule executes.

Retry focuses the loading status before hiding its trigger. Completion moves focus to the enabled
filter or the restored retry button only while the status still holds focus; an empty result leaves
the notice focused, and a visitor who moved elsewhere is not interrupted.

The account is configured in the GitHub adapter under `js/data/` and the
profile link in `index.html`; changing it also requires updating the synthetic fixture route and
associated tests. Tests require no authentication token.

## Accessibility and progressive enhancement

Semantic elements, native input types, accessible names, and explicit labels take precedence over
custom behavior. Errors use text as well as color, and a failed submission focuses the first invalid
field. Without JavaScript, page content and links remain available while live projects display an
explanation and form submission stays disabled.

Each enhancement owns its readiness. Navigation collapses only after its listeners are installed;
until then, compact header links remain usable even if an earlier feature fails. The theme button
begins hidden and is revealed only after its initial state and preference/click listeners are ready.

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

## Verification boundaries

The verifier runs readable-source formatting, linting, and strict JSDoc-backed `checkJs` before the
Node and browser suites. Runtime JavaScript remains JavaScript; TypeScript and Biome are test-only
tools and do not ship with the static site. Import-graph checks enforce the dependency directions
above without fixing an exact internal module inventory.

Node tests execute contact, repository, and theme rules with ordinary values. A fresh Node process
also imports every discovered domain module with browser capabilities poisoned. Import checks cover
static imports, re-exports and literal dynamic imports and reject opaque module edges; global-symbol
checks distinguish local declarations from environmental I/O. These checks support, but do not
replace, semantic review of rules hidden inside otherwise allowed UI modules. Browser tests preserve
the real form, network, keyboard, theme, layout, and content-safety contracts. Normal-motion tests
separately verify composed entrance/hover/focus behavior; reduced-motion screenshots alone cannot
establish that it works. Packaging checks compare the complete nested runtime trees so a new module
cannot be omitted from Pages while still passing a local source test.

## Images and privacy

`images/profile-notes.svg` is original line art created for this site, not a photograph of a real
person. The site includes no external fonts, tracking scripts, or analytics. In normal operation, the
only remote request is the browser's public GitHub API query. Contact-form content never leaves the
page.
