# Exercise the production build, real local Firebase emulators, and Chromium flows.
demo:
    node scripts/verify-native.mjs --demo

# Check types, unit behavior, browser flows, and the owner-isolation policy.
check:
    npm run check
    npm test
    node scripts/verify-native.mjs

# Start the interactive planner and both emulators using Compose.
preview:
    docker compose -f compose.yaml -f compose.preview.yaml up --build --wait
    @echo 'http://127.0.0.1:8088 (stop with just stop-preview)'

# Shut down the interactive preview and erase its disposable emulator data.
stop-preview:
    docker compose -f compose.yaml -f compose.preview.yaml down --volumes
