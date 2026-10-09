# Benchbook Design System

## 0. Research Log

- Embedded refs: shortlisted Notion, Linear, and Airtable; picked the operational taste rules plus
  Notion because a workshop planner benefits from warm document surfaces, whisper borders, and dense
  but calm controls.
- Existing-project lane: reviewed B1-1's design contract and nine UI/behavior files; retained its
  semantic-token discipline, 4px spacing base, state components, focus treatment, and intrinsic grids.
- Lazyweb: skipped because external design research was unnecessary for this private-coursework task;
  no restricted material was sent outside the workspace.
- Imagen drafts: skipped because no image-generation tool is available and this is an application
  shell whose real product UI is the focal artifact.

## 1. Atmosphere & Identity

A working studio ledger: warm paper, graphite type, cobalt registration marks, and terse operational
copy. The signature is a slim cobalt "binding" at the left of each workshop card, with status and
capacity reading like annotations rather than dashboard chrome. The memorable interaction is the
list reorganizing immediately as filters change while the URL and result count remain in sync.

Design read: a task-focused planning SPA for workshop coordinators, with calm editorial productivity
language inspired by Notion rather than a generic SaaS dashboard. Dials: variance 5, motion 3, density 6.

## 2. Color

| Role / token | Value | Usage |
|---|---|---|
| `--canvas` | `#f2f0ea` | App background |
| `--surface` | `#fbfaf7` | Panels and fields |
| `--surface-raised` | `#ffffff` | Cards and active controls |
| `--ink` | `#252521` | Primary text |
| `--ink-muted` | `#62615b` | Supporting text |
| `--ink-faint` | `#7b7971` | Captions and placeholders |
| `--line` | `#d8d5cc` | Dividers and borders |
| `--line-strong` | `#9a978d` | Hover boundaries |
| `--accent` | `#1d58a7` | Primary action, links, binding |
| `--accent-hover` | `#174682` | Hover/pressed accent |
| `--accent-soft` | `#e4edf9` | Selected filters and info |
| `--success` | `#276a43` | Success and open status |
| `--success-soft` | `#e2f0e8` | Success surface |
| `--warning` | `#8a590e` | Capacity warning |
| `--warning-soft` | `#f8edd8` | Warning surface |
| `--danger` | `#a23631` | Errors and delete action |
| `--danger-soft` | `#f7e5e2` | Error surface |
| `--focus` | `#156fd1` | Keyboard focus |

Rules: color is semantic; accent is reserved for interaction and list binding. CSS may contain these
literals only in the token declaration block. Dark mode is not introduced because this operational
submission prioritizes a single thoroughly verified theme.

## 3. Typography

System-local fonts avoid network dependency. Display uses `Georgia, Cambria, serif`; body uses
`"Avenir Next", Avenir, "Segoe UI", sans-serif`; metadata uses `ui-monospace, Consolas, monospace`.

| Token | Size | Weight | Line height | Use |
|---|---|---:|---:|---|
| `--type-display` | `clamp(2.5rem, 7vw, 5.25rem)` | 400 | .95 | Home statement |
| `--type-h1` | `clamp(2rem, 4vw, 3.5rem)` | 400 | 1 | Page title |
| `--type-h2` | `1.5rem` | 600 | 1.2 | Card/section heading |
| `--type-h3` | `1.125rem` | 650 | 1.3 | Workshop title |
| `--type-lead` | `1.125rem` | 400 | 1.55 | Introductory copy |
| `--type-body` | `1rem` | 400 | 1.6 | Default text |
| `--type-small` | `.875rem` | 500 | 1.45 | Supporting UI |
| `--type-label` | `.75rem` | 650 | 1.35 | Metadata and badges |

## 4. Spacing & Layout

4px base: `--space-1` 4px, `--space-2` 8px, `--space-3` 12px, `--space-4` 16px,
`--space-5` 20px, `--space-6` 24px, `--space-8` 32px, `--space-10` 40px,
`--space-12` 48px, `--space-16` 64px, `--space-20` 80px.

- `--content-max`: 1180px; `--readable`: 66ch; `--control-size`: 44px.
- Page shell uses document scroll; header is sticky. List grids use
  `repeat(auto-fit, minmax(min(19rem, 100%), 1fr))` and collapse intrinsically.
- Detail and form pages use an asymmetric main/aside grid above 800px and one column below.
- Radius: `--radius-sm` 4px, `--radius-md` 10px, `--radius-lg` 18px, pills only for badges.

## 5. Components

### App shell and navigation
- Structure: skip link, sticky header, brand, primary links, signed-in identity, main, footer.
- States: current route, hover, focus, signed-in/loading. The document owns scrolling.
- Accessibility: landmarks, current-page semantics, 44px targets.

### Button / text action
- Variants: primary, secondary, quiet, danger. Spacing uses `--space-2` and `--space-4`.
- States: hover, focus-visible, active scale, disabled, submitting label.

### Field / select / textarea
- Structure: visible label, control, hint, reserved inline error. Stack layout.
- States: default, focus, invalid, disabled; errors use `aria-describedby` and `aria-invalid`.

### Workshop card and list
- Structure: binding edge, status/meta cluster, title, summary, capacity, view action.
- States: hover/focus-within, open/full/cancelled status. Intrinsic grid owns reflow.

### Status view
- Variants: loading skeleton, empty, error/retry, not-found.
- Accessibility: status or alert semantics; copy always identifies recovery action.

### Filter bar and pagination
- Structure: search, status select, result count, previous/next. Cluster layout.
- States: active query, disabled pagination, empty result.

### Workshop form
- Structure: controlled fields, live preview aside, submit/cancel actions, request error.
- States: pristine, invalid, submitting, request failure. Document scroll.

### Notice and confirmation panel
- Variants: informational, success, warning, destructive confirmation.
- Accessibility: `role=status` or `role=alert`; destructive action requires explicit confirmation.

## 6. Motion & Interaction

`--motion-fast` 120ms and `--motion-base` 220ms with `--ease-out`
`cubic-bezier(.16,1,.3,1)`. Only opacity and transform animate. Buttons compress on activation;
cards lift by one spacing unit on hover; route content fades in to clarify navigation. Reduced-motion
users get instant state changes. No perpetual or decorative motion.

## 7. Depth & Surface

Mixed but restrained: whisper borders define structure and a layered, low-opacity tinted shadow
(`--shadow-card`) distinguishes raised cards. The card binding edge provides product identity.
No glass, glow, or gradient.

## 8. Accessibility Constraints & Accepted Debt

Target WCAG 2.2 AA: 4.5:1 body contrast, 3:1 UI boundaries, visible focus, full keyboard operation,
44px targets, reduced-motion support, live request states, and errors that never rely on color.
Personas: keyboard-only evaluator, low-vision coordinator at 200% zoom, motion-sensitive visitor,
and a coordinator recovering from an emulator/network failure.

| Item | Location | Why accepted | Owner / Exit |
|---|---|---|---|
| No external deployment URL | README | Publishing and real Firebase credentials require separate approval | Project owner deploys and then reruns the same flows |
| QEMU serves only the built SPA | VM verifier | Browser-accessible emulator stays a Compose service; guest egress is deliberately restricted | Use an all-in-guest emulator only if VM backend parity becomes an explicit goal |
