# Benchbook: React workshop planner

Benchbook is a focused React SPA for planning hands-on workshops. It has seven routes, controlled
create/edit forms, detail and list screens, filtering, pagination, deletion confirmation, and shared
loading/error/empty patterns. The official Firebase JavaScript SDK talks to real local Auth and
Firestore emulators; the application does not substitute an in-memory mock for its backend.

This directory is the complete submission unit. It needs Docker Engine, Compose v2, and a POSIX shell,
but no host Node.js, Java, Firebase CLI, QEMU, cloud account, real credentials, or Docker socket mounted
inside a workload.

## Run and verify

```sh
# Production build + Firebase emulators + Chromium end-to-end tests
sh scripts/verify.sh docker

# The same built SPA served inside an x86_64 QEMU TCG guest; emulator remains a Compose service
sh scripts/verify.sh vm

# Both paths
sh scripts/verify.sh all
```

For an interactive preview:

```sh
project="benchbook-preview-$$"
docker compose -p "$project" -f compose.yaml -f compose.preview.yaml up --build -d --wait
# Open http://127.0.0.1:8088
docker compose -p "$project" -f compose.yaml -f compose.preview.yaml down --volumes
```

The preview maps Firestore to loopback port 8085 and Auth to 9099. Emulator data is disposable and
is removed with the Compose volume/network. "Load sample schedule" writes deterministic public-safe
fixtures through the same Firebase SDK used by normal CRUD.

Each automated verification run and the preview example use a distinct Compose project. Run only one
host preview at a time: the browser's emulator connections use the fixed loopback ports above.
Automated tests do not publish host ports; they use their isolated `firebase` service and make no
public internet calls at runtime.

## Emulator authorization and persistence checks

The Playwright verifier includes direct official Firebase SDK contract tests against the local Auth
and Firestore emulators. Signed-out SDK reads and writes must receive `permission-denied` under the
checked-in `firestore.rules`; a synthetic anonymous emulator user can write and read the same
collection. Browser scenarios additionally create, reload, update, reload, delete, and reload a
synthetic workshop, and recover from malformed emulator data through the visible retry action.

The fixture administration requests used to reset Firestore and insert/remove malformed test data
are test setup only. Authorization expectations are asserted through ordinary Firebase SDK calls,
not administration endpoints, custom tokens, rule bypasses, or external Firebase projects.

## Routes and state flow

| Route | Purpose |
|---|---|
| `/` | Product overview |
| `/workshops` | List, search, status filter, pagination, empty/error/loading states |
| `/workshops/new` | Controlled create form with validation and live preview |
| `/workshops/:id` | Firestore-backed detail and delete flow |
| `/workshops/:id/edit` | Controlled edit form |
| `/about` | Architecture explanation |
| `*` | Not-found recovery |

Reusable components include the app shell, buttons, fields, badges, page header, workshop cards,
filter bar, pagination, status views, notices, and workshop form. `useWorkshops` and `useWorkshop`
own asynchronous request states; form drafts remain local; anonymous Auth state is shared through
context. Firestore payloads and user form input are parsed with Zod at their boundaries.

## Technology

- React 19, React Router, TypeScript with strict boundary flags
- Firebase Auth and Firestore emulators plus the modular Firebase SDK
- Zod, Phosphor icons, Vite, Biome, Vitest, and Playwright
- Multi-stage pinned Docker images; Nginx production server
- QEMU TCG with pinned Alpine guest artifacts and checksum verification

## GitHub Pages and Firebase

The monorepo [Pages workflow](../../.github/workflows/b1-1-pages.yml) builds this frontend for
<https://mjy9088.github.io/codyssey-public/B1-2/>. The root is a project index and B1-1 has its own
`B1-1/` directory. These are configured targets, **not claims of a completed deployment**.

Before publishing:

1. Register a Firebase web app in an approved project, create the default Firestore database,
   and enable **Anonymous** sign-in in Firebase Authentication. Use a dedicated disposable demo
   project with synthetic data, not a project containing personal or important information.
2. In the GitHub repository's **Settings → Secrets and variables → Actions**, add these three
   **Repository secrets** individually. Use each raw value without quotes or the surrounding
   Firebase configuration object:

   | Repository secret | Firebase web configuration field |
   | --- | --- |
   | `VITE_FIREBASE_API_KEY` | `apiKey` |
   | `VITE_FIREBASE_AUTH_DOMAIN` | `authDomain` |
   | `VITE_FIREBASE_PROJECT_ID` | `projectId` |

   Do not add service-account JSON, private keys, or administrator tokens. Firebase web configuration
   is included in the public JavaScript bundle even when supplied through Secrets; Secrets avoid
   hardcoding environment-specific values, not public exposure of web configuration.
3. Review and publish Firestore rules separately through the Firebase console. The checked-in
   `firestore.rules` is a **shared anonymous demo policy**: anyone who signs in anonymously can read,
   edit, or delete every workshop. It does not enforce field validation, ownership, roles, rate
   limits, or protection against quota exhaustion. Do not treat anonymous sign-in or hidden API keys
   as access control for a private application. An untrusted public deployment needs a deliberately
   stronger authorization/data-validation policy before use; rules are not deployed by Pages.
4. Review Authentication's authorized domains for the intended host (`mjy9088.github.io`, without
   a URL scheme or path). Keep the demo on **Spark without a linked Cloud Billing account** if
   usage must stop at free quotas rather than incur usage charges. Billing budget alerts are not
   a spending cap. Hosting, Functions, and Storage are not required by this frontend.
5. Set GitHub **Settings → Pages → Source** to **GitHub Actions**. After a separately approved push
   to `main`, relevant changes trigger **Publish B1 websites to Pages**; it also supports manual
   dispatch. Updating Secrets alone does not run a build; rerun the workflow after changing them.

The workflow uses the locked dependencies and pinned Node image, runs checks, and builds with
`VITE_USE_EMULATORS=false` and `VITE_ROUTER_MODE=hash`. Missing/blank Firebase values stop the
build. Vite's asset base is `/<repository>/B1-2/`; a workshop URL looks like
`/codyssey-public/B1-2/#/workshops`. Hash routing allows direct links and refreshes on Pages
without server rewrite rules. Local Docker/QEMU verification keeps its existing browser-history
routes and emulator defaults. An independent deployment can choose its own `--base` and leave
`VITE_ROUTER_MODE` unset when the host supports SPA history fallback.

Only the built `index.html` and JavaScript/CSS assets are added to the Pages artifact. Sources,
`.env` files, source maps, Firebase rules, tests, backend tooling, and local archives are excluded.
The combined build does not publish a partial site when Firebase settings are missing.

After a successful deployment, visit the actual B1-2 URL and test create, reload, edit, reload,
delete, and reload against the real Firebase project. Also test a copied detail link, a missing
route, keyboard skip navigation, and narrow screens. Check Firebase usage and remove disposable
demo data afterward. No GitHub Secret values need to be shared in chat.

For local configuration-boundary regressions with installed dependencies:

```sh
sh tests/deployment-build.sh
```

This uses synthetic web configuration only, makes no Firebase requests, and verifies required
settings and prefixed assets. It does not prove that production credentials or rules work.

The workflow also runs `node tests/pages-smoke.mjs SITE_DIR EVIDENCE_DIR` in pinned Chromium
against the assembled Pages artifact. It serves the static files under `/codyssey-public/`
without SPA rewrites and blocks all external requests. It checks both project links, hash-route
refreshes, validation, skip-link focus, asset loading, and 375/768/1280px layouts. Firebase-backed
routes deliberately exercise the authentication-unavailable state, not production CRUD.

## Deployment boundary

There is **no external deployment URL yet**. Local Docker, browser, and QEMU checks are not cloud
deployment evidence. A real submission deployment still requires an approved public repository,
Firebase project configuration supplied at build time, reviewed production Firestore
rules, and a separately approved deployment. After deployment, CRUD must be rerun against that
actual URL; the emulator result must not be presented as proof of production behavior.

QEMU boots an independent x86_64 Linux kernel under TCG and serves the exact production `dist/` from
inside the guest. It may run substantially slower on ARM hosts because it is an x86_64 guest check,
not a native ARM compatibility check.
The Firebase emulators deliberately remain local Compose network services, reachable by the test
browser. The guest has restricted user-mode networking and does not contain Java/Firebase tooling.
This proves VM frontend portability, not an all-in-guest backend or external collaboration.

Runtime screenshots, traces, reports, and logs stay in ignored `artifacts/`. This assignment does not
require tracked screenshots, and committing generated evidence would become stale, duplicate the
rerunnable checks, grow history, and risk exposing environment details.
