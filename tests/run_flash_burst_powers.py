"""Exercise real monster RemoteEvent gates and cleanup with simulated services."""
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
FILES = {
    "GameConfig": "src/ReplicatedStorage/Modules/GameConfig.lua",
    "FlashlightConfig": "src/ReplicatedStorage/Modules/FlashlightConfig.lua",
    "FlashlightRules": "src/ReplicatedStorage/Modules/FlashlightRules.lua",
    "ShadowRushRules": "src/ReplicatedStorage/Modules/ShadowRushRules.lua",
    "ShadowRush": "src/server/ShadowRush.lua",
    "MonsterTeleport": "src/server/MonsterTeleport.lua",
    "MonsterCombat": "src/server/MonsterCombat.lua",
    "GrabService": "src/server/GrabService.lua",
}
sources = "local sources = {}\n" + "\n".join(
    f'sources["{name}"] = [====[\n{(ROOT / path).read_text()}\n]====]'
    for name, path in FILES.items()
)
# Reuse the existing service/math doubles, without its client scenarios.
fixture = (ROOT / "tests/shadow_presentation.luau").read_text().split('local config=loadModule("GameConfig")')[0]
with tempfile.TemporaryDirectory(prefix="flash-burst-powers-") as directory:
    runner = pathlib.Path(directory) / "test.luau"
    runner.write_text(sources + fixture + (ROOT / "tests/flash_burst_powers.luau").read_text())
    subprocess.run([sys.argv[1] if len(sys.argv) > 1 else "luau", str(runner)], check=True)
