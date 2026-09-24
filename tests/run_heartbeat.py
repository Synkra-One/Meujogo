"""Run actual heartbeat sources with deterministic Roblox doubles (no engine/audio)."""
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
MODULES = {
    "GameConfig": "src/ReplicatedStorage/Modules/GameConfig.lua",
    "StatScaling": "src/ReplicatedStorage/Modules/StatScaling.lua",
    "NoiseService": "src/server/NoiseService.lua",
    "HeartbeatConfig": "src/ReplicatedStorage/Modules/HeartbeatConfig.lua",
    "HeartbeatRules": "src/ReplicatedStorage/Modules/HeartbeatRules.lua",
    "HeartbeatDetection": "src/server/HeartbeatDetection.lua",
    "HeartbeatAsset": "src/server/HeartbeatAsset.lua",
    "HeartbeatController": "src/client/HeartbeatController.client.luau",
}
sources = "local sources = {}\n" + "\n".join(
    f'sources["{name}"] = [====[\n{(ROOT / path).read_text()}\n]====]'
    for name, path in MODULES.items()
)
with tempfile.TemporaryDirectory(prefix="meujogo-heartbeat-") as directory:
    runner = pathlib.Path(directory) / "heartbeat.luau"
    runner.write_text(sources + "\n" + (ROOT / "tests/heartbeat.luau").read_text())
    subprocess.run([sys.argv[1] if len(sys.argv) > 1 else "luau", str(runner)], check=True)
