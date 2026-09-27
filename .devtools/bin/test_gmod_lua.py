import unittest

from gmod_lua import Realm, RunResult, extract_runs, long_string, wrap


class LongString(unittest.TestCase):
    def test_picks_a_level_the_code_does_not_contain(self):
        code = 'x = [[a]] .. [=[b]=]'
        quoted = long_string(code)
        self.assertTrue(quoted.startswith("[==["))
        self.assertTrue(quoted.endswith("]==]"))


class Wrap(unittest.TestCase):
    def test_brackets_the_code_with_markers_for_its_run(self):
        lua = wrap("print(1)", "r1")
        self.assertIn('"@@LUADEV-BEGIN r1 "', lua)
        self.assertIn('"@@LUADEV-END r1"', lua)
        self.assertIn("[[print(1)]]", lua)


class ExtractRuns(unittest.TestCase):
    LOG = (
        "noise\n"
        "@@LUADEV-BEGIN r1 sv\n"
        "hello\n"
        "@@RET 42\n"
        "@@LUADEV-END r1\n"
        "@@LUADEV-BEGIN r1 cl\n"
        "@@ERR lua:1: boom\n"
        "@@LUADEV-END r1\n"
        "@@LUADEV-BEGIN r2 sv\n"
    )

    def test_one_result_per_realm_that_finished(self):
        runs = extract_runs(self.LOG, "r1")
        self.assertEqual(
            runs,
            [
                RunResult(Realm.SERVER, ["hello"], ["42"], None),
                RunResult(Realm.CLIENT, [], [], "lua:1: boom"),
            ],
        )

    def test_unfinished_run_yields_nothing(self):
        self.assertEqual(extract_runs(self.LOG, "r2"), [])

    def test_other_runs_are_ignored(self):
        self.assertEqual(extract_runs(self.LOG, "r9"), [])


if __name__ == "__main__":
    unittest.main()
