"""Exercise the actual presentation/animation/audio consumers with Roblox doubles.
Synthetic asset IDs below are only consumed by doubles, never by Roblox.
"""
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
MODULES = {
    "GameConfig": "src/ReplicatedStorage/Modules/GameConfig.lua",
    "StatScaling": "src/ReplicatedStorage/Modules/StatScaling.lua",
    "FearPresentationRules": "src/ReplicatedStorage/Modules/FearPresentationRules.lua",
    "FearAnimationPlayer": "src/client/FearAnimationPlayer.lua",
    "FearPresentation": "src/client/FearPresentation.lua",
    "SoundManager": "src/server/SoundManager.lua",
}
sources = "local sources = {}\n" + "\n".join(
    f'sources["{name}"] = [====[\n{(ROOT / path).read_text()}\n]====]'
    for name, path in MODULES.items()
)
with tempfile.TemporaryDirectory(prefix="meujogo-fear-presentation-") as directory:
    runner = pathlib.Path(directory) / "presentation.luau"
    runner.write_text(sources + "\n" + (ROOT / "tests/fear_presentation.luau").read_text())
    subprocess.run([sys.argv[1] if len(sys.argv) > 1 else "luau", str(runner)], check=True)
