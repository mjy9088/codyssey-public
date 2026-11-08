# Repeatable real Firebase setup

Use the official Firebase CLI to manage Anonymous sign-in and Firestore rules as code.
This is an **optional operator command**, separate from the credential-free Docker/QEMU lab.
It does not run during a frontend build, Pages deployment, or emulator verification.

## Supported path and design decision

Firebase CLI **15.6.0** introduced Authentication provider deployment. Its documented
configuration is `auth.providers.anonymous: true`, applied with `firebase deploy --only auth`.
The operator image pins CLI **15.35.0** and its transitive dependencies using a separate npm lockfile.
The emulator image remains on its existing CLI version; changing real-server configuration
does not require changing the local lab.

Two designs were considered: a public-REST reconciler owning API enablement, Auth configuration,
database long-running operations, and rules releases; and a thin official-CLI operator. The
CLI design was selected because it already owns those workflows and preserves unspecified
Auth providers. The wrapper owns input/consent policy, credential isolation, preflight, and
failure sequencing, not a second cloud-state store. Terraform was not selected: Firebase's
documented Terraform Auth setup enables Identity Platform and requires a billing-linked
Blaze project. No billing upgrade is authorized or performed here.

The documented CLI surface is supported, but **first-time Authentication initialization on
an untouched Spark project has not been verified here**. The public REST `initializeAuth`
method is explicitly billing-only; do not replace the CLI with that method or promise it is
a Spark workaround. If the supported CLI reports a billing or initialization requirement,
stop and review that requirement. This tool never links billing or retries through a paid path.

Official references:

- [Configure Authentication providers using the CLI](https://firebase.google.com/docs/auth/configure-providers-cli)
- [Firebase CLI 15.6.0 release](https://github.com/firebase/firebase-tools/releases/tag/v15.6.0)
- [Firestore database management](https://firebase.google.com/docs/firestore/manage-databases)
- [Deploy Firebase Security Rules](https://firebase.google.com/docs/rules/manage-deploy)
- [Terraform Authentication requirements](https://firebase.google.com/docs/projects/terraform/get-started#firebase-authentication)
- [Public Auth initialization API](https://cloud.google.com/identity-platform/docs/reference/rest/v2/projects.identityPlatform/initializeAuth)

## Prerequisites and authority

- Docker Engine, a POSIX shell, and internet for the operator image build and cloud commands.
  No host Firebase CLI, Node.js, Java, or cloud SDK is required.
- An existing, approved, **dedicated disposable Firebase project** and an already registered
  Firebase **Web App**. Use its actual project ID, not a CLI alias or display name. The operator
  deliberately refuses to let the CLI create a Web App implicitly.
- A Google account accepted into Firebase with permissions to inspect the project's apps,
  configure Auth, enable the required APIs, create Firestore if missing, and publish rules.
  The CLI reports missing IAM permissions; the wrapper never grants itself access.
- An explicitly chosen [Firestore location](https://firebase.google.com/docs/firestore/locations).
  `--create-location` applies **only if `(default)` does not exist**. An existing database and
  its location are retained even when different. This is not a migration command; use an
  existing Standard / Firestore Native database for this application.
- Consent to replace the default database's current rules with `firestore.rules`. This policy
  gives **every signed-in user, including anyone signing in anonymously, shared read/write/delete
  access to every workshop**. Other paths are denied. It has no field validation, ownership,
  roles, rate limiting, or quota-abuse protection. Do not use a project with real/private data.

`--accept-shared-demo-policy` attests to these demo and rule-replacement restrictions and to
the cost caveat: **billing is not inspected, costs are not capped**, and an already billed
project can incur charges. Keep Spark with no linked Cloud Billing account if a quota stop
rather than overage billing is required. Budget alerts are not spending caps.

The three `VITE_FIREBASE_*` settings are public web configuration, not administrator
authentication. They cannot authorize this command. Never put an administrator token or
service-account key in those settings, a frontend bundle, an image, the lab, or a chat message.

## Build, preview, authenticate, apply

Run from this submission directory. The project and location below are synthetic examples;
replace them with approved values. The location choice must be deliberate, not copied blindly.

```sh
sh scripts/firebase-live.sh --help
sh scripts/firebase-live.sh build
sh scripts/firebase-live.sh version

# Offline, credential-free preview. This is NOT a remote-state diff or readiness check.
sh scripts/firebase-live.sh plan \
  --project your-demo-project \
  --create-location asia-northeast3

# One operator login, kept outside the checkout in a dedicated private directory.
export BENCHBOOK_FIREBASE_CREDENTIALS="$HOME/.local/share/benchbook-firebase-cli"
mkdir -p "$BENCHBOOK_FIREBASE_CREDENTIALS"
chmod 700 "$BENCHBOOK_FIREBASE_CREDENTIALS"
sh scripts/firebase-live.sh login

# Mutates the selected cloud project. Read the policy and cost warning above first.
sh scripts/firebase-live.sh apply \
  --project your-demo-project \
  --create-location asia-northeast3 \
  --confirm-project your-demo-project \
  --accept-shared-demo-policy

# Remove the local login and attempt remote token revocation when finished.
sh scripts/firebase-live.sh logout
```

`login` uses the CLI's interactive `--no-localhost` flow, so the browser can be on your own
machine rather than inside Docker. Follow its instructions privately. The dedicated directory
contains a sensitive refreshable user OAuth login and must not be shared or committed. It is
mounted writable only for login/logout/apply, with the host user's UID/GID; OAuth refresh may
update it. Plan/version run without credentials and with Docker networking disabled. Do not
mount a whole home directory or reuse the credential directory for unrelated secrets.

Login/logout/apply always perform a cached image rebuild and run that build's immutable image
ID. This prevents an old or concurrently replaced image tag from selecting stale code, rules,
or dependencies. Those commands need build-time network access if layers are not cached.
Offline plan/version instead mount the current operator source and rules read-only, so a
previously built image cannot silently substitute stale preview logic or rules.

Logout verifies that the local default/additional login records are gone. The Firebase CLI
attempts remote token revocation but may warn and still exit successfully if it fails. Read
its warnings; successful local logout does not prove a copied token was revoked. Remove the
dedicated credential directory when no longer needed. If remote revocation is uncertain,
review the Google account's third-party access controls separately rather than assuming a
copied token is harmless.

The build context is this submission subtree, and the Dockerfile copies only the reviewed
operator source, dependency lock, and rules. The launcher refuses credential directories
inside the checkout or containing it. It forwards neither host environment credentials nor
a Docker socket. Administrator credentials are never mounted into the Compose lab or QEMU guest.

## Apply sequence and recovery

1. Validate project/location, exact project confirmation, and demo-policy consent.
2. Check exact owner-only writable `0700` credential-directory permissions, a stored Firebase
   user and refresh token, and CLI version. Empty/malformed/post-logout config is rejected
   before any cloud CLI command, rather than allowing ambient ADC/metadata authentication.
   List existing Web
   Apps through the supported CLI; stop without deployment on an error or missing Web App.
3. Generate a private temporary config with Anonymous enabled and the explicit default database,
   creation-only location, Standard edition, and checked-in rules. No emulator endpoints, indexes,
   other providers, or hooks are included.
4. Deploy only `auth`. If it fails, **do not publish rules**.
5. Deploy only `firestore:rules`. The CLI may enable the API and create the default Firestore
   Native database if absent, then compile/release the rules. Existing documents are not seeded,
   edited, or deleted by setup. Existing rules are deliberately replaced.
6. Remove the temporary config on success, command failure, or handled interruption. CLI runtime
   files stay in the container's disposable `/tmp`, not in the checkout.

Apply is not transactional. Auth can succeed before Firestore fails; API/database creation can
succeed before rules publication fails. Read the CLI error and rerun the same command after
correcting the cause. Do not reset/delete the database. Repeated provider enablement converges,
the CLI preserves an existing database and compares rules source before uploading duplicate
rulesets. The wrapper intentionally reruns the supported commands rather than keeping a stale
local success marker; it is not a remote no-op planner. Login/logout/apply use the fixed Docker
container name `benchbook-firebase-operator-<host UID>`, serializing credential writers for that
operator on the same Docker daemon. A second active command fails on name conflict; it does not
enter the other container or touch its login. The container is automatically removed on exit.
If a Docker failure leaves a stopped container, inspect its state before removing that named
container and retrying; never kill another active operator to clear the name. This is not a
distributed lock: coordinate different users/hosts and run only one apply per project at a time.
An interrupted cloud operation can complete server-side after local cancellation. Rerun to
re-observe it through the CLI, not to roll it back. SIGKILL/container loss discards temporary
local files but cannot cancel or undo server-side changes.

No command is issued to create a Cloud project, add Firebase to a non-Firebase project, link
billing, change IAM, deploy Hosting/Functions/Storage/indexes, seed documents, change authorized
domains, update GitHub secrets, or publish Pages. Keep those separately approved operations
separate. Existing providers and authorized domains are not deliberately rewritten.

## Verification and remaining live boundary

```sh
# Includes pure request/config policy and synthetic CLI/launcher boundary checks.
npm run test:provision

# Runs those checks alongside the real-emulator app tests in the standalone lab.
sh scripts/verify.sh docker
```

Synthetic process doubles verify the requested CLI payloads, explicit project scope, consent
rejection, no-Web-App failure, offline isolation, temporary-config cleanup, repeated desired
state, and recovery sequencing. These tests **do not prove** cloud initialization, cloud
idempotence, IAM eligibility, current billing, or remote Security Rules enforcement. Version
and plan can be exercised against the real pinned CLI image without cloud credentials.

After an authorized live apply, retry the actual deployed frontend. If web configuration has
not changed, a server-only Auth/provider/rules update needs no Pages rebuild. If it changed,
update the Actions web settings and rebuild. Verify anonymous sign-in, create/reload, edit/reload,
delete/reload, copied hash links, and signed-out denial against the intended real project. Check
usage and remove synthetic test records. A successful CLI deployment alone is not that proof.
Do not treat emulator success or static Pages smoke tests as evidence that live Firebase works.
