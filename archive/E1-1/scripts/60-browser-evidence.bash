#!/bin/bash
set -Eeuo pipefail
source /workspace/scripts/lib.bash
begin_validation "60-browser-evidence"

readonly BROWSER_IMAGE="selenium/standalone-chromium@sha256:ddcd01e43742e92eaeb3bc114a01f3e8d6b5afa326ac75aefd57a198d0d20a42"
readonly BROWSER_VERSION="138.0.7204.183"
readonly BROWSER_CONTAINER="browser-evidence"
# 브라우저 chrome도 golden의 픽셀이다. 이미지와 viewport를 고정하고, 변동하는
# window-manager 우측 경계와 하단 clock panel은 캡처에서 제외한다.
readonly DISPLAY_SIZE="1365x768"
readonly CAPTURE_SIZE="1358x744"
readonly CAPTURE_FILTER="1358:744"
readonly ACTUAL_DIR="/workspace/.local/evidence/actual"
readonly DIFF_DIR="/workspace/.local/evidence/diff"
readonly EXPECTED="/workspace/tests/expected/browser-with-address-bar.png"
readonly ACTUAL="$ACTUAL_DIR/browser-with-address-bar.png"

cleanup_browser() {
  cleanup_container "$BROWSER_CONTAINER"
}

create_browser_session() {
  local payload
  payload='{
    "capabilities": {
      "alwaysMatch": {
        "browserName": "chrome",
        "goog:chromeOptions": {
          "args": [
            "--window-position=0,0",
            "--window-size=1365,768",
            "--force-device-scale-factor=1",
            "--disable-gpu",
            "--disable-background-networking",
            "--disable-default-apps",
            "--disable-extensions",
            "--disable-features=Translate,MediaRouter",
            "--disable-sync",
            "--no-first-run"
          ]
        }
      }
    }
  }'
  curl --fail --silent \
    -H 'Content-Type: application/json' \
    --data "$payload" \
    http://127.0.0.1:4444/session
}

trap cleanup_browser EXIT
cleanup_browser
mkdir -p "$ACTUAL_DIR" "$DIFF_DIR"

section "Pinned browser environment"
docker pull "$BROWSER_IMAGE"
actual_version="$(docker run --rm --entrypoint chromium "$BROWSER_IMAGE" --version)"
test "$actual_version" = "Chromium $BROWSER_VERSION built on Debian GNU/Linux 13 (trixie)"

cat >"$ACTUAL_DIR/environment.txt" <<EOF
image=$BROWSER_IMAGE
chromium=$actual_version
display=$DISPLAY_SIZE
capture=$CAPTURE_SIZE
locale=ko-KR
timezone=UTC
device_scale_factor=1
rasterizer=software
EOF
cat "$ACTUAL_DIR/environment.txt"

section "Start a real browser on Xvfb"
# --network host는 nested Chromium에서 outer DinD의 localhost:8080을 그대로 보이게 한다.
docker run -d --name "$BROWSER_CONTAINER" --network host \
  --shm-size 2g \
  --mount "type=bind,source=$ACTUAL_DIR,target=/output" \
  -e SE_SCREEN_WIDTH=1365 \
  -e SE_SCREEN_HEIGHT=768 \
  -e SE_SCREEN_DEPTH=24 \
  -e SE_NODE_SESSION_TIMEOUT=60 \
  "$BROWSER_IMAGE"

for ((attempt = 1; attempt <= 30; attempt++)); do
  curl --fail --silent http://127.0.0.1:4444/status >/dev/null && break
  sleep 1
done
curl --fail --silent http://127.0.0.1:4444/status

session_response="$(create_browser_session)"
session_id="$(jq -er '.value.sessionId' <<<"$session_response")"

curl --fail --silent \
  -H 'Content-Type: application/json' \
  --data '{"url":"http://localhost:8080"}' \
  "http://127.0.0.1:4444/session/$session_id/url"
test "$(curl --fail --silent \
  "http://127.0.0.1:4444/session/$session_id/url" | jq -r '.value')" = \
  "http://localhost:8080/"

# 페이지 페인트가 끝난 뒤 Xvfb framebuffer 전체를 캡처하므로 주소창도 포함된다.
sleep 1
rm -f "$ACTUAL"
docker exec --user root "$BROWSER_CONTAINER" ffmpeg \
  -loglevel error \
  -f x11grab \
  -draw_mouse 0 \
  -video_size "$DISPLAY_SIZE" \
  -i :99.0 \
  -vf "crop=$CAPTURE_FILTER:0:0" \
  -frames:v 1 \
  -threads 1 \
  -compression_level 9 \
  -pred mixed \
  -y /output/browser-with-address-bar.png
test -s "$ACTUAL"
sha256sum "$ACTUAL"

section "Binary regression"
if [[ "${1:-}" == "--update-golden" ]]; then
  cp "$ACTUAL" "$EXPECTED"
  echo "Golden screenshot updated explicitly."
elif [[ -f "$EXPECTED" ]]; then
  if ! cmp --silent "$EXPECTED" "$ACTUAL"; then
    cp "$ACTUAL" "$DIFF_DIR/actual.png"
    cp "$EXPECTED" "$DIFF_DIR/expected.png"
    echo "Binary screenshot mismatch; inspect .local/evidence/diff/." >&2
    exit 1
  fi
  sha256sum "$EXPECTED"
  echo "Screenshot is byte-for-byte identical to the golden file."
else
  echo "Golden screenshot is absent." >&2
  echo "Review the actual image, then run:" >&2
  echo "  bash scripts/60-browser-evidence.bash --update-golden" >&2
  exit 1
fi

end_validation
