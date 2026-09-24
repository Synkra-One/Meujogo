"""Run the server regression scenarios with the standalone Luau interpreter.

Usage: python3 tests/run_waiting_room.py /path/to/luau
Roblox services are simulated; this does not replace a Studio multiplayer test.
"""
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
MODULES = {
	"GameConfig": "src/ReplicatedStorage/Modules/GameConfig.lua",
    "CharacterData": "src/ReplicatedStorage/Modules/CharacterData.lua",
    "SurvivorSelectionConfig": "src/ReplicatedStorage/Modules/SurvivorSelectionConfig.lua",
    "LoadoutData": "src/ReplicatedStorage/Modules/LoadoutData.lua",
    "StatScaling": "src/ReplicatedStorage/Modules/StatScaling.lua",
    "CharacterStatsApplier": "src/server/CharacterStatsApplier.lua",
    "RoleAssignment": "src/server/RoleAssignment.lua",
    "WaitingRoomManager": "src/server/WaitingRoomManager.lua",
    "RoundManager": "src/server/RoundManager.lua",
}

sources = "local sources = {}\n" + "\n".join(
    f'sources["{name}"] = [====[\n{(ROOT / path).read_text()}\n]====]'
    for name, path in MODULES.items()
)
# The real service owns Roblox Heartbeat/Workspace instances, which are not
# part of this focused waiting-room double. Preserve the service contract for
# the state transition assertions without pulling the runtime implementation
# into the standalone harness.
sources += '''\nsources["MatchStateService"] = [====[\nlocal ReplicatedStorage = game:GetService("ReplicatedStorage")\nreturn {\n\tSet = function(value) ReplicatedStorage:SetAttribute("MatchState", value) end,\n\tIsGameplayEnabled = function(player) return player:GetAttribute("GameplayEnabled") == true end,\n}\n]====]\n'''
with tempfile.TemporaryDirectory(prefix="meujogo-tests-") as directory:
    runner = pathlib.Path(directory) / "waiting_room.luau"
    runner.write_text(sources + "\n" + (ROOT / "tests/survivor_selection.luau").read_text())
    subprocess.run([sys.argv[1] if len(sys.argv) > 1 else "luau", str(runner)], check=True)
