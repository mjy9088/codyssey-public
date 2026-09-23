#!/usr/bin/env python3
"""지정 revision에서 PTY 증거, SVG와 PNG를 순서대로 생성한다."""

import argparse
import subprocess
import sys
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parent.parent


def run(*command: str) -> None:
    subprocess.run(command, cwd=PROJECT_ROOT, check=True)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--revision", required=True, help="스크린샷을 생성할 Git tag 또는 commit")
    args = parser.parse_args()

    run(sys.executable, "scripts/capture_terminal_evidence.py", "--revision", args.revision)
    run(sys.executable, "scripts/render_terminal_svgs.py")
    run(sys.executable, "scripts/rasterize_submission_svgs.py")
    print(f"PASS: {args.revision} 기준 PTY → SVG → PNG 제출 증거를 생성했습니다.")


if __name__ == "__main__":
    main()
