#!/usr/bin/env python3
"""Exercise actual firearm/lobby/pickup modules with simulated Roblox services.

Usage: python3 tests/run_firearms.py /path/to/luau
This checks gameplay contracts, not Studio physics, rendering or asset permissions.
"""
import pathlib
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET

ROOT = pathlib.Path(__file__).resolve().parents[1]
MODULES = {
    "GameConfig": "src/ReplicatedStorage/Modules/GameConfig.lua",
    "FirearmRules": "src/ReplicatedStorage/Modules/FirearmRules.lua",
    "Ammo": "src/ReplicatedStorage/Modules/Ammo.lua",
    "AmmoSystem": "src/server/AmmoSystem.lua",
    "DropItemSystem": "src/server/DropItemSystem.lua",
    "FirearmServer": "src/server/FirearmServer.lua",
    "LobbyFiringRange": "src/server/LobbyFiringRange.lua",
}

sources = "local sources = {}\n" + "\n".join(
    f'sources["{name}"] = [====[\n{(ROOT / path).read_text()}\n]====]'
    for name, path in MODULES.items()
)
tools = ET.parse(ROOT / "src/ReplicatedStorage/WeaponAssets/Tools.rbxmx")
names = [item.findtext('./Properties/string[@name="Name"]') for item in tools.iter("Item") if item.get("class") == "Tool"]
assert names == ["Glock17"], f"Only the pistol belongs in the build: {names}"
assert not any(item.get("class") in ("Script", "LocalScript", "ModuleScript") for item in tools.iter("Item")), "Unexpected code embedded in Tool assets"
with tempfile.TemporaryDirectory(prefix="meujogo-firearms-") as directory:
    # Embedded movement source is not included by a *.lua/*.luau compile glob.
    compiler = pathlib.Path(sys.argv[1]).with_name("luau-compile") if len(sys.argv) > 1 else None
    if compiler and compiler.exists():
        movement = ET.parse(ROOT / "src/MovementPack/StarterCharacterScripts/Crouching.rbxmx")
        movement_source = pathlib.Path(directory) / "Crouching.luau"
        movement_source.write_text(movement.find('.//string[@name="Source"]').text)
        subprocess.run([str(compiler), "--null", str(movement_source)], check=True)
    runner = pathlib.Path(directory) / "firearms.luau"
    runner.write_text(sources + "\n" + (ROOT / "tests/firearms.luau").read_text())
    subprocess.run([sys.argv[1] if len(sys.argv) > 1 else "luau", str(runner)], check=True)
