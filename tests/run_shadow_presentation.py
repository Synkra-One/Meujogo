"""Client VFX lifecycle with deterministic Roblox doubles, not a render/playtest."""
import pathlib
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET

ROOT = pathlib.Path(__file__).resolve().parents[1]
MODULES = {
    "FlashlightConfig": "src/ReplicatedStorage/Modules/FlashlightConfig.lua",
    "FlashlightRules": "src/ReplicatedStorage/Modules/FlashlightRules.lua",
    "GameConfig": "src/ReplicatedStorage/Modules/GameConfig.lua",
    "ShadowRushRules": "src/ReplicatedStorage/Modules/ShadowRushRules.lua",
    "FearPresentationRules": "src/ReplicatedStorage/Modules/FearPresentationRules.lua",
    "ShadowRushVFX": "src/ReplicatedStorage/Modules/ShadowRushVFX.lua",
    "ShadowController": "src/client/ShadowRushController.client.luau",
}
binary = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else pathlib.Path("luau")
compiler = binary.with_name("luau-compile")
with tempfile.TemporaryDirectory(prefix="shadow-presentation-") as temporary:
    directory = pathlib.Path(temporary)
    animation = ET.parse(ROOT / "src/MovementPack/StarterCharacterScripts/Animate.rbxmx").find('.//string[@name="Source"]').text
    animation_path = directory / "Animate.luau"
    animation_path.write_text(animation)
    if compiler.exists():
        subprocess.run([str(compiler), "--null", *[str(ROOT / p) for p in MODULES.values()], str(animation_path),
                        str(ROOT / "src/client/ShadowRushController.client.luau")], check=True)
    sources = "local sources = {}\n" + "\n".join(
        f'sources["{name}"] = [====[\n{(ROOT / path).read_text()}\n]====]'
        for name, path in MODULES.items()
    )
    # Exercise the integration in the actual Animate source, not a second implementation.
    integration = animation[animation.index("-- Shadow Rush uses"):animation.index('playAnimation("idle", 0.3)\npose = "Standing"')]
    sources += '\nsources["ShadowAnimation"] = [====[\n' + integration + '\n]====]\n'
    test = directory / "presentation.luau"
    test.write_text(sources + "\n" + (ROOT / "tests/shadow_presentation.luau").read_text())
    subprocess.run([str(binary), str(test)], check=True)
