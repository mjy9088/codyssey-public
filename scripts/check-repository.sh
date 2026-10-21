#!/bin/sh
set -eu

scan_repository() {
  root=$1
  python3 - "$root" <<'PY'
from __future__ import annotations

import html
import re
import sys
from pathlib import Path
from typing import Final
from urllib.parse import unquote

SOURCE_SUFFIXES: Final = {
    ".bash", ".c", ".cc", ".cpp", ".go", ".js", ".jsx", ".mjs", ".pl", ".py",
    ".rb", ".rs", ".sh", ".swift", ".ts", ".tsx", ".zsh",
}
LINK_PATTERN: Final = re.compile(r"!?\[[^\]]*\]\(([^)\n]+)\)")
SCHEME_PATTERN: Final = re.compile(r"^[A-Za-z][A-Za-z0-9+.-]*:")
FENCE_PATTERN: Final = re.compile(r"^ {0,3}(`{3,}|~{3,})")


def markdown_without_fences(text: str) -> str:
    lines: list[str] = []
    fence: str | None = None
    for line in text.splitlines():
        marker = FENCE_PATTERN.match(line)
        if fence is None:
            if marker is not None:
                fence = marker.group(1)[0]
            else:
                lines.append(line)
        elif marker is not None and marker.group(1)[0] == fence:
            fence = None
    return "\n".join(lines)


def local_target(raw_target: str) -> str | None:
    target = html.unescape(raw_target.strip())
    if not target:
        return None
    if target.startswith("<") and ">" in target:
        target = target[1 : target.index(">")]
    else:
        target = target.split(maxsplit=1)[0]
    if not target or target.startswith(("#", "//")) or SCHEME_PATTERN.match(target):
        return None
    return unquote(target.split("#", 1)[0].split("?", 1)[0])


def is_within_root(path: Path, root: Path) -> bool:
    try:
        path.relative_to(root)
    except ValueError:
        return False
    return True


def markdown_errors(root: Path) -> list[str]:
    errors: list[str] = []
    resolved_root = root.resolve()
    for markdown in sorted(root.rglob("*.md")):
        if markdown.is_symlink():
            continue
        relative_markdown = markdown.relative_to(root)
        text = markdown.read_text(encoding="utf-8", errors="replace")
        for match in LINK_PATTERN.finditer(markdown_without_fences(text)):
            target = local_target(match.group(1))
            if target is None or target == "":
                continue
            candidate = (root / target.lstrip("/")) if target.startswith("/") else (markdown.parent / target)
            resolved_candidate = candidate.resolve(strict=False)
            if not is_within_root(resolved_candidate, resolved_root) or not resolved_candidate.exists():
                errors.append(f"markdown-link: {relative_markdown} -> {target}")
    return errors


def root_entrypoint_errors(root: Path) -> list[str]:
    errors = [
        f"root-entrypoint: {path.name}"
        for path in sorted(root.iterdir())
        if (path.is_symlink() or path.is_file())
        and path.name != "init.sh"
        and path.suffix.lower() in SOURCE_SUFFIXES
    ]
    entrypoint = root / "init.sh"
    if entrypoint.is_symlink() or not entrypoint.is_file():
        errors.append("root-entrypoint: missing regular init.sh")
    return errors


def docker_context_errors(root: Path) -> list[str]:
    errors: list[str] = []
    for area_name in ("coursework", "environment"):
        area = root / area_name
        if area.is_symlink() or not area.is_dir():
            continue
        for project in sorted(path for path in area.iterdir() if not path.is_symlink() and path.is_dir()):
            dockerfile = project / "Dockerfile"
            dockerignore = project / ".dockerignore"
            if (dockerfile.is_symlink() or dockerfile.is_file()) and (
                dockerignore.is_symlink() or not dockerignore.is_file()
            ):
                errors.append(f"docker-context: {project.relative_to(root)}/.dockerignore")
    return errors


def main() -> int:
    root = Path(sys.argv[1])
    errors = root_entrypoint_errors(root) + markdown_errors(root) + docker_context_errors(root)
    if errors:
        for error in sorted(errors):
            print(error, file=sys.stderr)
        return 1
    print("Repository integrity checks passed.")
    return 0


raise SystemExit(main())
PY
}

case ${1-} in
  --help|-h)
    [ "$#" -eq 1 ] || { printf 'Usage: sh scripts/check-repository.sh\n' >&2; exit 2; }
    printf '%s\n' 'Usage: sh scripts/check-repository.sh' \
      'Check tracked public layout, local Markdown targets, and Docker context policies.' \
      'Requires Git, Bash, tar, and Docker; no host Python or Node.js is required.'
    ;;
  --scan)
    [ "$#" -eq 2 ] || { printf 'Usage: %s --scan ROOT\n' "$0" >&2; exit 2; }
    scan_repository "$2"
    ;;
  --scan-archive)
    [ "$#" -eq 1 ] || { printf 'Usage: %s --scan-archive\n' "$0" >&2; exit 2; }
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' 0
    trap 'exit 129' HUP
    trap 'exit 130' INT
    trap 'exit 143' TERM
    tar -xf - -C "$tmp"
    scan_repository "$tmp"
    ;;
  '')
    [ "$#" -eq 0 ] || { printf 'Usage: sh scripts/check-repository.sh\n' >&2; exit 2; }
    root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
    cd "$root"
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' 0
    trap 'exit 129' HUP
    trap 'exit 130' INT
    trap 'exit 143' TERM
    printf '%s\n' scripts/check-repository.sh tests/repository-integrity.Dockerfile \
      tests/repository-integrity-test.Dockerfile tests/repository-integrity-test.sh >"$tmp/build-files"
    tar -cf "$tmp/build.tar" -T "$tmp/build-files"
    test_image=$(docker build -q -f tests/repository-integrity-test.Dockerfile - <"$tmp/build.tar")
    docker run --rm --network none --read-only \
      --tmpfs /tmp:rw,noexec,nosuid,nodev,size=16m,mode=1777 \
      --cap-drop ALL --security-opt no-new-privileges "$test_image"
    image=$(docker build -q -f tests/repository-integrity.Dockerfile - <"$tmp/build.tar")
    git ls-files -z >"$tmp/index-files"
    bash -c '
      while IFS= read -r -d "" path; do
        if [ -e "$path" ] || [ -L "$path" ]; then
          printf "%s\0" "$path"
        fi
      done
    ' <"$tmp/index-files" >"$tmp/tracked-files"
    for path in scripts/check-repository.sh tests/repository-integrity.Dockerfile \
      tests/repository-integrity-test.Dockerfile tests/repository-integrity-test.sh; do
      if [ -e "$path" ] && ! git ls-files --error-unmatch -- "$path" >/dev/null 2>&1; then
        printf '%s\0' "$path" >>"$tmp/tracked-files"
      fi
    done
    tar --null -cf "$tmp/repository.tar" -T "$tmp/tracked-files"
    docker run --rm -i --network none --read-only \
      --tmpfs /tmp:rw,noexec,nosuid,nodev,size=128m,mode=1777 \
      --cap-drop ALL --security-opt no-new-privileges "$image" --scan-archive <"$tmp/repository.tar"
    ;;
  *)
    printf 'Usage: %s [--scan ROOT]\n' "$0" >&2
    exit 2
    ;;
esac
