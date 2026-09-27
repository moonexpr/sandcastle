#!/usr/bin/env python3
"""Run Lua in a running Garry's Mod through luadev's socket, and print what it printed.

  gmod_lua.py 'print(game.GetMap())'           run on the server
  gmod_lua.py --realm cl -f script.lua         run a file on the clients
  gmod_lua.py --realm sh 'return CLIENT'       run on both

luadev's socketdev listens on 127.0.0.1:27099 and has no reply channel, so the
code is wrapped in markers and its output is read back from console.log, which
GMod writes only when launched with -condebug. Values the chunk returns are
printed as @@RET lines; an error as one @@ERR line.
"""
import argparse
import socket
import sys
import time
import uuid
from dataclasses import dataclass
from enum import Enum
from pathlib import Path

GMOD = Path.home() / (
    "Library/Application Support/CrossOver/Bottles/Team Fortress 2/"
    "drive_c/Steam/steamapps/common/GarrysMod/garrysmod"
)
CONSOLE_LOG = GMOD / "console.log"
LUADEV = ("127.0.0.1", 27099)


class Realm(Enum):
    SERVER = "sv"
    CLIENT = "cl"
    SHARED = "sh"


@dataclass(frozen=True)
class RunResult:
    realm: Realm
    output: list[str]
    returns: list[str]
    error: str | None


class BridgeDown(Exception):
    pass


def long_string(code: str) -> str:
    level = 0
    while f"]{'=' * level}]" in code:
        level += 1
    eq = "=" * level
    return f"[{eq}[{code}]{eq}]"


def wrap(code: str, run_id: str) -> str:
    return f"""do
local id = "{run_id}"
print("@@LUADEV-BEGIN {run_id} " .. (SERVER and "sv" or "cl"))
local fn = CompileString({long_string(code)}, "gmod_lua:" .. id, false)
if isstring(fn) then
  print("@@ERR " .. fn)
else
  local r = {{ pcall(fn) }}
  if r[1] then
    for i = 2, table.maxn(r) do print("@@RET " .. tostring(r[i])) end
  else
    print("@@ERR " .. tostring(r[2]))
  end
end
print("@@LUADEV-END {run_id}")
end"""


def extract_runs(log: str, run_id: str) -> list[RunResult]:
    runs, current = [], None
    for line in log.splitlines():
        if line.startswith(f"@@LUADEV-BEGIN {run_id} "):
            current = (Realm(line.rsplit(" ", 1)[1]), [], [], [None])
        elif current is None:
            continue
        elif line == f"@@LUADEV-END {run_id}":
            realm, output, returns, error = current
            runs.append(RunResult(realm, output, returns, error[0]))
            current = None
        elif line.startswith("@@RET "):
            current[2].append(line[6:])
        elif line.startswith("@@ERR "):
            current[3][0] = line[6:]
        else:
            current[1].append(line)
    return runs


def send(realm: Realm, code: str, label: str) -> None:
    try:
        with socket.create_connection(LUADEV, timeout=3) as s:
            s.sendall(f"{realm.value}\n{label}\n{code}".encode())
    except OSError as e:
        raise BridgeDown(f"luadev socket {LUADEV[0]}:{LUADEV[1]} not reachable ({e}); is GMod running with luadev?") from e


def run(realm: Realm, code: str, timeout: float) -> list[RunResult]:
    if not CONSOLE_LOG.exists():
        raise BridgeDown(f"{CONSOLE_LOG} missing; launch GMod with -condebug")
    start = CONSOLE_LOG.stat().st_size
    run_id = uuid.uuid4().hex[:10]
    send(realm, wrap(code, run_id), "gmod_lua")
    expected = 2 if realm is Realm.SHARED else 1
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        with CONSOLE_LOG.open("rb") as f:
            f.seek(start)
            runs = extract_runs(f.read().decode("utf-8", "replace"), run_id)
        if len(runs) >= expected:
            return runs
        time.sleep(0.2)
    return runs


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("code", nargs="?")
    ap.add_argument("-f", "--file", type=Path)
    ap.add_argument("--realm", choices=[r.value for r in Realm], default="sv")
    ap.add_argument("--timeout", type=float, default=10)
    args = ap.parse_args()
    code = args.file.read_text() if args.file else args.code
    if code is None:
        ap.error("give code or --file")
    try:
        runs = run(Realm(args.realm), code, args.timeout)
    except BridgeDown as e:
        print(f"bridge down: {e}", file=sys.stderr)
        return 2
    if not runs:
        print("no result before the timeout (did the chunk hang, or is the map not loaded?)", file=sys.stderr)
        return 3
    failed = False
    for r in runs:
        print(f"[{r.realm.value}]")
        for line in r.output:
            print(line)
        for value in r.returns:
            print(f"=> {value}")
        if r.error:
            print(f"ERROR {r.error}")
            failed = True
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
