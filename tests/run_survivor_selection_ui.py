"""Exercise the real selection controller with UI/service doubles, plus camera math.

Does not simulate Roblox rendering, audio, physics or native focus navigation.
Usage: python3 tests/run_survivor_selection_ui.py [path/to/luau]
"""
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
MODULES = {
    "CharacterData": "src/ReplicatedStorage/Modules/CharacterData.lua",
    "SurvivorSelectionConfig": "src/ReplicatedStorage/Modules/SurvivorSelectionConfig.lua",
    "SurvivorSelectionState": "src/ReplicatedStorage/Modules/SurvivorSelectionState.lua",
    "Controller": "src/client/SurvivorSelectionController.client.luau",
}
sources = "local sources = {}\n" + "\n".join(
    f'sources["{name}"] = [====[\n{(ROOT / path).read_text()}\n]====]'
    for name, path in MODULES.items()
)
with tempfile.TemporaryDirectory(prefix="survivor-selection-ui-") as directory:
    runner = pathlib.Path(directory) / "selection_ui.luau"
    runner.write_text(sources + "\n" + (ROOT / "tests/survivor_selection_ui.luau").read_text())
    subprocess.run([sys.argv[1] if len(sys.argv) > 1 else "luau", str(runner)], check=True)
