"""Run real camera/occlusion code with deterministic geometry/service doubles.

Also parse all edited embedded scripts. Rendering and actual Roblox shapecasts
still require the Studio scenarios in docs/Camera.md.
"""
import pathlib
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET

ROOT = pathlib.Path(__file__).resolve().parents[1]
paths = {
    "Stub": "tests/robloxstub.luau",
    "Config": "src/ReplicatedStorage/Modules/ShoulderCameraConfig.lua",
    "Occlusion": "src/client/CameraOcclusion.lua",
    "Controller": "src/client/ShoulderCameraController.client.luau",
    "FallEffects": "src/client/FallEffects.client.luau",
    "WeaponImpact": "src/client/WeaponImpactController.client.luau",
    "ShadowRush": "src/client/ShadowRushController.client.luau",
}
sources = {name: (ROOT / path).read_text() for name, path in paths.items()}
for asset in (
    "src/MovementPack/StarterCharacterScripts/CustomShiftLock.rbxmx",
    "src/MovementPack/StarterCharacterScripts/Crouching.rbxmx",
    "src/StarterGui/Bobbing Camera.rbxmx",
):
    for index, node in enumerate(ET.parse(ROOT / asset).iter("Item")):
        source = node.find('./Properties/string[@name="Source"]')
        if source is not None:
            sources[f"{asset}:{index}"] = source.text or ""
bundle = "local sources = {}\n" + "\n".join(
    f'sources["{name}"] = [====[\n{source}\n]====]' for name, source in sources.items()
)
with tempfile.TemporaryDirectory(prefix="shoulder-camera-") as directory:
    test = pathlib.Path(directory) / "camera.luau"
    test.write_text(bundle + "\n" + (ROOT / "tests/shoulder_camera.luau").read_text())
    subprocess.run([sys.argv[1] if len(sys.argv) > 1 else "luau", str(test)], check=True)
