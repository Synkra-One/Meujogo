"""Exercise real power, combat and objective modules with deterministic services.

Usage: python3 tests/run_survivor_powers.py /path/to/luau
Does not simulate Roblox physics or replace a multiplayer Studio playtest.
"""
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
MODULES = {
    "CharacterData": "src/ReplicatedStorage/Modules/CharacterData.lua",
    "SurvivorPowerStatus": "src/server/SurvivorPowerStatus.lua",
    "SurvivorPowerSystem": "src/server/SurvivorPowerSystem.lua",
    "DamageSystem": "src/server/DamageSystem.lua",
    "RadioObjective": "src/server/RadioObjective.lua",
    "RaftObjective": "src/server/RaftObjective.lua",
}
sources = "local sources = {}\n" + "\n".join(
    f'sources["{name}"] = [====[\n{(ROOT / path).read_text()}\n]====]'
    for name, path in MODULES.items()
)
with tempfile.TemporaryDirectory(prefix="naufragos-powers-") as directory:
    runner = pathlib.Path(directory) / "powers.luau"
    runner.write_text(sources + "\n" + (ROOT / "tests/survivor_powers.luau").read_text())
    subprocess.run([sys.argv[1] if len(sys.argv) > 1 else "luau", str(runner)], check=True)
