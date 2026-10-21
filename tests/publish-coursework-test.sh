#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' 0 HUP INT TERM
repo=$tmp/repo
fakebin=$tmp/bin
git_log=$tmp/git.log
real_git=$(command -v git)
mkdir -p "$repo/scripts" "$repo/coursework/demo" "$fakebin"
cp "$root/scripts/publish-coursework.sh" "$repo/scripts/publish-coursework.sh"

fail() {
  printf 'publish-coursework-test: %s\n' "$*" >&2
  exit 1
}

cat >"$fakebin/git" <<'EOF'
#!/bin/sh
command_name=${1-}
if [ "$command_name" = -C ]; then
  command_name=${3-}
fi
printf '%s' "$command_name" >>"$FAKE_GIT_LOG"
for argument do
  printf '\t%s' "$argument" >>"$FAKE_GIT_LOG"
done
printf '\n' >>"$FAKE_GIT_LOG"
case $command_name in
  fetch)
    printf 'unexpected network operation: git fetch\n' >&2
    exit 91
    ;;
  push)
    printf 'simulated non-fast-forward rejection\n' >&2
    exit 1
    ;;
  worktree)
    case " $* " in
      *" worktree add "*)
        if [ -n "${FAKE_GIT_SIGNAL:-}" ]; then kill -s "$FAKE_GIT_SIGNAL" "$PPID"; fi
        ;;
    esac
    ;;
esac
GIT_MASTER=1 exec "$REAL_GIT" -c credential.helper= "$@"
EOF
chmod 0755 "$fakebin/git"

# A configured pager must not consume input intended for publication confirmation.
cat >"$fakebin/pager" <<'EOF'
#!/bin/sh
printf 'pager\n' >>"$FAKE_GIT_LOG"
dd bs=1 count=1 of=/dev/null </dev/tty 2>/dev/null
cat
EOF
chmod 0755 "$fakebin/pager"

git_run() {
  GIT_MASTER=1 "$real_git" -c credential.helper= -C "$repo" "$@"
}

GIT_MASTER=1 "$real_git" -c credential.helper= init -q "$repo"
printf '%s\n' first >"$repo/coursework/demo/value.txt"
printf '%s\n' blob >"$repo/coursework/not-a-tree"
git_run add .
GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=test@example.invalid \
  GIT_COMMITTER_NAME=Test GIT_COMMITTER_EMAIL=test@example.invalid \
  git_run commit -q -m first
first=$(git_run rev-parse HEAD)
printf '%s\n' second >"$repo/coursework/demo/value.txt"
git_run add coursework/demo/value.txt
GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=test@example.invalid \
  GIT_COMMITTER_NAME=Test GIT_COMMITTER_EMAIL=test@example.invalid \
  git_run commit -q -m second
head=$(git_run rev-parse HEAD)
printf '%s\n' uncommitted >"$repo/coursework/demo/value.txt"

run_publisher() {
  PATH=$fakebin:/usr/bin:/bin REAL_GIT=$real_git FAKE_GIT_LOG=$git_log \
    FAKE_GIT_SIGNAL=${TEST_SIGNAL-} \
    GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=test@example.invalid \
    GIT_COMMITTER_NAME=Test GIT_COMMITTER_EMAIL=test@example.invalid \
    sh "$repo/scripts/publish-coursework.sh" "$@"
}

: >"$git_log"
if run_publisher --source >"$tmp/missing-source.out" 2>&1; then
  fail '--source without a revision succeeded'
fi
grep -q 'requires a revision' "$tmp/missing-source.out" || fail 'missing --source value lacked a useful error'
if run_publisher --unknown >"$tmp/unknown.out" 2>&1; then
  fail 'unknown option succeeded'
fi
grep -q 'Unknown option' "$tmp/unknown.out" || fail 'unknown option lacked a useful error'
[ ! -s "$git_log" ] || fail 'invalid CLI input invoked Git'

: >"$git_log"
run_publisher demo https://example.invalid/submission.git >"$tmp/default.out"
grep -q "from $head" "$tmp/default.out" || fail 'default source was not the committed local HEAD'
grep -q 'No interactive terminal; the destination was not changed.' "$tmp/default.out" || fail 'no-TTY preparation did not stop before push'
! grep -q '^fetch' "$git_log" || fail 'preparation fetched from a remote'
! grep -q '^push' "$git_log" || fail 'no-TTY preparation attempted a push'
[ "$(cat "$repo/coursework/demo/value.txt")" = uncommitted ] || fail 'preparation modified the source working tree'
[ "$(git_run worktree list --porcelain | grep -c '^worktree ')" -eq 1 ] || fail 'successful preparation left a temporary worktree'

: >"$git_log"
run_publisher --source "$first" demo https://example.invalid/submission.git >"$tmp/revision.out"
prepared=$(sed -n 's/^Prepared submission commit \([^ ]*\) from .*$/\1/p' "$tmp/revision.out")
[ -n "$prepared" ] || fail 'prepared commit was not reported'
[ "$(git_run rev-parse "$prepared^")" = "$first" ] || fail '--source did not preserve the selected revision as parent'
[ "$(git_run show "$prepared:value.txt")" = first ] || fail '--source exported content from a different revision'

: >"$git_log"
if run_publisher --source "$first" not-a-tree https://example.invalid/submission.git >"$tmp/bad.out" 2>&1; then
  fail 'a blob was accepted as a coursework subtree'
fi
grep -q 'is not a directory' "$tmp/bad.out" || fail 'invalid subtree error was not specific'
! grep -q '^worktree' "$git_log" || fail 'worktree was created before subtree validation'

for signal in INT TERM; do
  : >"$git_log"
  TEST_SIGNAL=$signal
  set +e
  run_publisher demo https://example.invalid/submission.git >"$tmp/signal.out" 2>&1
  status=$?
  set -e
  case "$signal:$status" in INT:130|TERM:143) ;; *) fail 'publisher did not preserve interruption status' ;; esac
  [ "$(grep -c 'worktree.*remove' "$git_log")" -eq 1 ] || fail 'publisher cleanup did not run once'
  ! grep -q '^push' "$git_log" || fail 'interrupted preparation attempted publication'
  [ "$(git_run worktree list --porcelain | grep -c '^worktree ')" -eq 1 ] || fail 'interrupted preparation left a worktree'
done
unset TEST_SIGNAL

: >"$git_log"
set +e
printf 'y\n' | script -qec \
  "env PATH='$fakebin:/usr/bin:/bin' REAL_GIT='$real_git' FAKE_GIT_LOG='$git_log' TERM=xterm GIT_PAGER='$fakebin/pager' GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=test@example.invalid GIT_COMMITTER_NAME=Test GIT_COMMITTER_EMAIL=test@example.invalid sh '$repo/scripts/publish-coursework.sh' --source '$head' demo https://example.invalid/submission.git" \
  /dev/null \
  >"$tmp/divergence.out" 2>&1
status=$?
set -e
if [ "$status" -eq 0 ]; then
  cat "$tmp/divergence.out" >&2
  fail 'simulated diverged destination was reported as published'
fi
grep -q 'simulated non-fast-forward rejection' "$tmp/divergence.out" || fail 'divergence simulation did not reach the push boundary'
! grep -q '^pager$' "$git_log" || fail 'publication output invoked a confirmation-consuming pager'
! grep -q '^Published ' "$tmp/divergence.out" || fail 'rejected push printed a publication success message'
push_line=$(sed -n '/^push[[:space:]]/p' "$git_log")
if [ -z "$push_line" ]; then
  cat "$tmp/divergence.out" >&2
  fail 'confirmed TTY run did not attempt a push'
fi
case $push_line in
  *--force*) fail 'confirmed push used a force option' ;;
esac
printf '%s\n' "$push_line" | grep -q 'HEAD:refs/heads/main' || fail 'ordinary push targeted the wrong ref'
[ "$(git_run worktree list --porcelain | grep -c '^worktree ')" -eq 1 ] || fail 'rejected push left a temporary worktree'

printf '%s\n' 'Coursework publisher checks passed.'
