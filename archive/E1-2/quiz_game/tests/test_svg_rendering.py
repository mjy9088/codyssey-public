import unittest

from scripts.render_terminal_svgs import display_width, render_svg, wrap_line


class SvgRenderingTest(unittest.TestCase):
    def test_counts_korean_as_two_terminal_columns(self) -> None:
        self.assertEqual(display_width("ab한글"), 6)
        self.assertEqual(wrap_line("ab한글", columns=4), ["ab한", "글"])

    def test_escapes_terminal_text_and_grows_with_content(self) -> None:
        short = render_svg("제목", "설명", "$ command\nA < B & C")
        long = render_svg("제목", "설명", "$ command\n" + "line\n" * 20)

        self.assertIn("A &lt; B &amp; C", short)
        self.assertIn('font-family="Noto Sans CJK KR"', short)
        self.assertGreater(len(long), len(short))


if __name__ == "__main__":
    unittest.main()
