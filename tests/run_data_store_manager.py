"""Run the real DataStoreManager (+ LevelSystem) against a deterministic
in-memory DataStore double. Not a Studio playtest, but the merge-by-delta
save path (the whole point of this module) is exercised exactly as it runs
in production: real UpdateAsync semantics, real retry/backoff code path.

Usage: python3 tests/run_data_store_manager.py /path/to/luau
"""
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
MODULES = {
    "DataStoreManager": "src/server/DataStoreManager.lua",
    "LevelSystem": "src/ReplicatedStorage/Modules/LevelSystem.lua",
}
sources = "local sources = {}\n" + "\n".join(
    f'sources["{name}"] = [====[\n{(ROOT / path).read_text()}\n]====]'
    for name, path in MODULES.items()
)
with tempfile.TemporaryDirectory(prefix="meujogo-datastore-") as directory:
    runner = pathlib.Path(directory) / "data_store_manager.luau"
    runner.write_text(sources + "\n" + (ROOT / "tests/data_store_manager.luau").read_text())
    subprocess.run([sys.argv[1] if len(sys.argv) > 1 else "luau", str(runner)], check=True)
