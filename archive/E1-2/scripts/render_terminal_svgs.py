#!/usr/bin/env python3
"""고정된 텍스트 증거를 브라우저 없이 제출용 SVG로 렌더링한다."""

import hashlib
import json
import unicodedata
from html import escape
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parent.parent
SNAPSHOT_DIR = PROJECT_ROOT / "docs" / "evidence" / "snapshots"
OUTPUT_DIR = PROJECT_ROOT / "docs" / "submission" / "screenshots"
FONT_FAMILY = "Noto Sans CJK KR"
MAX_COLUMNS = 102

EVIDENCE = {
    "environment": ("개발 환경", "Python, Git과 운영체제", "environment.txt"),
    "add-quiz": ("퀴즈 추가", "프롬프트와 실제 입력, 저장 결과", "quiz-add-quiz.txt"),
    "quiz-list": ("퀴즈 목록", "추가한 문제를 포함한 저장 목록", "quiz-quiz-list.txt"),
    "play-progress-score": (
        "퀴즈 플레이",
        "선택지, 실제 답안, 진행률과 현재 점수",
        "quiz-play-quiz.txt",
    ),
    "best-score": ("최고 점수", "저장된 최고 점수 확인", "quiz-best-score.txt"),
    "git-graph": ("Git 브랜치와 병합 이력", "실제 git log 출력", "git-graph.txt"),
}


def display_width(text: str) -> int:
    return sum(2 if unicodedata.east_asian_width(character) in "WF" else 1 for character in text)


def wrap_line(line: str, columns: int = MAX_COLUMNS) -> list[str]:
    if not line:
        return [""]
    wrapped: list[str] = []
    current: list[str] = []
    width = 0
    for character in line:
        character_width = display_width(character)
        if current and width + character_width > columns:
            wrapped.append("".join(current))
            current = []
            width = 0
        current.append(character)
        width += character_width
    if current:
        wrapped.append("".join(current))
    return wrapped


def render_svg(title: str, subtitle: str, transcript: str) -> str:
    lines = [part for line in transcript.rstrip().splitlines() for part in wrap_line(line)]
    line_height = 24
    terminal_top = 126
    terminal_padding = 22
    terminal_height = terminal_padding * 2 + line_height * len(lines)
    height = terminal_top + terminal_height + 54
    text_lines = "\n".join(
        f'      <tspan x="72" y="{terminal_top + terminal_padding + 18 + index * line_height}">{escape(line)}</tspan>'
        for index, line in enumerate(lines)
    )
    return f'''<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="1280" height="{height}" viewBox="0 0 1280 {height}">
  <rect width="1280" height="{height}" fill="#0b1020"/>
  <text x="50" y="62" fill="#f8fafc" font-family="{FONT_FAMILY}" font-size="30" font-weight="700">{escape(title)}</text>
  <text x="50" y="98" fill="#93c5fd" font-family="{FONT_FAMILY}" font-size="16">{escape(subtitle)}</text>
  <rect x="50" y="{terminal_top}" width="1180" height="{terminal_height}" rx="12" fill="#020617" stroke="#334155"/>
  <text fill="#d1fae5" font-family="{FONT_FAMILY}" font-size="16">
{text_lines}
  </text>
  <text x="50" y="{height - 20}" fill="#94a3b8" font-family="{FONT_FAMILY}" font-size="13">실제 PTY 출력에서 생성 · 원본 해시는 svg-manifest.json에 기록</text>
</svg>
'''


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    evidence_manifest = json.loads(
        (SNAPSHOT_DIR / "manifest.json").read_text(encoding="utf-8")
    )
    generated: dict[str, dict[str, str]] = {}
    for name, (title, subtitle, source_name) in EVIDENCE.items():
        source = SNAPSHOT_DIR / source_name
        destination = OUTPUT_DIR / f"{name}.svg"
        destination.write_text(
            render_svg(title, subtitle, source.read_text(encoding="utf-8")),
            encoding="utf-8",
        )
        generated[str(destination.relative_to(PROJECT_ROOT))] = {
            "source": str(source.relative_to(PROJECT_ROOT)),
            "source_sha256": sha256(source),
            "sha256": sha256(destination),
        }

    manifest = {
        "revision": evidence_manifest["revision"],
        "revision_input": evidence_manifest["revision_input"],
        "generator": str(Path(__file__).relative_to(PROJECT_ROOT)),
        "font_family": FONT_FAMILY,
        "svgs": generated,
    }
    (OUTPUT_DIR / "svg-manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"PASS: 제출 SVG {len(generated)}개를 생성했습니다.")


if __name__ == "__main__":
    main()
