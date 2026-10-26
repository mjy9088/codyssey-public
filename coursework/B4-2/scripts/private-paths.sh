#!/bin/sh

private_path_has_symlink() {
  private_path=$1
  private_current=
  private_old_ifs=$IFS
  IFS=/
  set -f
  set -- $private_path
  set +f
  IFS=$private_old_ifs
  for private_component do
    test -n "$private_component" || continue
    private_current=$private_current/$private_component
    test ! -L "$private_current" || return 0
  done
  return 1
}

prepare_private_paths() {
  private_root=$1
  private_input=$2
  private_evidence=$3
  case "$private_input" in /*) ;; *) printf 'Input ZIP path must be absolute\n' >&2; exit 2 ;; esac
  case "$private_evidence" in /*) ;; *) printf 'Evidence root path must be absolute\n' >&2; exit 2 ;; esac
  test -f "$private_input" || { printf 'Input ZIP not found: %s\n' "$private_input" >&2; exit 2; }
  if private_path_has_symlink "$private_input"; then printf 'Input ZIP path must not contain symlinks\n' >&2; exit 2; fi
  private_public_root=$private_root
  private_ancestor=$private_root
  while test "$private_ancestor" != /; do
    if test -e "$private_ancestor/.git"; then private_public_root=$private_ancestor; break; fi
    private_ancestor=$(dirname "$private_ancestor")
  done
  input=$(realpath "$private_input")
  case "$input" in
    "$private_public_root/.local/B4-2/agent-app-leak.zip") ;;
    "$private_public_root"|"$private_public_root"/*) printf 'Input ZIP must remain outside the public checkout except at .local/B4-2/agent-app-leak.zip\n' >&2; exit 2 ;;
  esac
  private_size=$(wc -c <"$input")
  test "$private_size" -le 52428800 || { printf 'Input ZIP exceeds 50 MiB safety bound\n' >&2; exit 2; }
  if private_path_has_symlink "$private_evidence"; then printf 'Evidence root path must not contain symlinks\n' >&2; exit 2; fi
  private_evidence=$(realpath -m "$private_evidence")
  case "$private_evidence" in
    "$private_public_root/.local/evidence/B4-2") ;;
    "$private_public_root"|"$private_public_root"/*) printf 'Evidence root must remain outside the public checkout except at .local/evidence/B4-2\n' >&2; exit 2 ;;
  esac
  if test -e "$private_evidence"; then
    test -d "$private_evidence" || { printf 'Evidence root must be a directory\n' >&2; exit 2; }
  else
    mkdir -m 0700 -p "$private_evidence"
  fi
  chmod 0700 "$private_evidence"
  run_dir=$(mktemp -d "$private_evidence/run.XXXXXX")
  chmod 0700 "$run_dir"
}
