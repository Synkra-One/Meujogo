"""Executa o gerador real da Estação Abismo e verifica sua geometria.

Uso: python3 tests/run_abyss_station.py [caminho/para/luau]
Não simula renderização, física, navegação de Humanoid nem voxels do Studio.
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
    "Structures": "src/server/Tools/Structures.lua",
    "IslandLayout": "src/server/Tools/IslandLayout.lua",
    "AbyssStationPlan": "src/server/Tools/AbyssStationPlan.lua",
    "AbyssLabFurnishings": "src/server/Tools/AbyssLabFurnishings.lua",
    "AbyssStationGenerator": "src/server/Tools/AbyssStationGenerator.lua",
    "AbyssStationRunner": "src/server/Tools/AbyssStationRunner.lua",
}
sources = "local sources = {}\n" + "\n".join(
    f'sources["{name}"] = [====[\n{(ROOT / path).read_text()}\n]====]'
    for name, path in MODULES.items()
)
with tempfile.TemporaryDirectory(prefix="meujogo-abismo-") as directory:
    runner = pathlib.Path(directory) / "abyss_station.luau"
    runner.write_text(sources + "\n" + (ROOT / "tests/abyss_station.luau").read_text())
    subprocess.run([sys.argv[1] if len(sys.argv) > 1 else "luau", str(runner)], check=True)
