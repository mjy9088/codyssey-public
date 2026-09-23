#!/usr/bin/env python3
"""증거 커밋의 HEAD가 아니라 지정한 tag의 내용과 제출 증거를 검증한다."""

import argparse
import hashlib
import io
import json
import os
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parent.parent
SCREENSHOT_DIR = PROJECT_ROOT / "docs" / "submission" / "screenshots"


def run(*command: str, cwd: Path = PROJECT_ROOT, env: dict[str, str] | None = None) -> str:
    return subprocess.run(
        command,
        cwd=cwd,
        env=env,
        check=True,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    ).stdout


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def extract_revision(revision: str, destination: Path) -> None:
    archive = subprocess.run(
        ["git", "archive", "--format=tar", revision],
        cwd=PROJECT_ROOT,
        check=True,
        stdout=subprocess.PIPE,
    ).stdout
    with tarfile.open(fileobj=io.BytesIO(archive), mode="r:") as archive_file:
        archive_file.extractall(destination, filter="data")


def fail(message: str) -> None:
    raise SystemExit(f"FAIL: {message}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--tag", required=True, help="검증할 annotated tag")
    parser.add_argument(
        "--allow-missing-vscode",
        action="store_true",
        help="실제 VS Code 캡처 전 중간 점검에서만 사용",
    )
    args = parser.parse_args()

    if run("git", "cat-file", "-t", args.tag).strip() != "tag":
        fail("--tag에는 annotated tag를 지정해야 합니다.")
    revision = run("git", "rev-parse", f"{args.tag}^{{commit}}").strip()
    remote = run("git", "remote", "get-url", "origin").strip()

    metadata = json.loads((PROJECT_ROOT / "docs/submission/metadata.json").read_text(encoding="utf-8"))
    expected_metadata = {"tag": args.tag, "revision": revision, "origin": remote}
    if metadata != expected_metadata:
        fail("metadata.json이 현재 tag 또는 origin과 다릅니다. refresh 스크립트를 실행하세요.")

    evidence_manifest = json.loads(
        (PROJECT_ROOT / "docs/evidence/snapshots/manifest.json").read_text(encoding="utf-8")
    )
    svg_manifest = json.loads(
        (SCREENSHOT_DIR / "svg-manifest.json").read_text(encoding="utf-8")
    )
    raster_manifest = json.loads(
        (SCREENSHOT_DIR / "raster-manifest.json").read_text(encoding="utf-8")
    )
    if raster_manifest.get("resvg_revision") != "68b14c4c3bccdb60344c777406486b54c36ec1a4":
        fail("검증되지 않은 resvg revision으로 PNG가 생성되었습니다.")
    if raster_manifest.get("font_package") != "fonts-noto-cjk=1:20220127+repack1-1":
        fail("검증되지 않은 글꼴 패키지로 PNG가 생성되었습니다.")
    for name, manifest in (
        ("터미널", evidence_manifest),
        ("SVG", svg_manifest),
        ("PNG", raster_manifest),
    ):
        if manifest.get("revision_input") != args.tag or manifest.get("revision") != revision:
            fail(f"{name} 증거가 지정한 tag에서 생성되지 않았습니다.")

    for relative_path, record in evidence_manifest.get("files", {}).items():
        path = PROJECT_ROOT / relative_path
        if not path.is_file() or sha256(path) != record.get("sha256"):
            fail(f"터미널 증거가 없거나 해시가 다릅니다: {relative_path}")

    for relative_path, record in svg_manifest.get("svgs", {}).items():
        path = PROJECT_ROOT / relative_path
        source = PROJECT_ROOT / record["source"]
        if sha256(source) != record.get("source_sha256"):
            fail(f"SVG의 원본 텍스트 해시가 다릅니다: {record['source']}")
        if not path.is_file() or sha256(path) != record.get("sha256"):
            fail(f"SVG가 없거나 해시가 다릅니다: {relative_path}")

    for relative_path, record in raster_manifest.get("pngs", {}).items():
        path = PROJECT_ROOT / relative_path
        source = PROJECT_ROOT / record["source"]
        if sha256(source) != record.get("source_sha256"):
            fail(f"PNG의 원본 SVG 해시가 다릅니다: {record['source']}")
        if not path.is_file() or sha256(path) != record.get("sha256"):
            fail(f"PNG가 없거나 해시가 다릅니다: {relative_path}")

    vscode_path = SCREENSHOT_DIR / "vscode-environment.png"
    if not vscode_path.is_file() and not args.allow_missing_vscode:
        fail(f"실제 VS Code 스크린샷이 없습니다: {vscode_path.relative_to(PROJECT_ROOT)}")

    proof = PROJECT_ROOT / "docs/evidence/snapshots/github-clone-pull.txt"
    if not proof.is_file() or f"remote={remote}" not in proof.read_text(encoding="utf-8"):
        fail("현재 origin에서 수행한 GitHub clone/pull 증거가 없습니다.")

    with tempfile.TemporaryDirectory(prefix="quiz-tag-test-") as directory:
        source = Path(directory)
        extract_revision(args.tag, source)
        environment = {**os.environ, "PYTHONPATH": str(source / "quiz_game" / "src")}
        print(run(sys.executable, "-m", "unittest", "discover", "-s", "quiz_game/tests", "-v", cwd=source, env=environment), end="")

    print(run("sh", "scripts/verify_public_origin.sh", args.tag), end="")
    print(f"PASS: 제출 증거와 공개 origin이 annotated tag {args.tag}를 기준으로 일치합니다.")


if __name__ == "__main__":
    main()
