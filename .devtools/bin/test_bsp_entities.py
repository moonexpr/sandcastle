import struct
import unittest

from bsp_entities import BspError, parse_entity_lump, read_entity_lump


def bsp_with_entity_text(text: bytes, version: int = 20) -> bytes:
    header_size = 4 + 4 + 64 * 16 + 4
    lumps = bytearray(64 * 16)
    struct.pack_into("<iiii", lumps, 0, header_size, len(text), 0, 0)
    return b"VBSP" + struct.pack("<i", version) + bytes(lumps) + struct.pack("<i", 1) + text


class ReadEntityLump(unittest.TestCase):
    def test_reads_uncompressed_lump_zero(self):
        data = bsp_with_entity_text(b'{\n"classname" "worldspawn"\n}\n\x00')
        self.assertEqual(read_entity_lump(data), '{\n"classname" "worldspawn"\n}\n')

    def test_rejects_non_bsp(self):
        with self.assertRaises(BspError):
            read_entity_lump(b"NOPE" + bytes(2000))


class ParseEntityLump(unittest.TestCase):
    def test_keeps_repeated_output_keys_in_order(self):
        text = (
            '{\n"classname" "trigger_multiple"\n'
            '"OnStartTouch" "door,Open,,0,-1"\n'
            '"OnStartTouch" "relay,Trigger,,1,-1"\n}\n'
            '{\n"classname" "info_target"\n"targetname" "t"\n}\n'
        )
        first, second = parse_entity_lump(text)
        self.assertEqual(first.classname, "trigger_multiple")
        self.assertEqual(
            first.values("OnStartTouch"),
            ["door,Open,,0,-1", "relay,Trigger,,1,-1"],
        )
        self.assertEqual(second.get("targetname"), "t")

    def test_entity_without_classname_is_refused(self):
        with self.assertRaises(BspError):
            parse_entity_lump('{\n"targetname" "x"\n}\n')


if __name__ == "__main__":
    unittest.main()
