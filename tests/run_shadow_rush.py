"""Actual Luau modules, deterministic service/geometry doubles (not a Studio playtest).

python3 tests/run_shadow_rush.py /path/to/luau
"""
import pathlib
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET

ROOT = pathlib.Path(__file__).resolve().parents[1]
MODULES = {
    "GameConfig": "src/ReplicatedStorage/Modules/GameConfig.lua",
    "ShadowRushRules": "src/ReplicatedStorage/Modules/ShadowRushRules.lua",
    "ShadowRush": "src/server/ShadowRush.lua",
    "FearSystem": "src/server/FearSystem.lua",
    "FearRules": "src/server/FearRules.lua",
    "StatScaling": "src/ReplicatedStorage/Modules/StatScaling.lua",
    "Elimination": "src/server/Elimination.lua",
    "MonsterCombat": "src/server/MonsterCombat.lua",
    "StaminaSystem": "src/server/StaminaSystem.lua",
    "ShadowRushVFX": "src/ReplicatedStorage/Modules/ShadowRushVFX.lua",
    "FearPresentationRules": "src/ReplicatedStorage/Modules/FearPresentationRules.lua",
}
binary = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else pathlib.Path("luau")
compiler = binary.with_name("luau-compile")
with tempfile.TemporaryDirectory(prefix="meujogo-shadow-") as temporary:
    directory = pathlib.Path(temporary)
    if compiler.exists():
        paths = [str(ROOT / p) for p in MODULES.values()]
        paths += [str(ROOT / "src/client/ShadowRushController.client.luau")]
        for filename in ("Crouching", "Animate", "CustomShiftLock"):
            xml = ROOT / f"src/MovementPack/StarterCharacterScripts/{filename}.rbxmx"
            source = ET.parse(xml).find('.//string[@name="Source"]').text
            path = directory / f"{filename}.luau"
            path.write_text(source)
            paths.append(str(path))
        subprocess.run([str(compiler), "--null", *paths], check=True)
    sources = "local sources = {}\n" + "\n".join(
        f'sources["{name}"] = [====[\n{(ROOT / path).read_text()}\n]====]'
        for name, path in MODULES.items()
    )
    test = directory / "shadow_rush.luau"
    test.write_text(sources + "\n" + (ROOT / "tests/shadow_rush.luau").read_text())
    subprocess.run([str(binary), str(test)], check=True)
