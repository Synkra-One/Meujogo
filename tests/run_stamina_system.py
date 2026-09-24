"""StaminaSystem real (gasto/recuperação/teto) com dublês de jogador e Heartbeat.
Uso: python3 tests/run_stamina_system.py [caminho/para/luau]
"""
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
MODULES = {
    "RobloxStub": "tests/robloxstub.luau",
    "GameConfig": "src/ReplicatedStorage/Modules/GameConfig.lua",
    "LoadoutData": "src/ReplicatedStorage/Modules/LoadoutData.lua",
    "StatScaling": "src/ReplicatedStorage/Modules/StatScaling.lua",
    "StaminaSystem": "src/server/StaminaSystem.lua",
}
sources = "local sources = {}\n" + "\n".join(
    f'sources["{name}"] = [====[\n{(ROOT / path).read_text()}\n]====]'
    for name, path in MODULES.items()
)
with tempfile.TemporaryDirectory(prefix="meujogo-stamina-system-") as directory:
    runner = pathlib.Path(directory) / "stamina_system.luau"
    runner.write_text(sources + "\n" + (ROOT / "tests/stamina_system.luau").read_text())
    subprocess.run([sys.argv[1] if len(sys.argv) > 1 else "luau", str(runner)], check=True)
