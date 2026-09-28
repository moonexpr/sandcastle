import contextlib
import io
import struct
import tempfile
import unittest
from pathlib import Path

from tf2_content import (
    TF_DIR,
    Catalog,
    ContentError,
    Kind,
    Reference,
    Vpk,
    main,
    manifest_files,
    particle_names,
    references_in_lua,
    soundscript_names,
)

INLINE = 0x7FFF


def vpk_dir(files, preload=0, archive=INLINE):
    """A version 2 VPK directory; each file keeps `preload` bytes in the tree and the rest in `archive`."""
    by_ext = {}
    for name, blob in files.items():
        path, _, file = name.rpartition("/")
        stem, _, ext = file.rpartition(".")
        by_ext.setdefault(ext, {}).setdefault(path or " ", []).append((stem, blob))
    tree, data = bytearray(), bytearray()
    for ext, paths in by_ext.items():
        tree += ext.encode() + b"\0"
        for path, items in paths.items():
            tree += path.encode() + b"\0"
            for stem, blob in items:
                head, rest = blob[:preload], blob[preload:]
                tree += stem.encode() + b"\0"
                tree += struct.pack("<IHHIIH", 0, len(head), archive, len(data), len(rest), 0xFFFF) + head
                data += rest
            tree += b"\0"
        tree += b"\0"
    tree += b"\0"
    header = struct.pack("<7I", 0x55AA1234, 2, len(tree), len(data) if archive == INLINE else 0, 0, 0, 0)
    return header + bytes(tree) + (bytes(data) if archive == INLINE else b""), bytes(data)


def pcf(names):
    header = b"<!-- dmx encoding binary 2 format pcf 1 -->\n\0"
    table = struct.pack("<h", 2) + b"DmeElement\0DmeParticleSystemDefinition\0"
    elements = struct.pack("<i", 1 + len(names)) + struct.pack("<h", 0) + b"root\0" + bytes(16)
    for name in names:
        elements += struct.pack("<h", 1) + name.encode() + b"\0" + bytes(16)
    return header + table + elements + b"attribute data follows"


SOUNDSCRIPT = """
// comment { "Commented.Out" }
"Halloween.Skeleton.Spawn"
{
    "channel"   "CHAN_STATIC"
    "rndwave"   { "wave" "misc/a.wav" "wave" "misc/b.wav" }
}
Bare.Name { "wave" "x.wav" }
"""


class ReadVpk(unittest.TestCase):
    def test_reads_inline_and_preloaded_files(self):
        files = {"models/a.mdl": b"MODEL", "scripts/b.txt": b"TEXT", "root.txt": b"R"}
        for preload in (0, 2):
            with self.subTest(preload=preload), tempfile.TemporaryDirectory() as tmp:
                path = Path(tmp) / "pak_dir.vpk"
                path.write_bytes(vpk_dir(files, preload=preload)[0])
                vpk = Vpk.open(path)
                self.assertEqual(set(vpk.names), set(files))
                self.assertEqual({n: vpk.read(n) for n in files}, files)

    def test_reads_files_from_a_numbered_archive(self):
        with tempfile.TemporaryDirectory() as tmp:
            tree, data = vpk_dir({"maps/x.nav": b"NAVDATA"}, preload=1, archive=0)
            (Path(tmp) / "pak_dir.vpk").write_bytes(tree)
            (Path(tmp) / "pak_000.vpk").write_bytes(data)
            self.assertEqual(Vpk.open(Path(tmp) / "pak_dir.vpk").read("maps/x.nav"), b"NAVDATA")

    def test_names_are_case_insensitive(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "pak_dir.vpk"
            path.write_bytes(vpk_dir({"models/a.mdl": b"M"})[0])
            self.assertEqual(Vpk.open(path).read("Models\\A.mdl"), b"M")

    def test_refuses_a_file_that_is_not_a_vpk(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "pak_dir.vpk"
            path.write_bytes(b"PK\3\4" + bytes(40))
            with self.assertRaises(ContentError):
                Vpk.open(path)


class ParseContent(unittest.TestCase):
    def test_soundscript_names_are_the_top_level_keys(self):
        self.assertEqual(soundscript_names(SOUNDSCRIPT), {"halloween.skeleton.spawn", "bare.name"})

    def test_manifest_lists_precache_and_preload_files(self):
        text = '"game_sounds_manifest" { "precache_file" "scripts/a.txt" "preload_file" "scripts/b.txt" }'
        self.assertEqual(manifest_files(text), ["scripts/a.txt", "scripts/b.txt"])

    def test_particle_names_are_the_system_definitions(self):
        self.assertEqual(particle_names(pcf(["spell_a", "spell_b"])), {"spell_a", "spell_b"})

    def test_particle_file_in_another_encoding_is_refused(self):
        with self.assertRaises(ContentError):
            particle_names(b"<!-- dmx encoding keyvalues2 1 format pcf 1 -->\n\0")


class ScanLua(unittest.TestCase):
    SOURCE = "\n".join(
        [
            'local MODEL = "models/bots/skeleton_sniper/skeleton_sniper.mdl"',
            'self:EmitSound("Halloween.Skeleton.Spawn")',
            "ParticleEffect('spell_fireball_small_red', pos, ang)",
            'SOUNDS = { "A.One", "A.Two" }',
            'icon = "vgui/spellbook_fireball"',
            'local name = "foundation.npc.zombie"',
            '-- EmitSound("Commented.Out")',
            'x = 1 -- sound = "Trailing.Comment"',
            '--[[ EmitSound("Block.Comment") ]] util.PrecacheSound("misc/x.wav")',
        ]
    )

    def test_classifies_literals_by_shape_and_by_the_name_before_them(self):
        got = [(r.kind, r.name, r.line) for r in references_in_lua(self.SOURCE, "f.lua")]
        self.assertEqual(
            got,
            [
                (Kind.MODEL, "models/bots/skeleton_sniper/skeleton_sniper.mdl", 1),
                (Kind.SOUND, "Halloween.Skeleton.Spawn", 2),
                (Kind.PARTICLE, "spell_fireball_small_red", 3),
                (Kind.SOUND, "A.One", 4),
                (Kind.SOUND, "A.Two", 4),
                (Kind.MATERIAL, "vgui/spellbook_fireball", 5),
                (Kind.SOUND, "misc/x.wav", 9),
            ],
        )

    def test_a_reference_names_its_place(self):
        (ref,) = references_in_lua('EmitSound("A.B")', "x/y.lua")
        self.assertEqual(ref, Reference(Kind.SOUND, "A.B", "x/y.lua", 1))
        self.assertEqual(ref.where, "x/y.lua:1")


class CatalogLookups(unittest.TestCase):
    catalog = Catalog(
        files=frozenset({"models/a.mdl", "sound/misc/x.wav", "materials/vgui/icon.vmt"}),
        soundscripts=frozenset({"halloween.x"}),
        particles=frozenset({"spell_a"}),
    )

    def test_finds_each_kind(self):
        found = [
            (Kind.MODEL, "Models\\A.mdl"),
            (Kind.SOUND, "Halloween.X"),
            (Kind.SOUND, "misc/x.wav"),
            (Kind.SOUND, ")misc/x.wav"),
            (Kind.PARTICLE, "spell_a"),
            (Kind.MATERIAL, "vgui/icon"),
            (Kind.MATERIAL, "vgui/icon.vmt"),
        ]
        for kind, name in found:
            with self.subTest(name=name):
                self.assertTrue(self.catalog.has(kind, name))

    def test_misses_what_is_not_there(self):
        missing = [(Kind.MODEL, "models/b.mdl"), (Kind.SOUND, "Halloween.Y"), (Kind.PARTICLE, "spell_b")]
        for kind, name in missing:
            with self.subTest(name=name):
                self.assertFalse(self.catalog.has(kind, name))


def run(argv):
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        code = main(argv)
    return code, out.getvalue()


class CommandLine(unittest.TestCase):
    def test_exit_status_says_whether_every_name_exists(self):
        with tempfile.TemporaryDirectory() as tmp:
            (Path(tmp) / "tf2_misc_dir.vpk").write_bytes(vpk_dir({"models/a.mdl": b"M"})[0])
            self.assertEqual(run(["--tf", tmp, "model", "models/a.mdl"])[0], 0)
            code, out = run(["--tf", tmp, "model", "models/a.mdl", "models/nope.mdl"])
            self.assertEqual(code, 1)
            self.assertIn("missing model models/nope.mdl", out)

    def test_lua_mode_checks_every_reference_in_the_files(self):
        with tempfile.TemporaryDirectory() as tmp:
            (Path(tmp) / "tf2_misc_dir.vpk").write_bytes(vpk_dir({"models/a.mdl": b"M"})[0])
            lua = Path(tmp) / "x.lua"
            lua.write_text('Model("models/a.mdl")\nModel("models/b.mdl")\n')
            code, out = run(["--tf", tmp, "lua", str(lua)])
            self.assertEqual(code, 1)
            self.assertIn(f"missing model models/b.mdl {lua}:2", out)
            self.assertNotIn("models/a.mdl", out)


@unittest.skipUnless((TF_DIR / "tf2_misc_dir.vpk").exists(), "TF2 is not installed")
class RealContent(unittest.TestCase):
    def test_known_model_exits_0_and_made_up_one_exits_1(self):
        self.assertEqual(run(["model", "models/bots/skeleton_sniper/skeleton_sniper.mdl"])[0], 0)
        self.assertEqual(run(["model", "models/bots/skeleton_sniper/made_up.mdl"])[0], 1)

    def test_known_soundscript_and_particle(self):
        self.assertEqual(run(["sound", "Halloween.HeadlessBossSpawn"])[0], 0)
        self.assertEqual(run(["particle", "merasmus_tp"])[0], 0)
        self.assertEqual(run(["particle", "fatty_explode"])[0], 1)


if __name__ == "__main__":
    unittest.main()
