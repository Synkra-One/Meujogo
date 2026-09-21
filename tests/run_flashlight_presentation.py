"""Exercise real flashlight pose/visual modules with deterministic 3D math."""
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
FILES = {
    "RobloxStub": "tests/robloxstub.luau",
    "FlashlightConfig": "src/ReplicatedStorage/Modules/FlashlightConfig.lua",
    "FlashlightRules": "src/ReplicatedStorage/Modules/FlashlightRules.lua",
    "FlashlightExposureFX": "src/client/FlashlightExposureFX.lua",
    "FlashlightPose": "src/client/FlashlightPose.lua",
    "FlashlightVisuals": "src/client/FlashlightVisuals.lua",
}
sources = "local sources = {}\n" + "\n".join(
    f'sources["{name}"] = [====[\n{(ROOT / path).read_text()}\n]====]'
    for name, path in FILES.items()
)
with tempfile.TemporaryDirectory(prefix="flashlight-presentation-") as directory:
    runner = pathlib.Path(directory) / "test.luau"
    runner.write_text(sources + (ROOT / "tests/flashlight_presentation.luau").read_text())
    subprocess.run([sys.argv[1] if len(sys.argv) > 1 else "luau", str(runner)], check=True)
