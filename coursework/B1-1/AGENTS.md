# Portfolio subtree

- Keep this subtree independently executable with Docker Engine and Compose.
  Do not import parent files, private assets, DIM configuration, or host Docker sockets.
- Runtime code is vanilla HTML/CSS/JavaScript. Browser-test dependencies do not ship
  with the site. Use local original artwork and synthetic test fixtures.
- Author documentation in English. Keep instructions/design rationale in Git, not
  test-run reports, status journals, traces, logs, or generated result JSON.
- Runtime artifacts belong in ignored `artifacts/`. The only required versioned
  captures are `docs/screenshots/desktop.png`, `mobile.png`, and `dark.png`.
  Explain in the README that these are an explicit submission exception, not the
  normal practice or a substitute for rerunning the tests. Do not add other captures.
- These three images also serve as deterministic visual-regression baselines. Normal
  tests must fail on differences, never rewrite expectations. Refresh them only via
  the explicit update command after reviewing the intended visual change.
- Never weaken assertions or replace real browser/VM verification with fixed output.
- Do not claim that Docker/QEMU checks establish a public deployment. Publishing
  the repository or GitHub Pages still requires separate approval.
