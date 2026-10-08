# Margin Notes Portfolio Design System

## 0. Design Rationale and References

The visual direction combines editorial and notebook conventions rather than reproducing a single
product. Notion informs warm paper surfaces and quiet dividers; Wired informs serif-led hierarchy and
asymmetric editorial rhythm; Claude informs restrained controls and generous reading space. Public
portfolio examples such as Immersive Labs and Chordify illustrate centered introductions, a distinct
featured area, roomy project grids, and cards organized as image, label, summary, and action.

Interaction patterns follow common accessible input, button, and theme-control conventions: reserve
space for field errors, connect errors with `aria-describedby`, expose invalid and pressed states,
support reduced motion, and keep icon changes simple. These are reference principles, not bundled
brand assets, copied library code, or runtime dependencies. Original local SVG line art provides the
site's focal image.

## 1. Atmosphere & Identity

A calm engineering notebook: warm paper, black ink, blue-green annotations, and deliberate margins. The signature is an offset “working page” portrait built from local line art and ruled annotations; the memorable moment is the page changing ink and paper together when the theme toggles.

Content jobs follow the visitor path: hero hooks, About explains, Skills orients, Projects proves, Contact converts, footer retains/navigation closes.

## 2. Color

| Role / token | Light | Dark | Usage |
|---|---|---|---|
| `--paper` | `#f4f1e8` | `#151816` | Page canvas |
| `--sheet` | `#fffdf7` | `#1d211e` | Cards and fields |
| `--sheet-strong` | `#ffffff` | `#252a26` | Elevated controls |
| `--ink` | `#202522` | `#f2eee2` | Primary text |
| `--ink-soft` | `#626861` | `#b7bcb4` | Secondary text |
| `--line` | `#d8d3c6` | `#3b423c` | Whisper dividers |
| `--line-strong` | `#aba797` | `#697168` | Hover borders |
| `--accent` | `#126c61` | `#79cbbb` | Links and actions |
| `--accent-strong` | `#0a5048` | `#a1dfd2` | Hover/active |
| `--accent-soft` | `#dcece6` | `#203f38` | Tags and selected state |
| `--danger` | `#a43b36` | `#ff9b92` | Validation errors |
| `--success` | `#27633d` | `#86cf9c` | Local-validation success |
| `--focus` | `#176fbd` | `#78bfff` | Keyboard focus |

Rules: color is semantic; no undeclared literals in CSS. Accent is reserved for interaction and annotations. Dark mode is selected by `[data-theme="dark"]`.

## 3. Typography

Local/system stacks only:

- Display: `Georgia, "Times New Roman", serif`
- Body: `"Avenir Next", Avenir, "Segoe UI", sans-serif`
- Mono/meta: `ui-monospace, "SFMono-Regular", Consolas, monospace`

| Token | Size | Weight | Line height | Tracking | Use |
|---|---:|---:|---:|---:|---|
| `--type-display` | `clamp(3rem, 10vw, 7.5rem)` | 400 | .88 | -.055em | Hero |
| `--type-h1` | `clamp(2.5rem, 6vw, 4.75rem)` | 400 | .96 | -.04em | Section headings |
| `--type-h2` | `clamp(1.65rem, 3vw, 2.35rem)` | 400 | 1.1 | -.025em | Card/feature headings |
| `--type-h3` | `1.125rem` | 650 | 1.35 | -.01em | Item titles |
| `--type-lead` | `clamp(1.125rem, 2vw, 1.35rem)` | 400 | 1.65 | 0 | Introductions |
| `--type-body` | `1rem` | 400 | 1.7 | 0 | Body |
| `--type-small` | `.875rem` | 500 | 1.5 | .01em | Metadata |
| `--type-label` | `.75rem` | 650 | 1.4 | .1em | Uppercase labels |

## 4. Spacing & Layout

4px base: `--space-1` 4px, `--space-2` 8px, `--space-3` 12px, `--space-4` 16px, `--space-5` 20px, `--space-6` 24px, `--space-8` 32px, `--space-10` 40px, `--space-12` 48px, `--space-16` 64px, `--space-20` 80px, `--space-24` 96px, `--space-32` 128px.

- `--page-gutter`: `clamp(1rem, 4vw, 3rem)`; `--content-max`: 1200px; readable text max: 68ch.
- Mobile is one column. At 768px, About, Contact, skills, and projects gain columns. At 1024px, the hero becomes an asymmetric 7/5 composition and project cards form three columns.
- Navigation uses flex with the wordmark pushing controls right. Project cards use auto-fit/minmax with an 18rem minimum capped to available width; long filter labels never enlarge the page. About has a full-width heading above profile, body, and margin note.
- Sections use large rhythm rather than boxes. Asymmetry distinguishes authored work from a template.
- Radii: `--radius-sm` 4px, `--radius-md` 12px, `--radius-lg` 24px, `--radius-round` 999px.

## 5. Components

### Header and primary navigation
- Structure: semantic header, brand anchor, nav, menu and theme buttons.
- States: transparent/default; compact ruled surface after 60px; mobile menu open/closed; hover, active, focus.
- Accessibility: `aria-expanded`, `aria-controls`, Escape closes and restores trigger focus; nav link closes and focus follows the destination.
- Desktop hiding overrides the enhanced mobile selector; the native `hidden` attribute always wins over component display rules.

### Action link / button
- Structure: text plus local SVG arrow/icon; primary filled and quiet outlined variants.
- States: default, hover, focus-visible, active, disabled/loading where applicable.
- Motion: 120ms pressed scale; reduced motion removes transforms.

### Editorial card
- Structure: metadata row, title, description, language badge, action.
- States: loading skeleton, success card, empty notice, error/retry; hover/focus raises only through border and 4px transform.
- Accessibility: article landmark; external link names include project title.

### Field
- Structure: label, input/textarea, reserved error line.
- States: default, focus, invalid, valid, disabled.
- Accessibility: native required/type semantics plus `aria-invalid`, `aria-describedby`, and live form status.

### Section heading
- Structure: mono index/label plus serif title and optional introduction.
- Layout: cluster on mobile, aligned editorial baseline at tablet/desktop.

### Icon control
- Structure: 44px minimum button with inline SVG and accessible name.
- States: default, hover, focus, active; icon swap for theme and menu state.

## 6. Motion & Interaction

| Token | Value | Use |
|---|---|---|
| `--motion-fast` | 120ms | Press and icon feedback |
| `--motion-base` | 240ms | Color, opacity, menu state |
| `--motion-reveal` | 560ms | Intersection reveal |
| `--ease-out` | `cubic-bezier(.16,1,.3,1)` | Meaningful entrances |

- Reveal starts only after JS adds `.js`; content is visible by default. Observer threshold is `.2` and items reveal once.
- Smooth scrolling is CSS-only. Reduced motion disables smooth scrolling, reveal transforms, and nonessential transitions.
- Header and back-to-top visibility respond to scroll state; only transform/opacity animate.
- The hidden back-to-top control leaves the tab order and accessibility tree. Activation moves focus to main content; section links focus their destination without timer-based focus changes.

## 7. Depth & Surface

Mixed but restrained: whisper borders and tonal shifts carry most depth. A single soft shadow token (`--shadow-paper`) uses layered low-opacity ink for the portrait sheet, project cards, and open mobile nav. No gradients and no glassmorphism; original SVG hatching and paper rules create atmosphere.

## 8. Accessibility Constraints & Accepted Debt

- Target WCAG 2.2 AA: 4.5:1 body contrast, 3:1 large text/UI boundaries, visible focus, semantic landmarks, keyboard-complete interactions, 44px targets, reduced motion, and errors that do not rely on color.
- Personas: keyboard-only reviewer, low-vision visitor using 200% zoom/dark preference, motion-sensitive visitor, and mobile visitor on an unreliable connection. Core content remains present without JS; only live repositories and enhancements depend on it.
- GitHub content is untrusted: schema-check every item, cap rendered results, and insert values with `textContent`/safe DOM attributes only.
- Contact success states only local validation and explicitly says no message was sent.

### Accepted Debt

| Item | Location | Why accepted | Owner / Exit |
|---|---|---|---|
| Live GitHub data needs network access | Projects | Required runtime behavior; explicit error/retry and empty states exist | Site owner may add a static curated fallback later |
| System serif metrics vary by OS | Global typography | No external fonts or dependencies permitted | Accept while preserving responsive measures |
