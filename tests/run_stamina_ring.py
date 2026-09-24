"""Run the real StaminaRing module with deterministic Roblox doubles.
Usage: python3 tests/run_stamina_ring.py /path/to/luau
"""
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
MODULES = {
    "StaminaRing": "src/client/StaminaRing.lua",
    # Só o TEXTO: o HUD precisa de services do Studio, mas dá pra travar
    # regressões visuais nele (halo preto, segunda barra, conversão dupla).
    "SurvivalMinimapHUD": "src/client/SurvivalMinimapHUD.lua",
    "StaminaHUD": "src/client/StaminaHUD.client.luau",
    "StaminaSystem": "src/server/StaminaSystem.lua",
}
sources = "local sources = {}\n" + "\n".join(
    f'sources["{name}"] = [====[\n{(ROOT / path).read_text()}\n]====]'
    for name, path in MODULES.items()
)
with tempfile.TemporaryDirectory(prefix="meujogo-stamina-ring-") as directory:
    runner = pathlib.Path(directory) / "stamina_ring.luau"
    runner.write_text(sources + "\n" + (ROOT / "tests/stamina_ring.luau").read_text())
    subprocess.run([sys.argv[1] if len(sys.argv) > 1 else "luau", str(runner)], check=True)
