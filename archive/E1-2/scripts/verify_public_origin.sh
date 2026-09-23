#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
GIT_CLIENT_IMAGE=${GIT_CLIENT_IMAGE:-docker.gitea.com/gitea:1.24.7}
ORIGIN_URL=$(git -C "$PROJECT_ROOT" remote get-url origin)
REVISION=${1:-}

case "$ORIGIN_URL" in
    http://*|https://*) ;;
    *)
        echo "FAIL: origin이 비인증 HTTP(S) 접근을 검증할 수 있는 주소가 아닙니다: $ORIGIN_URL" >&2
        exit 1
        ;;
esac

authority=${ORIGIN_URL#*://}
authority=${authority%%/*}
case "$authority" in
    *@*)
        echo "FAIL: origin URL에 사용자 정보나 자격 증명이 포함되어 있습니다." >&2
        exit 1
        ;;
esac

printf 'origin=%s\n' "$ORIGIN_URL"
printf 'client_image=%s\n' "$GIT_CLIENT_IMAGE"
printf 'authentication=disabled (clean container, empty environment, no host mounts or prompts)\n'

REMOTE_REFS='HEAD refs/heads/main'
TAG_NAME=
EXPECTED_REVISION=
if [ -n "$REVISION" ]; then
    git check-ref-format "refs/tags/$REVISION" >/dev/null 2>&1 || {
        echo "FAIL: 올바른 tag 이름이 아닙니다: $REVISION" >&2
        exit 1
    }
    TAG_NAME=$REVISION
    EXPECTED_REVISION=$(git -C "$PROJECT_ROOT" rev-parse --verify "refs/tags/$TAG_NAME^{commit}" 2>/dev/null) || {
        echo "FAIL: 검증 대상은 로컬에 존재하는 tag여야 합니다: $REVISION" >&2
        exit 1
    }
    REMOTE_REFS="$REMOTE_REFS refs/tags/$TAG_NAME refs/tags/$TAG_NAME^{}"
    printf 'tag=%s\n' "$TAG_NAME"
fi

docker run --rm \
    --env "ORIGIN_URL=$ORIGIN_URL" \
    --env "REMOTE_REFS=$REMOTE_REFS" \
    --env "TAG_NAME=$TAG_NAME" \
    --env "EXPECTED_REVISION=$EXPECTED_REVISION" \
    --entrypoint sh \
    "$GIT_CLIENT_IMAGE" \
    -eu -c '
        mkdir -p /tmp/empty-home
        # env -i 뒤에 명시한 값만 Git에 전달되므로 알려지지 않은 인증 변수도 차단된다.
        env -i \
            HOME=/tmp/empty-home \
            PATH="$PATH" \
            ORIGIN_URL="$ORIGIN_URL" \
            REMOTE_REFS="$REMOTE_REFS" \
            TAG_NAME="$TAG_NAME" \
            EXPECTED_REVISION="$EXPECTED_REVISION" \
            GIT_CONFIG_GLOBAL=/dev/null \
            GIT_CONFIG_NOSYSTEM=1 \
            GIT_TERMINAL_PROMPT=0 \
            GIT_ASKPASS=/bin/false \
            sh -eu -c '\''
                result=$(git -c credential.helper= -c core.askPass=/bin/false \
                    ls-remote --exit-code "$ORIGIN_URL" $REMOTE_REFS)
                printf "%s\n" "$result"
                if [ -n "$TAG_NAME" ]; then
                    tab=$(printf "\t")
                    printf "%s\n" "$result" | grep -F \
                        "$EXPECTED_REVISION${tab}refs/tags/$TAG_NAME^{}" >/dev/null
                fi
            '\''
    '

echo "PASS: 인증 설정이 없는 컨테이너에서 origin의 공개 refs를 조회했습니다."
