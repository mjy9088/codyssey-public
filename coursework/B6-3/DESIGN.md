# Folio Design System

## 1. Atmosphere & Identity

Folio feels like a quiet reading room: warm paper surfaces, crisp typographic hierarchy, and blue
used only for actions. Its signature is the slim cobalt inventory rail on each title card.

## 2. Color

| Role | Token | Light | Dark |
| --- | --- | --- | --- |
| Canvas | `--canvas` | `#f6f5f4` | `#191918` |
| Surface | `--surface` | `#ffffff` | `#242321` |
| Surface strong | `--surface-strong` | `#ebe9e6` | `#31302e` |
| Text | `--ink` | `#20201e` | `#f6f5f4` |
| Text muted | `--muted` | `#615d59` | `#b9b4ae` |
| Border | `--line` | `#d9d6d2` | `#484541` |
| Accent | `--accent` | `#0068c9` | `#62aef0` |
| Accent strong | `--accent-strong` | `#00509b` | `#92c8f5` |
| Error | `--error` | `#b42318` | `#ffb4ab` |
| Success | `--success` | `#26734d` | `#74d6a3` |

## 3. Typography

The stack is `Arial, Helvetica, sans-serif`; no remote font delays rendering. Display is
`clamp(2rem, 5vw, 3.5rem)` at 700/1.05, H1 is `2rem`, H2 is `1.375rem`, body is `1rem` at
1.55, and captions are `0.8125rem` at 600.

## 4. Spacing & Layout

The base unit is 4px. Tokens are 4, 8, 12, 16, 24, 32, 48, and 64px. Content is capped at
1120px with 16px mobile gutters and 32px desktop gutters. Multi-column content collapses below
720px; touch targets remain at least 44px.

## 5. Components

### App header
- Structure: brand, catalog and loans links, member identity, logout form.
- States: link hover/focus and button pressed; navigation wraps on narrow screens.
- Accessibility: landmark navigation and visible focus outlines.

### Action
- Structure: link or button with primary, secondary, and danger variants.
- States: default, hover, active, focus, disabled.
- Motion: transform only, 120ms, disabled under reduced motion.

### Field
- Structure: label above native input, optional hint, contextual error below.
- States: default, focus, invalid, disabled.
- Accessibility: explicit labels, high-contrast focus and error text.

### Book card
- Structure: inventory rail, title and author, year, availability label, linked record surface.
- States: available and unavailable use text plus color; the title link carries hover and focus.
- Layout: responsive grid becoming a vertical stack on mobile; metadata never truncates.

### Member session
- Structure: compact identity block, navigation, and a CSRF-protected sign-out control.
- States: current navigation uses `aria-current`; signed-out pages omit protected navigation.
- Layout: the account row wraps below navigation at narrow widths without changing source order.

### Loan row
- Structure: status label, linked book title, author, borrowed date, returned date or return action.
- States: borrowed is blue and actionable; returned is quiet green and final.
- Accessibility: status is never communicated by color alone; filters expose the current value.

### Confirmation disclosure
- Structure: quiet destructive trigger followed by a native `details` confirmation surface.
- States: collapsed by default, explicit open state, CSRF-protected final action.
- Accessibility: no client script is required; the summary is keyboard-operable and danger copy is direct.

### Notice and empty state
- Variants: error alert, availability status, no catalog matches, no loans for a filter.
- Accessibility: alerts use `role="alert"`; empty states include a plain next action where useful.

### Primitive showcase
- A synthetic `/showcase` route should render navigation, actions, fields, notices, book cards, loan
  rows, badges, empty states, and confirmation disclosure for mobile/tablet/desktop review.

## 6. Motion & Interaction

Interactive controls move down 1px when pressed and use 120ms ease-out transitions for transform,
color, and opacity. Reduced-motion mode disables transitions. No automatic motion is used.

## 7. Depth & Surface

Depth uses tonal shifts plus whisper borders. Cards use one subtle, warm-tinted shadow; navigation
and page sections use no shadow. Radius is 8px for surfaces and 4px for controls.

## 8. Accessibility Constraints & Accepted Debt

Target WCAG 2.2 AA: 4.5:1 body contrast, visible keyboard focus, semantic landmarks, labeled forms,
44px targets, responsive reflow, and reduced-motion support. Accepted debt: no manual theme toggle;
system color preference selects the theme until product requirements justify a persistent control.

## 9. Route & State Inventory

- `/login`: default, invalid credentials, expired CSRF.
- `/`: authenticated welcome and current shelf preview.
- `/books`: populated, search result, no-match result.
- `/books/new` and `/books/{id}/edit`: default and invalid submission.
- `/books/{id}`: available, unavailable, borrow action, delete disclosure.
- `/loans`: all, borrowed, returned, and empty-filter states.
- Loan conflict and book-not-found pages: recovery-oriented error surfaces.
