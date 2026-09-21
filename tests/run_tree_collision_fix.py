"""Testa a correção isolada de colisão da Mesh_AlpTrees4 fora do Studio.

Uso: python3 tests/run_tree_collision_fix.py /caminho/para/luau
"""

import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
MODULES = {
    "RobloxStub": "tests/robloxstub.luau",
    "TreeCollisionFix": "src/server/TreeCollisionFix.lua",
}

sources = "local sources = {}\n" + "\n".join(
    f'sources["{name}"] = [====[\n{(ROOT / path).read_text()}\n]====]'
    for name, path in MODULES.items()
)

with tempfile.TemporaryDirectory(prefix="meujogo-tree-collision-") as directory:
    runner = pathlib.Path(directory) / "tree_collision_fix.luau"
    runner.write_text(sources + "\n" + (ROOT / "tests/tree_collision_fix.luau").read_text())
    executable = sys.argv[1] if len(sys.argv) > 1 else "luau"
    subprocess.run([executable, str(runner)], check=True)
