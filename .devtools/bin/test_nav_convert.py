import contextlib
import io
import struct
import tempfile
import unittest
import zipfile
from dataclasses import replace
from pathlib import Path

from nav_convert import (
    GMOD_LOADER,
    TF_LOADER,
    EmptyMesh,
    MissingBsp,
    NavError,
    NoNavMesh,
    Truncated,
    TrailingData,
    UnsupportedVersion,
    convert,
    load_source,
    main,
    write_nav,
)
from tf2_content import TF_DIR

TF_ATTRIBUTES = struct.pack("<I", 0x40)


def area_bytes(area_id, custom=b""):
    """One area as CNavArea::Save writes it at version 16, then any derived-class data."""
    b = struct.pack("<Ii", area_id, 0x21)
    b += struct.pack("<3f3f", 0.0, 0.0, 10.5, 50.0, 50.0, 12.25)
    b += struct.pack("<ff", 11.0, 11.5)
    b += struct.pack("<II", 1, 99) + struct.pack("<I", 0) * 3
    b += struct.pack("<B", 1) + struct.pack("<I3fB", 7, 10.0, 20.0, 30.0, 4)
    b += struct.pack("<I", 1) + struct.pack("<IBIBB", 99, 0, 98, 2, 1) + struct.pack("<IB", 7, 128)
    b += struct.pack("<H", 1)
    b += struct.pack("<II", 1, 9) + struct.pack("<I", 0)
    b += struct.pack("<ff", 3.5, 4.5)
    b += struct.pack("<4f", 1.0, 0.5, 0.25, 1.0)
    b += struct.pack("<I", 1) + struct.pack("<IB", 99, 1)
    b += struct.pack("<I", 0)
    return b + custom


LADDER = struct.pack("<If3f3ffI5I", 9, 25.0, 0.0, 0.0, 100.0, 0.0, 0.0, 0.0, 100.0, 1, 1, 0, 0, 0, 2)


def nav_bytes(sub_version=2, bsp_size=1234, areas=(1, 2), custom=TF_ATTRIBUTES, ladders=(LADDER,), tail=b""):
    b = struct.pack("<IIIIB", 0xFEEDFACE, 16, sub_version, bsp_size, 1)
    b += struct.pack("<H", 1) + struct.pack("<H", 7) + b"Cellar\0" + struct.pack("<B", 0)
    b += struct.pack("<I", len(areas)) + b"".join(area_bytes(a, custom) for a in areas)
    b += struct.pack("<I", len(ladders)) + b"".join(ladders)
    return b + tail


def bsp_with_pakfile(entries):
    pak = io.BytesIO()
    with zipfile.ZipFile(pak, "w", compression=zipfile.ZIP_LZMA) as z:
        for name, blob in entries.items():
            z.writestr(name, blob)
    header_size = 4 + 4 + 64 * 16 + 4
    lumps = bytearray(64 * 16)
    struct.pack_into("<iiii", lumps, 40 * 16, header_size, len(pak.getvalue()), 0, 0)
    return b"VBSP" + struct.pack("<i", 20) + bytes(lumps) + struct.pack("<i", 1) + pak.getvalue()


class ParseTfMesh(unittest.TestCase):
    def test_reads_every_part_of_an_area(self):
        mesh = TF_LOADER.parse(nav_bytes())
        self.assertEqual((mesh.version, mesh.sub_version, mesh.bsp_size), (16, 2, 1234))
        self.assertEqual(mesh.places.names, (b"Cellar\0",))
        first = mesh.areas[0]
        self.assertEqual([a.id for a in mesh.areas], [1, 2])
        self.assertEqual(first.connections, ((99,), (), (), ()))
        self.assertEqual([s.id for s in first.hiding_spots], [7])
        self.assertEqual(first.encounters[0].spots[0].t, 128)
        self.assertEqual((first.place, first.ladders), (1, ((9,), ())))
        self.assertEqual(first.custom, TF_ATTRIBUTES)
        self.assertEqual([l.id for l in mesh.ladders], [9])

    def test_writing_what_was_read_gives_the_same_bytes(self):
        data = nav_bytes()
        self.assertEqual(write_nav(TF_LOADER.parse(data)), data)

    def test_sub_versions_0_and_1_carry_no_area_data(self):
        for sub in (0, 1):
            with self.subTest(sub=sub):
                self.assertEqual(TF_LOADER.parse(nav_bytes(sub_version=sub, custom=b"")).areas[0].custom, b"")

    def test_refuses_what_the_loader_would_refuse(self):
        bad = {
            "magic": (b"\0\0\0\0" + nav_bytes()[4:], NavError),
            "version 15": (nav_bytes()[:4] + struct.pack("<I", 15) + nav_bytes()[8:], UnsupportedVersion),
            "sub-version 3": (nav_bytes(sub_version=3), UnsupportedVersion),
            "no areas": (nav_bytes(areas=()), EmptyMesh),
            "truncated": (nav_bytes()[:-3], Truncated),
            "trailing": (nav_bytes(tail=b"\0"), TrailingData),
        }
        for name, (data, error) in bad.items():
            with self.subTest(name), self.assertRaises(error):
                TF_LOADER.parse(data)


class ConvertForGmod(unittest.TestCase):
    def test_drops_the_tf_area_data_and_sets_sub_version_0_and_the_bsp_size(self):
        data = nav_bytes()
        converted = convert(TF_LOADER.parse(data), bsp_size=5678)
        out = write_nav(converted)
        self.assertEqual(len(out), len(data) - 4 * 2)
        again = GMOD_LOADER.parse(out)
        self.assertEqual((again.sub_version, again.bsp_size), (0, 5678))
        original = TF_LOADER.parse(data)
        self.assertEqual(again.areas, tuple(replace(a, custom=b"") for a in original.areas))
        self.assertEqual((again.places, again.ladders), (original.places, original.ladders))

    def test_gmod_cannot_read_the_unconverted_file(self):
        with self.assertRaises(NavError):
            GMOD_LOADER.parse(nav_bytes())


class FindTheMesh(unittest.TestCase):
    def test_reads_the_mesh_embedded_in_a_bsp_and_its_real_size(self):
        with tempfile.TemporaryDirectory() as tmp:
            bsp = Path(tmp) / "maps" / "pl_x.bsp"
            bsp.parent.mkdir()
            bsp.write_bytes(bsp_with_pakfile({"maps/pl_x.nav": nav_bytes()}))
            source = load_source(bsp)
            self.assertEqual((source.map, source.data, source.bsp_size), ("pl_x", nav_bytes(), bsp.stat().st_size))
            self.assertIn("pakfile", source.origin)

    def test_falls_back_to_the_embed_name(self):
        with tempfile.TemporaryDirectory() as tmp:
            bsp = Path(tmp) / "pl_x.bsp"
            bsp.write_bytes(bsp_with_pakfile({"maps/embed.nav": nav_bytes()}))
            self.assertEqual(load_source(bsp).data, nav_bytes())

    def test_a_loose_nav_beside_the_bsp_wins_as_it_does_in_tf2(self):
        with tempfile.TemporaryDirectory() as tmp:
            bsp = Path(tmp) / "pl_x.bsp"
            bsp.write_bytes(bsp_with_pakfile({"maps/pl_x.nav": nav_bytes(bsp_size=1)}))
            (Path(tmp) / "pl_x.nav").write_bytes(nav_bytes(bsp_size=2))
            self.assertEqual(load_source(bsp).data, nav_bytes(bsp_size=2))

    def test_a_loose_nav_takes_the_size_of_the_bsp_beside_it(self):
        with tempfile.TemporaryDirectory() as tmp:
            nav = Path(tmp) / "ctf_x.nav"
            nav.write_bytes(nav_bytes())
            (Path(tmp) / "ctf_x.bsp").write_bytes(b"VBSP" + bytes(96))
            self.assertEqual(load_source(nav).bsp_size, 100)

    def test_a_loose_nav_without_its_bsp_is_refused(self):
        with tempfile.TemporaryDirectory() as tmp:
            nav = Path(tmp) / "ctf_x.nav"
            nav.write_bytes(nav_bytes())
            with self.assertRaises(MissingBsp):
                load_source(nav)

    def test_a_bsp_with_no_mesh_anywhere_is_refused(self):
        with tempfile.TemporaryDirectory() as tmp:
            bsp = Path(tmp) / "pl_x.bsp"
            bsp.write_bytes(bsp_with_pakfile({"materials/x.vmt": b""}))
            with self.assertRaises(NoNavMesh):
                load_source(bsp)


def run(argv):
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        code = main(argv)
    return code, out.getvalue()


class CommandLine(unittest.TestCase):
    def test_without_out_it_writes_nothing(self):
        with tempfile.TemporaryDirectory() as tmp:
            bsp = Path(tmp) / "pl_x.bsp"
            bsp.write_bytes(bsp_with_pakfile({"maps/pl_x.nav": nav_bytes()}))
            before = sorted(Path(tmp).rglob("*"))
            code, out = run([str(bsp)])
            self.assertEqual(code, 0)
            self.assertEqual(sorted(Path(tmp).rglob("*")), before)
            self.assertIn("pl_x: 2 areas", out)

    def test_out_writes_a_mesh_gmod_can_load(self):
        with tempfile.TemporaryDirectory() as tmp:
            bsp = Path(tmp) / "pl_x.bsp"
            bsp.write_bytes(bsp_with_pakfile({"maps/pl_x.nav": nav_bytes()}))
            out_dir = Path(tmp) / "out"
            out_dir.mkdir()
            self.assertEqual(run([str(bsp), "--out", str(out_dir)])[0], 0)
            mesh = GMOD_LOADER.parse((out_dir / "pl_x.nav").read_bytes())
            self.assertEqual((mesh.sub_version, mesh.bsp_size), (0, bsp.stat().st_size))

    def test_a_bad_map_is_reported_and_the_rest_still_convert(self):
        with tempfile.TemporaryDirectory() as tmp:
            good = Path(tmp) / "pl_good.bsp"
            good.write_bytes(bsp_with_pakfile({"maps/pl_good.nav": nav_bytes()}))
            bad = Path(tmp) / "pl_bad.bsp"
            bad.write_bytes(bsp_with_pakfile({"maps/pl_bad.nav": nav_bytes()[:-3]}))
            code, out = run([str(bad), str(good)])
            self.assertEqual(code, 1)
            self.assertIn("pl_bad: FAILED", out)
            self.assertIn("pl_good: 2 areas", out)


MAPS = TF_DIR / "maps"
HALLOWEEN_MAPS = [
    "pl_bloodwater",
    "pl_breadspace",
    "pl_coal_event",
    "pl_corruption",
    "pl_fifthcurve_event",
    "pl_hasslecastle",
    "pl_millstone_event",
    "pl_precipice_event_final",
    "pl_rumble_event",
    "pl_sludgepit_event",
    "pl_spineyard",
    "pl_terror_event",
    "plr_hacksaw_event",
    "plr_hightower_event",
]


def gmod_round_trip(test, path):
    """Convert, then read the result as GMod's base CNavArea::Load does; everything but the TF data survives."""
    source = load_source(path)
    tf = TF_LOADER.parse(source.data)
    out = write_nav(convert(tf, source.bsp_size))
    gmod = GMOD_LOADER.parse(out)
    test.assertEqual(write_nav(tf), source.data)
    test.assertEqual((gmod.version, gmod.sub_version, gmod.bsp_size), (16, 0, source.bsp_size))
    test.assertEqual(gmod.areas, tuple(replace(a, custom=b"") for a in tf.areas))
    test.assertEqual((gmod.places, gmod.ladders, gmod.analyzed), (tf.places, tf.ladders, tf.analyzed))
    test.assertEqual(len(out), len(source.data) - len(b"".join(a.custom for a in tf.areas)))
    return source, tf, gmod, out


@unittest.skipUnless((MAPS / "ctf_2fort.nav").exists(), "TF2 is not installed")
class RealMeshes(unittest.TestCase):
    def test_ctf_2fort(self):
        source, tf, gmod, out = gmod_round_trip(self, MAPS / "ctf_2fort.nav")
        self.assertEqual(tf.sub_version, 2)
        self.assertEqual([a.id for a in gmod.areas], [a.id for a in tf.areas])
        self.assertEqual(len(out), len(source.data) - 4 * len(tf.areas))

    def test_pl_hasslecastle_embedded_mesh_gets_the_real_bsp_size(self):
        source, tf, gmod, _ = gmod_round_trip(self, MAPS / "pl_hasslecastle.bsp")
        self.assertIn("pakfile", source.origin)
        self.assertNotEqual(tf.bsp_size, gmod.bsp_size)
        self.assertEqual(gmod.bsp_size, (MAPS / "pl_hasslecastle.bsp").stat().st_size)

    def test_every_halloween_payload_map(self):
        for name in HALLOWEEN_MAPS:
            with self.subTest(name):
                gmod_round_trip(self, MAPS / f"{name}.bsp")


if __name__ == "__main__":
    unittest.main()
