"""Gavetas: DrawerRules + DrawerSystem reais sobre móveis reais, com dublês
do resto do servidor.
Uso: python3 tests/run_drawers.py [caminho/para/luau]
"""
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
MODULES = {
    "RobloxStub": "tests/robloxstub.luau",
    "AssetRegistry": "src/ReplicatedStorage/Modules/AssetRegistry.lua",
    "AssetLoader": "src/ReplicatedStorage/Modules/AssetLoader.lua",
    "GameConfig": "src/ReplicatedStorage/Modules/GameConfig.lua",
    "ItemRegistry": "src/ReplicatedStorage/Modules/ItemRegistry.lua",
    "Structures": "src/server/Tools/Structures.lua",
    "HouseKit": "src/server/Tools/Houses/HouseKit.lua",
    "Furniture": "src/server/Tools/Houses/Furniture.lua",
    "DrawerRules": "src/server/DrawerRules.lua",
    "DrawerSystem": "src/server/DrawerSystem.lua",
    "LootCrateSystem": "src/server/LootCrateSystem.lua",
}
sources = "local sources = {}\n" + "\n".join(
    f'sources["{name}"] = [====[\n{(ROOT / path).read_text()}\n]====]'
    for name, path in MODULES.items()
)
with tempfile.TemporaryDirectory(prefix="meujogo-gavetas-") as directory:
    runner = pathlib.Path(directory) / "drawers.luau"
    runner.write_text(sources + "\n" + (ROOT / "tests/drawers.luau").read_text())
    subprocess.run([sys.argv[1] if len(sys.argv) > 1 else "luau", str(runner)], check=True)
