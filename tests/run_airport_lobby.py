"""Roda o AirportLobbyGenerator real com dublês determinísticos do Roblox.
Uso: python3 tests/run_airport_lobby.py /caminho/para/luau
"""
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
MODULES = {
    "RobloxStub": "tests/robloxstub.luau",
    "Structures": "src/server/Tools/Structures.lua",
    "AirportLobbyGenerator": "src/server/Tools/AirportLobbyGenerator.lua",
}
sources = "local sources = {}\n" + "\n".join(
    f'sources["{name}"] = [====[\n{(ROOT / path).read_text()}\n]====]'
    for name, path in MODULES.items()
)
with tempfile.TemporaryDirectory(prefix="meujogo-airport-") as directory:
    runner = pathlib.Path(directory) / "airport_lobby.luau"
    runner.write_text(sources + "\n" + (ROOT / "tests/airport_lobby.luau").read_text())
    subprocess.run([sys.argv[1] if len(sys.argv) > 1 else "luau", str(runner)], check=True)
