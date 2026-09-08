"""Run actual Fear modules against deterministic Roblox service doubles.

Usage: python3 tests/run_fear.py /path/to/luau
Does not replace a multiplayer Studio playtest.
"""
import pathlib
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET

ROOT = pathlib.Path(__file__).resolve().parents[1]
MODULES = {
    "GameConfig": "src/ReplicatedStorage/Modules/GameConfig.lua",
    "StatScaling": "src/ReplicatedStorage/Modules/StatScaling.lua",
    "FearRules": "src/server/FearRules.lua",
    "FearSystem": "src/server/FearSystem.lua",
    "Elimination": "src/server/Elimination.lua",
    "StaminaSystem": "src/server/StaminaSystem.lua",
}
sources = "local sources = {}\n" + "\n".join(
    f'sources["{name}"] = [====[\n{(ROOT / path).read_text()}\n]====]'
    for name, path in MODULES.items()
)
with tempfile.TemporaryDirectory(prefix="meujogo-fear-") as directory:
    # Crouching lives inside XML, outside the usual *.luau compilation glob.
    movement = ET.parse(ROOT / "src/MovementPack/StarterCharacterScripts/Crouching.rbxmx")
    source = movement.find('.//string[@name="Source"]').text
    assert 'Character:GetAttribute("FearTripping")' in source
    assert 'Character:GetAttribute("FearTripSpeedCap")' in source
    compiler = pathlib.Path(sys.argv[1]).with_name("luau-compile") if len(sys.argv) > 1 else None
    if compiler and compiler.exists():
        movement_path = pathlib.Path(directory) / "Crouching.luau"
        movement_path.write_text(source)
        subprocess.run([str(compiler), "--null", str(movement_path)], check=True)
    runner = pathlib.Path(directory) / "fear.luau"
    runner.write_text(sources + "\n" + (ROOT / "tests/fear.luau").read_text())
    subprocess.run([sys.argv[1] if len(sys.argv) > 1 else "luau", str(runner)], check=True)
