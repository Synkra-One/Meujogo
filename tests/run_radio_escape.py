"""Exercise the real radio/extraction flow with deterministic Roblox doubles.

Minigame timing has its own suite. This verifies the objective's prerequisites,
item consumption, interruption/reset, passenger lifecycle and camera ownership.
Physics, streaming and rendering still need the Studio playtest in docs/Radio.md.
"""
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
MODULES = {
    "Stub": "tests/robloxstub.luau",
    "GameConfig": "src/ReplicatedStorage/Modules/GameConfig.lua",
    "AssetRegistry": "src/ReplicatedStorage/Modules/AssetRegistry.lua",
    "RadioTowerGenerator": "src/server/Tools/RadioTowerGenerator.lua",
    "RadioSiteSystem": "src/server/RadioSiteSystem.lua",
    "RadioInstallSystem": "src/server/RadioInstallSystem.lua",
    "RadioObjective": "src/server/RadioObjective.lua",
    "InteractionGuard": "src/server/InteractionGuard.lua",
    "ExtractionSystem": "src/server/ExtractionSystem.lua",
    "ExtractionPassenger": "src/server/ExtractionPassenger.lua",
    "ExtractionCamera": "src/client/ExtractionCamera.lua",
    "ExtractionController": "src/client/ExtractionController.client.luau",
    "MatchStateService": "src/server/MatchStateService.lua",
    "ToolFactory": "src/ReplicatedStorage/Modules/ToolFactory.lua",
    "ItemRegistry": "src/ReplicatedStorage/Modules/ItemRegistry.lua",
    "RadioPieces": "src/server/RadioPieces.lua",
    "ItemSpawner": "src/server/Tools/ItemSpawner.lua",
}
bundle = "local sources = {}\n" + "\n".join(
    f'sources["{name}"] = [====[\n{(ROOT / path).read_text()}\n]====]'
    for name, path in MODULES.items()
)
with tempfile.TemporaryDirectory(prefix="radio-escape-") as directory:
    runner = pathlib.Path(directory) / "radio.luau"
    runner.write_text(bundle + "\n" + (ROOT / "tests/radio_escape.luau").read_text())
    subprocess.run([sys.argv[1] if len(sys.argv) > 1 else "luau", str(runner)], check=True)
