#!/usr/bin/env python3
"""현재 origin과 검증 tag를 제출 메타데이터 및 공개 접근 증거에 반영한다."""

import argparse
import json
import subprocess
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parent.parent
METADATA_PATH = PROJECT_ROOT / "docs" / "submission" / "metadata.json"
PUBLIC_ORIGIN_SNAPSHOT = PROJECT_ROOT / "docs" / "evidence" / "snapshots" / "public-origin.txt"


def output(*command: str) -> str:
    return subprocess.run(
        command,
        cwd=PROJECT_ROOT,
        check=True,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    ).stdout


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--revision", required=True, help="검증 대상 annotated tag")
    args = parser.parse_args()

    if output("git", "cat-file", "-t", args.revision).strip() != "tag":
        raise SystemExit("FAIL: --revision에는 annotated tag를 지정해야 합니다.")

    revision = output("git", "rev-parse", f"{args.revision}^{{commit}}").strip()
    remote = output("git", "remote", "get-url", "origin").strip()
    verification = output("sh", "scripts/verify_public_origin.sh", args.revision)

    PUBLIC_ORIGIN_SNAPSHOT.write_text(verification, encoding="utf-8")
    METADATA_PATH.write_text(
        json.dumps(
            {"tag": args.revision, "revision": revision, "origin": remote},
            ensure_ascii=False,
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    print(f"PASS: {args.revision}와 현재 origin을 제출 메타데이터에 반영했습니다.")


if __name__ == "__main__":
    main()
