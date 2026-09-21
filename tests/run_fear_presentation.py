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
# Os HUDs que somem em panico tem de consumir a MESMA regra pura: se um deles
# voltar a decidir sozinho, o mapa/folego/inventario saem de sincronia com a
# tela escura -- e o teste abaixo nao pegaria isso, porque so roda as regras.
CONSUMERS = {
    "src/client/StaminaHUD.client.luau": ["FearRules.HudFade(fear, GameConfig.Fear).Vitals"],
    "src/client/HotbarController.client.luau": ["FearRules.HudFade(fear, GameConfig.Fear).Hotbar"],
    "src/client/SurvivorMapController.client.luau": ["FearRules.HudFade(fear, GameConfig.Fear).FullMapBlocked"],
    "src/client/SurvivalMinimapHUD.lua": ["fearHidden", "math.max(idle, hidden)"],
}
for path, needles in CONSUMERS.items():
    source = (ROOT / path).read_text()
    for needle in needles:
        assert needle in source, f"{path} precisa usar {needle}"
    if path != "src/client/SurvivalMinimapHUD.lua":
        # O medo vem do Attribute replicado, nunca de uma conta local.
        assert 'GetAttribute("Fear")' in source, f"{path} deve ler o Attribute Fear do servidor"

sources = "local sources = {}\n" + "\n".join(
    f'sources["{name}"] = [====[\n{(ROOT / path).read_text()}\n]====]'
    for name, path in MODULES.items()
)
with tempfile.TemporaryDirectory(prefix="meujogo-fear-presentation-") as directory:
    runner = pathlib.Path(directory) / "presentation.luau"
    runner.write_text(sources + "\n" + (ROOT / "tests/fear_presentation.luau").read_text())
    subprocess.run([sys.argv[1] if len(sys.argv) > 1 else "luau", str(runner)], check=True)
