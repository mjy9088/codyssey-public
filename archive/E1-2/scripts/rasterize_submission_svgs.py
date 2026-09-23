#!/usr/bin/env python3
"""고정 resvg 컨테이너로 제출 SVG를 PNG로 변환하고 연결 해시를 기록한다."""

import hashlib
import json
import os
import subprocess
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parent.parent
SCREENSHOT_DIR = PROJECT_ROOT / "docs" / "submission" / "screenshots"
DOCKERFILE = PROJECT_ROOT / "scripts" / "Dockerfile.svg-rasterizer"
IMAGE = "quiz-svg-rasterizer:resvg-0.48.1"


def run(*command: str) -> str:
    return subprocess.run(
        command,
        cwd=PROJECT_ROOT,
        check=True,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    ).stdout


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    svg_manifest_path = SCREENSHOT_DIR / "svg-manifest.json"
    svg_manifest = json.loads(svg_manifest_path.read_text(encoding="utf-8"))
    run("docker", "build", "--tag", IMAGE, "--file", str(DOCKERFILE), ".")
    generated: dict[str, dict[str, str]] = {}
    mount = f"type=bind,src={SCREENSHOT_DIR},dst=/work"
    user = f"{os.getuid()}:{os.getgid()}"
    for relative_svg, svg_record in svg_manifest["svgs"].items():
        svg_path = PROJECT_ROOT / relative_svg
        png_path = svg_path.with_suffix(".png")
        run(
            "docker",
            "run",
            "--rm",
            "--user",
            user,
            "--mount",
            mount,
            IMAGE,
            f"/work/{svg_path.name}",
            f"/work/{png_path.name}",
        )
        generated[str(png_path.relative_to(PROJECT_ROOT))] = {
            "source": relative_svg,
            "source_sha256": svg_record["sha256"],
            "sha256": sha256(png_path),
        }

    manifest = {
        "revision": svg_manifest["revision"],
        "revision_input": svg_manifest["revision_input"],
        "generator": str(Path(__file__).relative_to(PROJECT_ROOT)),
        "dockerfile": str(DOCKERFILE.relative_to(PROJECT_ROOT)),
        "image": IMAGE,
        "resvg_revision": "68b14c4c3bccdb60344c777406486b54c36ec1a4",
        "font_package": "fonts-noto-cjk=1:20220127+repack1-1",
        "pngs": generated,
    }
    (SCREENSHOT_DIR / "raster-manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"PASS: 고정 resvg 이미지로 제출 PNG {len(generated)}개를 생성했습니다.")


if __name__ == "__main__":
    main()
