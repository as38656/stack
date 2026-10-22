import unittest

from aptrepo.debversion import compare


class CompareTest(unittest.TestCase):
    def assertOrdered(self, lower, higher):
        self.assertLess(compare(lower, higher), 0, f"{lower} < {higher}")
        self.assertGreater(compare(higher, lower), 0, f"{higher} > {lower}")

    def test_equal(self):
        self.assertEqual(compare("1.0", "1.0"), 0)
        self.assertEqual(compare("0:1.0", "1.0"), 0)
        self.assertEqual(compare("1.0-0", "1.0-0"), 0)

    def test_numeric_parts_compare_as_numbers(self):
        self.assertOrdered("1.9", "1.10")
        self.assertOrdered("1.0", "1.0.1")
        self.assertOrdered("26.06.0", "26.10.0")

    def test_tilde_sorts_before_everything(self):
        self.assertOrdered("1.0~rc1", "1.0")
        self.assertOrdered("1.0~~", "1.0~")
        self.assertOrdered("1.0~rc1", "1.0~rc2")

    def test_letters_sort_before_other_symbols(self):
        self.assertOrdered("1.0", "1.0a")
        self.assertOrdered("1.0a", "1.0+")
        self.assertOrdered("1.0", "1.0+as38656.1")

    def test_epoch_wins(self):
        self.assertOrdered("2.0", "1:0.1")

    def test_revision(self):
        self.assertOrdered("1.0-1", "1.0-2")
        self.assertOrdered("1.0-1", "1.0-1+b1")
        self.assertOrdered("1.0-beta-2", "1.0-beta-10")

    def test_vpp_versions(self):
        self.assertOrdered("26.06.0-4~gf6ae22b", "26.06.0-5~g0000000")
        self.assertOrdered("26.06.0-4~gf6ae22b", "26.06.0-4~gf6ae22bd2")
        self.assertOrdered("26.06.0-40~gffffff", "26.10.0-1~g0000000")

    def test_zebra_rs_versions(self):
        self.assertOrdered("26.10.3", "26.10.3+as38656.120.g000000000")
        self.assertOrdered("26.10.3+as38656.9.gfff", "26.10.3+as38656.10.g000")
        self.assertOrdered("26.10.3+as38656.900.gfff", "26.10.4+as38656.1.g000")

    def test_invalid_versions_are_rejected(self):
        for bad in ["", "a1.0", "x:1.0", "1.0-", ":1.0", "1.0 2"]:
            with self.subTest(bad=bad), self.assertRaises(ValueError):
                compare(bad, "1.0")


if __name__ == "__main__":
    unittest.main()
