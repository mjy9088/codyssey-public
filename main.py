"""외부 라이브러리 없이 구현한 Mini NPU 콘솔 시뮬레이터."""

from __future__ import annotations

import json
import re
import time
from pathlib import Path
from typing import Any, Dict, List, Optional, Sequence, Tuple

Matrix = List[List[float]]
EPSILON = 1e-9
REPETITIONS = 10
PATTERN_KEY = re.compile(r"^size_(\d+)_(.+)$")


class DataError(ValueError):
    """입력 데이터의 형식 또는 의미가 잘못되었을 때 발생한다."""


def validate_matrix(value: Any, expected_size: int, name: str) -> Matrix:
    """값을 정사각 수치 행렬로 검증하고 float 행렬로 반환한다."""
    if not isinstance(value, list) or len(value) != expected_size:
        raise DataError(f"{name}: 행 수가 {expected_size}이어야 합니다.")
    matrix: Matrix = []
    for row_number, row in enumerate(value, start=1):
        if not isinstance(row, list) or len(row) != expected_size:
            raise DataError(
                f"{name}: {row_number}행의 열 수가 {expected_size}이어야 합니다."
            )
        if any(isinstance(item, bool) or not isinstance(item, (int, float)) for item in row):
            raise DataError(f"{name}: {row_number}행에 숫자가 아닌 값이 있습니다.")
        matrix.append([float(item) for item in row])
    return matrix


def mac(pattern: Sequence[Sequence[float]], filter_matrix: Sequence[Sequence[float]]) -> float:
    """동일 크기인 두 행렬의 Multiply-Accumulate 점수를 계산한다."""
    if len(pattern) != len(filter_matrix) or any(
        len(pattern_row) != len(filter_row)
        for pattern_row, filter_row in zip(pattern, filter_matrix)
    ):
        raise DataError("MAC 연산의 패턴과 필터 크기가 일치하지 않습니다.")
    score = 0.0
    for pattern_row, filter_row in zip(pattern, filter_matrix):
        for pattern_value, filter_value in zip(pattern_row, filter_row):
            score += pattern_value * filter_value
    return score


def decide(score_a: float, score_b: float, label_a: str, label_b: str) -> str:
    """epsilon 이내 점수는 동점으로 처리하고 그 외에는 큰 점수의 라벨을 반환한다."""
    if abs(score_a - score_b) < EPSILON:
        return "UNDECIDED"
    return label_a if score_a > score_b else label_b


def normalize_label(value: Any, source: str) -> str:
    """과제의 expected/filter 라벨을 Cross 또는 X로 정규화한다."""
    if not isinstance(value, str):
        raise DataError(f"{source} 라벨은 문자열이어야 합니다.")
    normalized = value.strip().lower()
    aliases = {"+": "Cross", "cross": "Cross", "x": "X"}
    if normalized not in aliases:
        raise DataError(f"{source} 라벨 '{value}'은 지원하지 않습니다.")
    return aliases[normalized]


def read_matrix(name: str, size: int = 3) -> Matrix:
    """행별 재입력을 지원하며 콘솔에서 행렬 하나를 읽는다."""
    print(f"{name} ({size}줄 입력, 공백 구분)")
    rows: Matrix = []
    while len(rows) < size:
        try:
            values = [float(token) for token in input().split()]
            if len(values) != size:
                raise ValueError
        except ValueError:
            print(f"입력 형식 오류: 각 줄에 {size}개의 숫자를 공백으로 구분해 입력하세요.")
            continue
        rows.append(values)
    return rows


def benchmark(pattern: Matrix, filter_matrix: Matrix, repetitions: int = REPETITIONS) -> float:
    """I/O를 제외한 MAC 함수 호출의 평균 실행 시간을 ms로 반환한다."""
    started = time.perf_counter_ns()
    for _ in range(repetitions):
        mac(pattern, filter_matrix)
    elapsed_ns = time.perf_counter_ns() - started
    return elapsed_ns / repetitions / 1_000_000


def generated_pattern(size: int, label: str) -> Matrix:
    """성능 측정을 위한 홀수 크기 Cross 또는 X 패턴을 생성한다."""
    center = size // 2
    return [
        [float((row == center or col == center) if label == "Cross" else (row == col or row + col == size - 1))
         for col in range(size)]
        for row in range(size)
    ]


def print_performance(
    sizes: Sequence[int],
    matrices: Optional[Dict[int, Tuple[Matrix, Matrix]]] = None,
) -> None:
    print("\n[성능 분석] (평균/10회)")
    print(f"{'크기':<10}{'평균 시간(ms)':>16}{'연산 횟수(N²)':>18}")
    print("-" * 44)
    for size in sizes:
        pattern, filter_matrix = (
            matrices[size] if matrices and size in matrices
            else (generated_pattern(size, "Cross"), generated_pattern(size, "Cross"))
        )
        average = benchmark(pattern, filter_matrix)
        print(f"{size}x{size:<7}{average:>16.6f}{size * size:>18}")


def run_manual_mode() -> None:
    print("\n[1] 필터 입력")
    filter_a = read_matrix("필터 A")
    filter_b = read_matrix("필터 B")
    print("필터 A, B 저장 완료")
    print("\n[2] 패턴 입력")
    pattern = read_matrix("패턴")
    score_a, score_b = mac(pattern, filter_a), mac(pattern, filter_b)
    result = decide(score_a, score_b, "A", "B")
    print("\n[3] MAC 결과")
    print(f"A 점수: {score_a}\nB 점수: {score_b}")
    print("판정: 판정 불가 (UNDECIDED)" if result == "UNDECIDED" else f"판정: {result}")
    print_performance([3], {3: (pattern, filter_a)})


def load_json(path: Path) -> Dict[str, Any]:
    try:
        with path.open(encoding="utf-8") as file:
            data = json.load(file)
    except FileNotFoundError as error:
        raise DataError(f"파일을 찾을 수 없습니다: {path}") from error
    except (OSError, json.JSONDecodeError) as error:
        raise DataError(f"JSON 파일을 읽을 수 없습니다: {error}") from error
    if not isinstance(data, dict) or not isinstance(data.get("filters"), dict) or not isinstance(data.get("patterns"), dict):
        raise DataError("최상위에 객체 형태의 filters와 patterns가 필요합니다.")
    return data


def analyze_data(data: Dict[str, Any]) -> Tuple[int, int, List[Tuple[str, str]], Dict[int, Tuple[Matrix, Matrix]]]:
    filters = data["filters"]
    prepared: Dict[int, Dict[str, Matrix]] = {}
    performance_inputs: Dict[int, Tuple[Matrix, Matrix]] = {}
    print("\n[1] 필터 로드")
    for size in (5, 13, 25):
        key = f"size_{size}"
        try:
            group = filters[key]
            if not isinstance(group, dict):
                raise DataError(f"{key}: 필터 묶음은 객체여야 합니다.")
            normalized: Dict[str, Matrix] = {}
            for raw_label, raw_matrix in group.items():
                label = normalize_label(raw_label, "filter")
                if label in normalized:
                    raise DataError(f"{key}: 정규화 후 {label} 필터가 중복됩니다.")
                normalized[label] = validate_matrix(raw_matrix, size, f"{key}.{raw_label}")
            if set(normalized) != {"Cross", "X"}:
                raise DataError(f"{key}: cross와 x 필터가 모두 필요합니다.")
            prepared[size] = normalized
            performance_inputs[size] = (normalized["Cross"], normalized["Cross"])
            print(f"OK {key}: Cross, X")
        except (KeyError, DataError) as error:
            print(f"FAIL {key}: {error}")

    passed = 0
    failures: List[Tuple[str, str]] = []
    patterns = data["patterns"]
    print("\n[2] 패턴 분석 (라벨 정규화 적용)")
    for case_id, case in patterns.items():
        try:
            match = PATTERN_KEY.fullmatch(case_id)
            if not match:
                raise DataError("키는 size_{N}_{idx} 형식이어야 합니다.")
            size = int(match.group(1))
            if size not in prepared:
                raise DataError(f"사용 가능한 size_{size} 필터가 없습니다.")
            if not isinstance(case, dict):
                raise DataError("패턴 항목은 객체여야 합니다.")
            pattern = validate_matrix(case.get("input"), size, f"{case_id}.input")
            expected = normalize_label(case.get("expected"), "expected")
            cross_score = mac(pattern, prepared[size]["Cross"])
            x_score = mac(pattern, prepared[size]["X"])
            result = decide(cross_score, x_score, "Cross", "X")
            status = "PASS" if result == expected else "FAIL"
            print(f"- {case_id}: Cross={cross_score}, X={x_score}, 판정={result}, expected={expected} | {status}")
            if status == "PASS":
                passed += 1
            else:
                failures.append((case_id, f"판정 {result}, expected {expected}"))
        except (KeyError, DataError) as error:
            failures.append((case_id, str(error)))
            print(f"- {case_id}: FAIL ({error})")
    return len(patterns), passed, failures, performance_inputs


def run_json_mode(path: Path = Path("data.json")) -> None:
    data = load_json(path)
    total, passed, failures, matrices = analyze_data(data)
    print_performance([3, 5, 13, 25], matrices)
    print("\n[결과 요약]")
    print(f"총 테스트: {total}개\n통과: {passed}개\n실패: {len(failures)}개")
    if failures:
        print("실패 케이스:")
        for case_id, reason in failures:
            print(f"- {case_id}: {reason}")


def main() -> None:
    print("=== Mini NPU Simulator ===")
    print("1. 사용자 입력 (3x3)\n2. data.json 분석")
    while True:
        choice = input("선택: ").strip()
        if choice in {"1", "2"}:
            break
        print("입력 오류: 1 또는 2를 입력하세요.")
    try:
        run_manual_mode() if choice == "1" else run_json_mode()
    except DataError as error:
        print(f"실행 오류: {error}")


if __name__ == "__main__":
    main()
