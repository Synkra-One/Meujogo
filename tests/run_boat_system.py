"""BoatSystem REAL (servidor do barco de fuga) com dublês determinísticos.

Uso:  python3 tests/run_boat_system.py [caminho/para/luau]
Cobre assentos, motor, montagem, gasolina, chave, sabotagem, encalhe,
empurrão, anti-teleporte, limite, cena e reset. A física do engine fica em
tests/boat.studio.luau (run-in-roblox).
"""
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
MODULES = {
    "Stub": "tests/robloxstub.luau",
    "GameConfig": "src/ReplicatedStorage/Modules/GameConfig.lua",
    "BoatRules": "src/ReplicatedStorage/Modules/BoatRules.lua",
    "BoatSystem": "src/server/BoatSystem.lua",
}
bundle = "local sources = {}\n" + "\n".join(
    f'sources["{name}"] = [====[\n{(ROOT / path).read_text()}\n]====]'
    for name, path in MODULES.items()
)
with tempfile.TemporaryDirectory(prefix="boat-system-") as directory:
    runner = pathlib.Path(directory) / "boat_system.luau"
    runner.write_text(bundle + "\n" + (ROOT / "tests/boat_system.luau").read_text())
    subprocess.run([sys.argv[1] if len(sys.argv) > 1 else "luau", str(runner)], check=True)
