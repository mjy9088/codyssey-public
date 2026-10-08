# Peer Review Guide

## 1. Confirm the submission boundary

Copy only the submission directory to an arbitrary location without consulting the parent monorepo.
Confirm that it contains `index.html`, `css`, `js`, `images`, and the verification configuration. The
following command should require no `.git`, assignment source, DIM configuration, personal
credentials, host Node.js, or host QEMU installation:

```sh
sh scripts/verify.sh all
```

Review the named assertions and behavior covered by the suite rather than treating a summary count
as sufficient evidence. Runtime logs, results, traces, and incidental screenshots should remain
ignored locally or be retained as CI artifacts, not committed as recurring reports.

## 2. Evaluate as a user

| Area | Action | Expected behavior |
|---|---|---|
| Small screen | At 375px, open the menu, press Escape, and select an item | expanded state, focus, and navigation agree |
| Breakpoint | Widen an open menu beyond 768px | the unnecessary menu button disappears |
| Keyboard | Use menu, theme, and form with Tab and Enter | focus is visible and order is meaningful |
| Theme | Toggle and reload | preference persists; blocked storage does not break the page |
| Navigation | Use the Projects anchor and back-to-top control | the header does not cover the target heading |
| Request state | Exercise success, 403, empty, malformed, offline, and delayed responses | distinct notices and retry behavior appear |
| Data safety | Supply markup-like names and long descriptions | text remains literal and layout remains usable |
| Form | Try blank, whitespace, malformed email, and valid values | field errors and honest local success are clear |
| Privacy | Submit valid input while viewing Network tools | name, email, and message are not transmitted |
| Accessibility | Inspect zoom, dark theme, and reduced motion | content remains readable without unnecessary motion |
| No JavaScript | Disable browser JavaScript | content/navigation remain; form submission is disabled |

Limit live GitHub API requests. Reproduce failure states with the synthetic test responses, and do
not interpret fixture repositories as real projects.

## 3. Discuss the code

- Why do navigation and projects use Flexbox and Grid for different jobs?
- Where does an event lead to a state update and then a DOM update?
- How are HTTP errors distinguished from invalid JSON structure?
- Is the request timer cleared after success, failure, and abort?
- Why are external strings excluded from HTML templates?
- Which behavior remains, and which persistence is lost, when `localStorage` is blocked?
- Why can automated checks not guarantee screen-reader quality or deployment behavior?
- How do the kernel and server boundaries differ between container and QEMU paths?

Assess whether the author can point to the relevant code and predict the effect of a change, not
whether a prepared answer has been memorized.

## 4. Interpret the verification boundary

- Browser automation and VM boot checks do not establish a GitHub Pages deployment.
- The QEMU guest runs the HTTP server; Chromium remains in the test container.
- Architecture, browser, and classroom-machine differences require evaluation in their intended environments.
- Fixtures make states deterministic but cannot reproduce every GitHub policy, outage, or response change.
- The project has no public deployment URL until a separately approved deployment returns one.
- The three tracked reference screenshots exist only because the evaluation explicitly requires
  desktop, mobile, and dark images. Other captures, including tablet test output, belong in ignored
  local output or CI artifacts and are not submission deliverables.

## 5. Troubleshooting

- **Preview port occupied:** choose another `PORT`. Automated verification does not publish a host port.
- **Docker is remote and preview is unreachable:** the published port exists on the daemon host. Use
  a tunnel or gateway for manual preview.
- **Download failure:** check registry, npm, and Alpine connectivity and available disk space. Do not
  remove version pins as a shortcut.
- **VM never becomes healthy:** inspect the transient VM serial output for `VM-BOOT-FATAL` and provide
  enough resources for software emulation. KVM and privileged mode are not required.
- **Buildx warning:** distinguish a warning from a build failure. Standard Docker Desktop BuildKit is supported.
- **API error:** anonymous rate limits or network failure may affect the live site. Keep credentials
  out of frontend code and distinguish fixture behavior from the real service.
