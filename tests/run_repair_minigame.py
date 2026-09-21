"""Exercise the real repair-minigame modules with deterministic services.

Usage: python3 tests/run_repair_minigame.py /path/to/luau
Covers authority, progress, grading, penalty, noise and cleanup.
Does not simulate Roblox physics, input or rendering -- the panel itself
still needs a Studio playtest on desktop, mobile and gamepad.
"""
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
MODULES = {
    "RepairMinigameConfig": "src/ReplicatedStorage/Modules/RepairMinigameConfig.lua",
    "RepairMinigameSystem": "src/server/RepairMinigameSystem.lua",
    "GeneratorErrorSound": "src/server/GeneratorErrorSound.lua",
    "InteractionGuard": "src/server/InteractionGuard.lua",
}
sources = "local sources = {}\n" + "\n".join(
    f'sources["{name}"] = [====[\n{(ROOT / path).read_text()}\n]====]'
    for name, path in MODULES.items()
)
with tempfile.TemporaryDirectory(prefix="naufragos-repair-") as directory:
    runner = pathlib.Path(directory) / "repair.luau"
    runner.write_text(sources + "\n" + (ROOT / "tests/repair_minigame.luau").read_text())
    subprocess.run([sys.argv[1] if len(sys.argv) > 1 else "luau", str(runner)], check=True)
