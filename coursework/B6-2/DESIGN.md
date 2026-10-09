# Folio Book Catalog Design System

## 1. Atmosphere & Identity

Folio feels like a carefully indexed personal library: calm, tactile, and exact. Its signature is the “shelf rule,” a narrow colored edge paired with editorial typography so every record reads like a catalog card rather than a generic SaaS tile.

The direction is an orderly reading desk rather than an admin dashboard. Warm paper, ink-blue actions, fine rules, and staggered book-spine accents make the catalog recognizable without decorative clutter.

Primary personas are a keyboard-first reader maintaining a small collection and a low-vision reader who needs strong contrast, clear focus, plain validation, and stable page structure.

## 2. Color

| Role | Token | Value | Usage |
|---|---|---|---|
| Canvas | `--paper` | `#f7f3eb` | Page background |
| Surface | `--sheet` | `#fffdf8` | Cards and forms |
| Surface quiet | `--wash` | `#eee8dc` | Header and secondary bands |
| Ink | `--ink` | `#24231f` | Primary text |
| Ink muted | `--muted` | `#69655d` | Metadata and help |
| Rule | `--rule` | `#d7d0c3` | Borders and dividers |
| Accent | `--blue` | `#244b64` | Links, focus, primary action |
| Accent hover | `--blue-deep` | `#173447` | Hover and active action |
| Shelf rust | `--rust` | `#a84f32` | Record edge and destructive emphasis |
| Error wash | `--error-wash` | `#f8e7df` | Validation summary |
| Error ink | `--error-ink` | `#7e2f1f` | Error text |
| Success wash | `--success-wash` | `#e3eee6` | Success notices |
| Success ink | `--success-ink` | `#4e775b` | Success notice rule |
| Invalid field | `--invalid-field` | `#fffaf7` | Invalid input background |
| On accent | `--on-accent` | `#ffffff` | Text on saturated actions |
| Input rule | `--input-rule` | `#aba398` | Default field border |
| Rule strong | `--rule-strong` | `#ada496` | Hovered card border |
| Focus wash | `--focus-wash` | `rgba(36, 75, 100, 0.2)` | Input focus halo |
| Masthead wash | `--masthead-wash` | `rgba(247, 243, 235, 0.96)` | Translucent header surface |
| Ledger shadow | `--ledger-shadow` | Four warm translucent layers | Featured ledger depth |

Only interactive controls and semantic states use saturated color. Body text maintains WCAG AA contrast.

## 3. Typography

| Level | Size | Weight | Line height | Tracking | Usage |
|---|---:|---:|---:|---:|---|
| Display | `clamp(2.75rem, 8vw, 5.5rem)` | 600 | 0.96 | -0.045em | Home statement |
| H1 | `clamp(2rem, 5vw, 3.5rem)` | 600 | 1.02 | -0.035em | Page title |
| H2 | `1.5rem` | 600 | 1.2 | -0.02em | Card/form heading |
| H3 | `1.125rem` | 650 | 1.3 | -0.01em | Book title |
| Body large | `1.125rem` | 400 | 1.65 | 0 | Introductory copy |
| Body | `1rem` | 400 | 1.6 | 0 | Default copy |
| Small | `0.875rem` | 500 | 1.45 | 0.01em | Metadata and help |
| Label | `0.75rem` | 700 | 1.3 | 0.09em | Uppercase labels |

- Display: Georgia, Cambria, `Times New Roman`, serif.
- UI/body: `Avenir Next`, Avenir, `Segoe UI`, sans-serif.
- Numerals/meta: `SFMono-Regular`, Consolas, monospace.
- No remote fonts; the system stack avoids third-party requests and layout shift.

## 4. Spacing & Layout

All spacing intent follows a 4px base: `--s1` 4px, `--s2` 8px, `--s3` 12px, `--s4` 16px, `--s5` 20px, `--s6` 24px, `--s8` 32px, `--s10` 40px, `--s12` 48px, `--s16` 64px, `--s20` 80px.

- Content width: 1120px with `clamp(16px, 4vw, 48px)` gutters.
- Reading/form width: 680px.
- Catalog grid: responsive `minmax(min(280px, 100%), 1fr)` tracks.
- Breakpoints: 640px, 860px, 1120px.
- Pages scroll as documents; no nested scroll regions.

## 5. Components

### Site shell
- **Structure**: skip link, masthead, primary navigation, main, restrained footer.
- **States**: current navigation uses `aria-current`; links have hover, active, and focus-visible states.
- **Layout**: centered document shell; navigation wraps rather than clips.

### Buttons and action links
- **Variants**: primary ink-blue, secondary paper, quiet text, destructive rust.
- **Spacing**: `--s3 --s5`; 4px radius; minimum 44px target.
- **States**: visible focus ring, color shift on hover, 2px translate plus brightness feedback on active, disabled opacity.
- **Accessibility**: links navigate, buttons submit; destructive action requires a confirmation page.

### Form field
- **Structure**: label, input, hint, inline error.
- **States**: default, hover, focus, invalid, disabled.
- **Accessibility**: labels are explicit; errors connect with `aria-describedby` and `aria-invalid`.

### Catalog card
- **Structure**: shelf edge, title link, author, publication year, record number, action link.
- **States**: hover/focus reinforces border and link; long titles wrap safely.
- **Layout**: vertical stack; no hidden metadata.

### Notice and empty state
- **Variants**: validation error, status success, missing record, empty collection.
- **Accessibility**: errors use `role="alert"`; status text uses `role="status"`.

### Primitive showcase
- `/showcase` renders buttons, links, fields, notices, cards, and empty states for mobile/tablet/desktop QA. It is a development/design reference containing only synthetic public-safe content.

## 6. Motion & Interaction

- Micro: 120ms ease-out for button press and focus feedback.
- Standard: 220ms ease-in-out for border, color, opacity, and transform transitions.
- Entry: 420ms cubic-bezier(0.16, 1, 0.3, 1) for the home ledger only.
- Animate only opacity and transform; reduced-motion disables entry motion.
- No JavaScript animation. SSR remains fully usable without client scripts.

## 7. Depth & Surface

Mixed but restrained: 1px rules define ordinary components; the featured home ledger uses one four-layer shadow stack with each layer below 0.05 opacity. No glass, gradients, or heavy floating cards.

## 8. Accessibility Constraints & Accepted Debt

- Target WCAG 2.2 AA: 4.5:1 body contrast, 3:1 large text, 44px targets, full keyboard reachability, semantic landmarks, and visible focus.
- Validation retains entered values and moves an alert summary before fields in source order.
- Destructive changes require a dedicated confirmation GET and CSRF-protected POST.
- No accepted accessibility or persona debt.
- External deployment and assistive-technology lab testing remain outside local verification; Docker/QEMU results are not presented as production evidence.
