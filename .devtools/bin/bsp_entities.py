#!/usr/bin/env python3
"""Dump a Source BSP's entity lump.

  bsp_entities.py MAP.bsp                 classname counts
  bsp_entities.py MAP.bsp --json          every entity, keys in lump order
  bsp_entities.py MAP.bsp --class NAME    entities of one classname, as JSON
  bsp_entities.py MAP.bsp --io            inputs fired by outputs, by target class
"""
import argparse
import json
import lzma
import re
import struct
import sys
from collections import Counter
from dataclasses import dataclass
from pathlib import Path

HEADER_LUMPS = 64
ENTITY_LUMP = 0


class BspError(Exception):
    pass


@dataclass(frozen=True)
class Entity:
    pairs: tuple[tuple[str, str], ...]

    def __post_init__(self):
        if not self.get("classname"):
            raise BspError(f"entity without a classname: {self.pairs!r}")

    @property
    def classname(self) -> str:
        return self.get("classname")

    def get(self, key: str) -> str:
        return next((v for k, v in self.pairs if k.lower() == key.lower()), "")

    def values(self, key: str) -> list[str]:
        return [v for k, v in self.pairs if k.lower() == key.lower()]


def _valve_lzma(blob: bytes) -> bytes:
    # Valve's header: "LZMA", actualSize, lzmaSize, 5 property bytes, then raw LZMA1.
    actual, _packed = struct.unpack_from("<II", blob, 4)
    props = blob[12:17]
    dict_size = struct.unpack_from("<I", props, 1)[0]
    lc, rem = props[0] % 9, props[0] // 9
    lp, pb = rem % 5, rem // 5
    filt = {"id": lzma.FILTER_LZMA1, "dict_size": dict_size, "lc": lc, "lp": lp, "pb": pb}
    out = lzma.LZMADecompressor(lzma.FORMAT_RAW, filters=[filt]).decompress(blob[17:], max_length=actual)
    return out


def read_entity_lump(data: bytes) -> str:
    if data[:4] != b"VBSP":
        raise BspError("not a VBSP file")
    ofs, length = struct.unpack_from("<ii", data, 8 + ENTITY_LUMP * 16)
    blob = data[ofs : ofs + length]
    if blob[:4] == b"LZMA":
        blob = _valve_lzma(blob)
    return blob.split(b"\x00", 1)[0].decode("utf-8", "replace")


_TOKEN = re.compile(r'"([^"]*)"|([{}])')


def parse_entity_lump(text: str) -> list[Entity]:
    entities, current, pending = [], None, None
    for quoted, brace in _TOKEN.findall(text):
        if brace == "{":
            current, pending = [], None
        elif brace == "}":
            entities.append(Entity(tuple(current)))
            current = None
        elif pending is None:
            pending = quoted
        else:
            current.append((pending, quoted))
            pending = None
    return entities


def _io_edges(entities: list[Entity]) -> Counter:
    by_name: dict[str, set[str]] = {}
    for e in entities:
        if e.get("targetname"):
            by_name.setdefault(e.get("targetname").lower(), set()).add(e.classname)
    edges = Counter()
    for e in entities:
        for key, value in e.pairs:
            parts = value.replace("\x1b", ",").split(",")
            if not key.startswith("On") or len(parts) < 5:
                continue
            target, inp = parts[0].lower(), parts[1]
            classes = by_name.get(target) or {f"<{target}>" if target.startswith("!") else "<unresolved>"}
            for cls in classes:
                edges[(e.classname, key, cls, inp)] += 1
    return edges


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("bsp", type=Path)
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--class", dest="cls")
    ap.add_argument("--io", action="store_true")
    args = ap.parse_args()
    entities = parse_entity_lump(read_entity_lump(args.bsp.read_bytes()))
    if args.json or args.cls:
        rows = [dict(pairs=list(e.pairs)) for e in entities if not args.cls or e.classname == args.cls]
        json.dump(rows, sys.stdout, indent=1)
    elif args.io:
        for (src, out, dst, inp), n in sorted(_io_edges(entities).items()):
            print(f"{n:4d}  {src}.{out} -> {dst}.{inp}")
    else:
        for cls, n in Counter(e.classname for e in entities).most_common():
            print(f"{n:5d}  {cls}")


if __name__ == "__main__":
    main()
