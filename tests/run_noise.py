"""Run real noise/stamina/client sources with deterministic Roblox doubles.
Usage: python3 tests/run_noise.py /path/to/luau
"""
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
MODULES = {
    "GameConfig": "src/ReplicatedStorage/Modules/GameConfig.lua",
    "StatScaling": "src/ReplicatedStorage/Modules/StatScaling.lua",
    "StaminaSystem": "src/server/StaminaSystem.lua",
    "NoiseService": "src/server/NoiseService.lua",
    "NoiseVisualizer": "src/client/NoiseVisualizer.client.luau",
}
sources = "local sources = {}\n" + "\n".join(
    f'sources["{name}"] = [====[\n{(ROOT / path).read_text()}\n]====]'
    for name, path in MODULES.items()
)
with tempfile.TemporaryDirectory(prefix="meujogo-noise-") as directory:
    runner = pathlib.Path(directory) / "noise.luau"
    runner.write_text(sources + "\n" + (ROOT / "tests/noise.luau").read_text())
    subprocess.run([sys.argv[1] if len(sys.argv) > 1 else "luau", str(runner)], check=True)
