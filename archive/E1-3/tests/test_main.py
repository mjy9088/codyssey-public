import contextlib
import io
import unittest

from main import DataError, analyze_data, decide, generated_pattern, mac, normalize_label, validate_matrix


class MiniNPUTest(unittest.TestCase):
    def test_mac_and_decision(self):
        cross = [[0, 1, 0], [1, 1, 1], [0, 1, 0]]
        x_shape = [[1, 0, 1], [0, 1, 0], [1, 0, 1]]
        self.assertEqual(mac(cross, cross), 5)
        self.assertEqual(mac(cross, x_shape), 1)
        self.assertEqual(decide(5, 1, "Cross", "X"), "Cross")

    def test_epsilon_tie(self):
        self.assertEqual(decide(0.9, 0.9 - 1e-10, "Cross", "X"), "UNDECIDED")
        self.assertEqual(decide(0.9, 0.9 - 1e-8, "Cross", "X"), "Cross")

    def test_label_normalization(self):
        self.assertEqual(normalize_label("+", "expected"), "Cross")
        self.assertEqual(normalize_label("cross", "filter"), "Cross")
        self.assertEqual(normalize_label("X", "expected"), "X")
        with self.assertRaises(DataError):
            normalize_label("circle", "expected")

    def test_matrix_validation(self):
        self.assertEqual(validate_matrix([[1, 0], [0, 1]], 2, "m"), [[1.0, 0.0], [0.0, 1.0]])
        with self.assertRaises(DataError):
            validate_matrix([[1, 0]], 2, "m")
        with self.assertRaises(DataError):
            validate_matrix([[True, 0], [0, 1]], 2, "m")

    def test_schema_error_is_isolated_to_its_case(self):
        filters = {}
        for size in (5, 13, 25):
            filters[f"size_{size}"] = {
                "cross": generated_pattern(size, "Cross"),
                "x": generated_pattern(size, "X"),
            }
        data = {
            "filters": filters,
            "patterns": {
                "size_5_good": {
                    "input": generated_pattern(5, "Cross"),
                    "expected": "+",
                },
                "size_5_bad": {"input": [[1]], "expected": "x"},
            },
        }

        with contextlib.redirect_stdout(io.StringIO()):
            total, passed, failures, _ = analyze_data(data)

        self.assertEqual((total, passed), (2, 1))
        self.assertEqual(len(failures), 1)
        self.assertEqual(failures[0][0], "size_5_bad")
        self.assertIn("행 수", failures[0][1])


if __name__ == "__main__":
    unittest.main()
