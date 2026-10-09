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

## Deployment boundary

There is **no external deployment URL yet**. Local Docker, browser, and QEMU checks are not cloud
deployment evidence. A real submission deployment still requires an approved public repository,
Firebase project configuration supplied as deployment environment variables, production Firestore
rules, an authorized Auth domain, and a separately approved host such as Firebase Hosting, Vercel,
or Netlify. After deployment, CRUD must be rerun against that actual URL; the emulator result must
not be presented as proof of production behavior.

QEMU boots an independent x86_64 Linux kernel under TCG and serves the exact production `dist/` from
inside the guest. It may run substantially slower on ARM hosts because it is an x86_64 guest check,
not a native ARM compatibility check.
The Firebase emulators deliberately remain local Compose network services, reachable by the test
browser. The guest has restricted user-mode networking and does not contain Java/Firebase tooling.
This proves VM frontend portability, not an all-in-guest backend or external collaboration.

Runtime screenshots, traces, reports, and logs stay in ignored `artifacts/`. This assignment does not
require tracked screenshots, and committing generated evidence would become stale, duplicate the
rerunnable checks, grow history, and risk exposing environment details.
