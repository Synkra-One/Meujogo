"""Run the real Apagão do Abismo modules against deterministic Roblox doubles.

Usage: python3 tests/run_abyss_blackout.py /path/to/luau
Does not replace a multiplayer Studio playtest.
"""
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
MODULES = {
    "FlashlightRules": "src/ReplicatedStorage/Modules/FlashlightRules.lua",
    "GameConfig": "src/ReplicatedStorage/Modules/GameConfig.lua",
    "StatScaling": "src/ReplicatedStorage/Modules/StatScaling.lua",
    "AbyssBlackoutRules": "src/ReplicatedStorage/Modules/AbyssBlackoutRules.lua",
    "FearRules": "src/server/FearRules.lua",
    "FearSystem": "src/server/FearSystem.lua",
    "Elimination": "src/server/Elimination.lua",
    "StaminaSystem": "src/server/StaminaSystem.lua",
    "AbyssBlackout": "src/server/AbyssBlackout.lua",
}

# The flashlight is blocked by ONE shared attribute list. If server and client
# ever stop reading that same list, the Tool would keep working on one side.
flags = (ROOT / "src/ReplicatedStorage/Modules/FlashlightConfig.lua").read_text()
assert "BlockingFlags" in flags and '"AbyssBlackout"' in flags, "AbyssBlackout must be a blocking flag"
for consumer in ("src/server/FlashlightSystem.lua", "src/client/FlashlightController.client.luau"):
    source = (ROOT / consumer).read_text()
    assert "for _, flag in Config.BlockingFlags do" in source, f"{consumer} must read Config.BlockingFlags"
assert "function System.ForceOff" in (ROOT / "src/server/FlashlightSystem.lua").read_text()

# No second Fear variable and no second flashlight: the ability may only reach
# Fear through FearSystem.AddFear and the lamp through the shared attribute.
ability = (ROOT / "src/server/AbyssBlackout.lua").read_text()
assert 'FearSystem.AddFear(victim, amount, "AbyssBlackout")' in ability
body = ability.split("]]", 1)[1]  # drops the --[[ ... ]] header block
calls = [line for line in body.splitlines()
         if "FearSystem.AddFear" in line and not line.lstrip().startswith(("--", "\t--"))]
assert len(calls) == 1, f"Fear is applied exactly once, at activation: {calls}"
assert "SetAttribute(\"Fear\"" not in ability and "Instance.new(\"Tool\")" not in ability
assert "WalkSpeed" not in ability and "DamageSystem" not in ability and "CFrame" not in ability, \
    "no speed boost, no direct damage, no teleport"

# The remote has to exist in the Rojo tree, or require(Remotes) errors at boot.
remote = ROOT / "src/ReplicatedStorage/Remotes/AbyssBlackout.model.json"
assert remote.exists() and '"RemoteEvent"' in remote.read_text()
assert 'Remotes.AbyssBlackout = getRemote("AbyssBlackout")' in (
    ROOT / "src/ReplicatedStorage/Modules/Remotes.lua").read_text()
assert 'safeInit("AbyssBlackout", script.AbyssBlackout)' in (
    ROOT / "src/server/init.server.luau").read_text()

sources = "local sources = {}\n" + "\n".join(
    f'sources["{name}"] = [====[\n{(ROOT / path).read_text()}\n]====]'
    for name, path in MODULES.items()
)
luau = sys.argv[1] if len(sys.argv) > 1 else "luau"
runner = ROOT / "tests" / ".abyss_blackout.generated.luau"
runner.write_text(sources + "\n" + (ROOT / "tests/abyss_blackout.luau").read_text())
try:
    subprocess.run([luau, str(runner)], check=True)
finally:
    runner.unlink(missing_ok=True)
