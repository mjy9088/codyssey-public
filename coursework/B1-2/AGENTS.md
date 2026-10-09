# Workshop planner subtree

- Keep this directory independently executable with Docker Engine and Compose. Do not import parent
  files, private assets, DIM configuration, real credentials, or a host Docker socket.
- Firebase Auth and Firestore emulator data must be real emulator state, never an in-memory mock.
- Use only synthetic workshop fixtures. Keep runtime output, screenshots, traces, and reports in the
  ignored `artifacts/` directory; this assignment does not require tracked screenshots.
- Author documentation in English and state local-emulator and external-deployment boundaries plainly.
- Keep TypeScript source files at or below 250 pure lines and preserve strict compiler settings.
