# Genuine Firebase verification

The ordinary standalone lab remains `sh scripts/verify.sh docker` (or `all` for Docker
and QEMU). It needs no cloud project or credentials. When Docker cannot start on a
development host, the optional native runner exercises real Firebase emulators and
the production-built app rather than substituting mocked authentication or a database.

## Native prerequisites

- Installed application dependencies from this directory's `package-lock.json`.
- Installed operator dependencies from `ops/firebase/package-lock.json`; this pins the
  native runner's Firebase CLI to 15.35.0. The existing Docker emulator retains its
  separately pinned CLI version. These are different runtime environments, not interchangeable
  container/VM evidence.
- Java 21 or later on `PATH` and a working headless Chromium. If the Playwright browser
  is unavailable, set `PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH` to a compatible installed binary.
- Working system fonts. A privately extracted native runtime can supply `LD_LIBRARY_PATH`
  and `FONTCONFIG_FILE`; the runner forwards only these runtime settings, not cloud tokens.
- Free loopback ports 4173, 4400, 4500, 8085, 9099, and 9150. Run one native verification
  at a time, without the fixed-port interactive preview. The runner checks ports before use
  and never kills a pre-existing process to free them.

```sh
npm ci --ignore-scripts --no-audit --no-fund
npm --prefix ops/firebase ci --ignore-scripts --no-audit --no-fund
npx playwright install chromium
node scripts/verify-native.mjs
```

Install Java, browser libraries and fonts using your platform's trusted packages. The
runner does not alter the host daemon, firewall, system package database, or host names.
On an unsupported libc/platform, Playwright's downloaded browser may not start; use a
compatible native Chromium rather than weakening visibility assertions.

## What executes

Every invocation creates a fresh `demo-benchbook-*` project namespace, private temporary
HOME/config directory, build output and logs under ignored `artifacts/native-firebase-*`.
The inherited Firebase/GCP credentials and normal user config are not forwarded. Demo
project IDs cannot provision or access non-emulated Firebase services. Both emulators bind
to loopback, and the app is explicitly built in emulator mode with synthetic web settings.

The runner waits until the hub reports **both** Auth and Firestore, builds the current
frontend, serves that production build with Vite preview, and executes the Playwright suite.
This covers signed-out denial, actual anonymous sign-in, durable browser create/edit/delete
through reloads, real-rule write rejection and retry, duplicate activation, and saved-record
counts after retry. Some existing Auth configuration-error tests inject failure packets;
their successful retries still use real Auth, not mocked successful login.

The additional SDK isolation probe uses separate anonymous users, server reads (not cached
documents), a randomly namespaced record, sign-out and repeated sign-in, creator CRUD and
cross-user read/update/delete attempts. It deletes only its exact record and user handles.
The disposable emulator process/state belongs exclusively to this run. Existing browser
fixtures may reset that run's project, never a real cloud database.

Exit codes:

- `0`: browser checks and owner-isolation probe passed.
- `1`: prerequisite, service, build, browser, or unexpected probe failure.
- `2`: browser checks passed, but the requested owner-isolation boundary failed.
- `130`: interrupted execution.

**Current policy deliberately lacks owner isolation.** The checked-in rule grants every
authenticated user shared CRUD over `/workshops/*`; the schema and queries have no owner
field/filter. Accordingly, the probe reports cross-user operations as allowed and exits `2`.
Do not present the shared-demo browser suite passing as owner-authorization acceptance.
An ownership/tenancy design and associated data/query/rules migration require an explicit
follow-up decision. This verification does not silently change that existing product policy,
deploy stronger or weaker rules, or rewrite real data.

Logs are ignored, JWT-like output is redacted, and native traces are disabled to avoid
recording authentication packets. The runner stops only its own process groups on success,
failure or handled signals. A complete second invocation starts with a new namespace and
does not reuse a prior success marker. Emulator downloads may be cached separately under
ignored `artifacts/native-emulator-cache/`; no Auth/database state is exported.

## Real deployed-cloud acceptance remains separate

Native/emulator success is not cloud acceptance. A real run additionally needs an approved
existing disposable project, matching deployed build/test web configuration, enabled Anonymous
Auth and Firestore APIs, applicable published rules, and authorization for test-owned resources.
The selected deployment must match the source revision being accepted. Configuration file
presence alone does not establish login, provider readiness, IAM permission, or correct rules.

Do not create or bill a project, upgrade plans, change IAM or production rules, access real
user records, or invoke `firebase-live.sh apply` merely to pass verification. Resolve missing
project selection/login/service setup and the owner-policy decision through the root handoff.
Keep cloud identities, keys and credential-bearing configuration out of logs and Git.
