import json
import tempfile
import unittest
from pathlib import Path

from gmod_lua import Realm, RunResult, collect_results, long_string, result_files, wrap


class LongString(unittest.TestCase):
    def test_picks_a_level_the_code_does_not_contain(self):
        code = 'x = [[a]] .. [=[b]=]'
        quoted = long_string(code)
        self.assertTrue(quoted.startswith("[==["))
        self.assertTrue(quoted.endswith("]==]"))


class Wrap(unittest.TestCase):
    def test_writes_its_result_under_the_run_id(self):
        lua = wrap("print(1)", "r1")
        self.assertIn('"gmod_lua/r1_"', lua)
        self.assertIn("[[print(1)]]", lua)

    def test_restores_print_even_when_the_chunk_fails(self):
        lua = wrap("error('x')", "r1")
        self.assertLess(lua.index("pcall"), lua.index("print = saved_print"))


class ResultFiles(unittest.TestCase):
    def test_shared_waits_for_both_realms(self):
        self.assertEqual([p.name for p in result_files(Path("d"), "r1", Realm.SHARED)], ["r1_sv.txt", "r1_cl.txt"])
        self.assertEqual([p.name for p in result_files(Path("d"), "r1", Realm.CLIENT)], ["r1_cl.txt"])


class CollectResults(unittest.TestCase):
    def test_reads_finished_realms_and_skips_missing_ones(self):
        with tempfile.TemporaryDirectory() as d:
            d = Path(d)
            (d / "r1_sv.txt").write_text(json.dumps({"output": ["hello"], "returns": ["42"]}))
            results = collect_results(d, "r1", Realm.SHARED)
        self.assertEqual(results, [RunResult(Realm.SERVER, ["hello"], ["42"], None)])

    def test_error_is_carried(self):
        with tempfile.TemporaryDirectory() as d:
            d = Path(d)
            (d / "r1_cl.txt").write_text(json.dumps({"output": [], "returns": [], "error": "boom"}))
            results = collect_results(d, "r1", Realm.CLIENT)
        self.assertEqual(results, [RunResult(Realm.CLIENT, [], [], "boom")])


if __name__ == "__main__":
    unittest.main()
