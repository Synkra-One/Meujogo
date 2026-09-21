"""Testa o encaixe da aparencia Meshy no monstro atual fora do Studio.

Uso: python3 tests/run_meshy_visuals.py /caminho/para/luau
Nao substitui olhar o monstro no Studio (ver docs/MonstroMeshy.md).
"""

import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
MODULES = {
    "RobloxStub": "tests/robloxstub.luau",
    "MonsterMeshyVisuals": "src/server/MonsterMeshyVisuals.lua",
    "AssetRegistry": "src/ReplicatedStorage/Modules/AssetRegistry.lua",
    "MonsterAnimationConfig": "src/ReplicatedStorage/Modules/MonsterAnimationConfig.lua",
    "AppearanceManager": "src/server/AppearanceManager.lua",  # so o texto (precisa de services do Studio)
}

sources = "local sources = {}\n" + "\n".join(
    f'sources["{name}"] = [====[\n{(ROOT / path).read_text()}\n]====]'
    for name, path in MODULES.items()
)

with tempfile.TemporaryDirectory(prefix="meujogo-meshy-visuals-") as directory:
    runner = pathlib.Path(directory) / "meshy_visuals.luau"
    runner.write_text(sources + "\n" + (ROOT / "tests/meshy_visuals.luau").read_text())
    executable = sys.argv[1] if len(sys.argv) > 1 else "luau"
    subprocess.run([executable, str(runner)], check=True)
