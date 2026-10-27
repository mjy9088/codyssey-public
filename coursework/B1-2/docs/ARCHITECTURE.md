# Ownership and Failure Boundaries

## Runtime flow

`main.tsx` composes authentication and routing. `App.tsx` selects screens inside the shared layout.
Pages coordinate navigation, filtering, pagination, and mutations; reusable components own markup,
form drafts, and interaction states. The pages call `useWorkshop` or `useWorkshops` for authenticated
reads and the Firestore adapter for mutations.

`lib/workshop.ts` owns plain-value validation and the workshop model. It has no DOM, Firebase, or
React initialization requirement. Controlled form strings cross that schema once before becoming
typed mutation inputs. `lib/workshop-store.ts` owns Firestore requests and parses stored records at
the read boundary. The snapshot's document ID is authoritative: a stored `id` field must never
redirect a link, update, or deletion to another document. Links and post-save navigation encode the
ID as a URL path segment; URL-reserved characters must not turn document identity into a query or
fragment. React Router decodes that segment before the SDK lookup.

`lib/workshop-seed.ts` owns deterministic sample administration with an atomic write batch. It is
separate from ordinary CRUD, and the list page owns its pending/error state. Fixture creation is
not an implicit side effect of normal reads or authentication.

## Authentication and asynchronous ownership

The auth provider owns one observer lifetime and the current anonymous sign-in attempt. Retry,
successful observed authentication, observer errors, and cleanup invalidate obsolete failures.
Unsubscribing releases the observer; it does not cancel an already-started SDK sign-in operation.

Read hooks tag their state with the authenticated user and, for detail reads, the requested ID.
A render for a new owner returns loading immediately rather than showing another owner's result
until an effect runs. Request generations exclude older success and rejection handlers after a
new load or ownership transition. Unmount invalidates pending completions. The SDK request itself
may still complete; `reload()` remains an awaitable operation for callers such as sample loading.
Form drafts remain component-local and are recreated when a new detail load replaces the form.

Deletion navigates with a typed success marker rather than arbitrary display copy. The list renders
the success notice and clears the consumed history state, so refreshing does not repeat an old
notification. Destructive confirmation describes the schedule, not an assumed backend environment.

## Configuration and authorization

Local development and standalone container builds default to the documented emulator mode.
`VITE_USE_EMULATORS` accepts exactly `true` or `false`; other spellings fail configuration rather
than accidentally selecting a backend. Explicit remote builds require all three Firebase web
settings. The Pages workflow selects remote mode explicitly. Web configuration is public bundle
data, not an administrator credential or an authorization mechanism.

The checked-in Firestore policy is intentionally a shared anonymous demo, not ownership protection
or server-side field validation. Application parsing does not make that policy safe for an
untrusted public deployment. The README's separate production review and deployment requirements
still apply. No rule or cloud configuration is published by local verification.

## Verification responsibilities

- Unit tests execute the schema and React request lifetimes with controlled deferred I/O. These
  tests distinguish stale completions deterministically; they do not substitute for Firebase.
- Source checks enforce dependency direction without pinning an exact internal file inventory,
  hook implementation syntax, or page-import count. Browser scenarios verify route identity.
- Browser tests use real Auth and Firestore emulators for authorization, durable CRUD, conflicting
  stored IDs, rejected writes, retry recovery, and draft preservation. Emulator administration
  endpoints only arrange synthetic inputs and faults; application requests use the ordinary SDK.
- The verifier runs Biome, strict application and test TypeScript, unit tests, deployment-build
  checks, and Chromium. Logs, traces, and screenshots are copied out before its containers are
  removed and remain ignored under `artifacts/docker/` or `artifacts/vm/`.
- QEMU serves the same built SPA from an independent guest kernel. The browser and emulators stay
  Compose services; this is local portability evidence, not an external Firebase deployment.
