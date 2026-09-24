"""Monta as casas grandes (CampCabin, CasaDoCaseiro) com os módulos reais e
verifica portas, gavetas, móveis e Footprint.
Uso: python3 tests/run_houses.py [caminho/para/luau]
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
    "HouseKit": "src/server/Tools/Houses/HouseKit.lua",
    "Furniture": "src/server/Tools/Houses/Furniture.lua",
    "CampCabin": "src/server/Tools/Houses/CampCabin.lua",
    "CasaDoCaseiro": "src/server/Tools/Houses/CasaDoCaseiro.lua",
    "Celeiro": "src/server/Tools/Houses/Celeiro.lua",
    "CasaDaFazenda": "src/server/Tools/Houses/CasaDaFazenda.lua",
}
sources = "local sources = {}\n" + "\n".join(
    f'sources["{name}"] = [====[\n{(ROOT / path).read_text()}\n]====]'
    for name, path in MODULES.items()
    if (ROOT / path).exists()
)
with tempfile.TemporaryDirectory(prefix="meujogo-casas-") as directory:
    runner = pathlib.Path(directory) / "houses.luau"
    runner.write_text(sources + "\n" + (ROOT / "tests/houses.luau").read_text())
    subprocess.run([sys.argv[1] if len(sys.argv) > 1 else "luau", str(runner)], check=True)
