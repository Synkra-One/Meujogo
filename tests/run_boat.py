"""Regras puras do barco de fuga (Modules/BoatRules.lua) com a GameConfig real.

Uso:  python3 tests/run_boat.py [caminho/para/luau]
Física do engine, render e rede ficam pro playtest descrito em docs/Barco.md.
"""
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
MODULES = {
    "Stub": "tests/robloxstub.luau",
    "GameConfig": "src/ReplicatedStorage/Modules/GameConfig.lua",
    "BoatRules": "src/ReplicatedStorage/Modules/BoatRules.lua",
}
bundle = "local sources = {}\n" + "\n".join(
    f'sources["{name}"] = [====[\n{(ROOT / path).read_text()}\n]====]'
    for name, path in MODULES.items()
)
with tempfile.TemporaryDirectory(prefix="boat-") as directory:
    runner = pathlib.Path(directory) / "boat.luau"
    runner.write_text(bundle + "\n" + (ROOT / "tests/boat.luau").read_text())
    subprocess.run([sys.argv[1] if len(sys.argv) > 1 else "luau", str(runner)], check=True)
