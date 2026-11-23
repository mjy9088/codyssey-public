import contextlib
import io
import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import main as application


def synthetic_data():
    filters = {
        f"size_{size}": {
            "cross": application.generated_pattern(size, "Cross"),
            "x": application.generated_pattern(size, "X"),
        }
        for size in (5, 13, 25)
    }
    return {
        "filters": filters,
        "patterns": {
            "size_5_case": {
                "input": application.generated_pattern(5, "Cross"),
                "expected": "+",
            }
        },
    }


class InteractiveFlowTest(unittest.TestCase):
    def test_manual_mode_retries_rows_and_reports_scores_decision_and_performance(self) -> None:
        cross = ["0 1 0", "1 1 1", "0 1 0"]
        x_shape = ["1 0 1", "0 1 0", "1 0 1"]
        inputs = ["1", "1 2", "not numbers", *cross, *x_shape, *cross]
        output = io.StringIO()

        with (
            patch("builtins.input", side_effect=inputs),
            patch.object(application.time, "perf_counter_ns", side_effect=[0, 1_000_000]),
            patch.object(application, "mac", wraps=application.mac) as measured_mac,
            contextlib.redirect_stdout(output),
        ):
            application.main()

        rendered = output.getvalue()
        self.assertEqual(rendered.count("입력 형식 오류"), 2)
        self.assertEqual(measured_mac.call_count, 12)
        self.assertIn("A 점수: 5.0", rendered)
        self.assertIn("B 점수: 1.0", rendered)
        self.assertIn("판정: A", rendered)
        self.assertIn("3x3", rendered)
        self.assertIn("9", rendered)

    def test_json_case_output_contains_both_scores_labels_and_status(self) -> None:
        output = io.StringIO()

        with contextlib.redirect_stdout(output):
            application.analyze_data(synthetic_data())

        case_line = next(
            line for line in output.getvalue().splitlines() if line.startswith("- size_5_case:")
        )
        for field in ("Cross=", "X=", "판정=Cross", "expected=Cross", "| PASS"):
            self.assertIn(field, case_line)

    def test_performance_table_measures_ten_calls_for_every_required_size(self) -> None:
        output = io.StringIO()
        timer_values = [value for _ in range(4) for value in (0, 1_000_000)]

        with (
            patch.object(application, "mac", return_value=0.0) as measured_mac,
            patch.object(application.time, "perf_counter_ns", side_effect=timer_values),
            contextlib.redirect_stdout(output),
        ):
            application.print_performance([3, 5, 13, 25])

        self.assertEqual(measured_mac.call_count, 40)
        rendered = output.getvalue()
        for size, operations in ((3, 9), (5, 25), (13, 169), (25, 625)):
            self.assertIn(f"{size}x{size}", rendered)
            self.assertIn(str(operations), rendered)

    def test_main_retries_mode_and_runs_complete_json_stage_order(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "data.json").write_text(json.dumps(synthetic_data()), encoding="utf-8")
            output = io.StringIO()
            previous = Path.cwd()
            os.chdir(root)
            try:
                with (
                    patch("builtins.input", side_effect=["invalid", "2"]),
                    contextlib.redirect_stdout(output),
                ):
                    application.main()
            finally:
                os.chdir(previous)

        rendered = output.getvalue()
        stages = ("[1] 필터 로드", "[2] 패턴 분석", "[성능 분석]", "[결과 요약]")
        self.assertEqual([rendered.index(stage) for stage in stages], sorted(rendered.index(stage) for stage in stages))
        self.assertIn("입력 오류", rendered)
        self.assertIn("총 테스트: 1개", rendered)


if __name__ == "__main__":
    unittest.main()
