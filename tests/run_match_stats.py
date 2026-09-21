"""XP, estatisticas e resultado de partida rodando contra os modulos REAIS.

Nao e um playtest: Roblox e substituido por dubles deterministicos (relogio
virtual, Heartbeat disparado na mao, Vector3 com aritmetica de verdade) e os
tres servicos, a configuracao e os tipos sao os arquivos de producao, sem
nenhuma reimplementacao paralela.

Uso:  python3 tests/run_match_stats.py [caminho/para/luau]
"""
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]

# Modulos REAIS sob teste. Todo o resto (Players, RoundManager, DamageSystem...)
# e dublado dentro do proprio spec.
MODULES = {
    "MatchStatsTypes": "src/ReplicatedStorage/Modules/MatchStatsTypes.lua",
    "MatchRewardsConfig": "src/ReplicatedStorage/Modules/MatchRewardsConfig.lua",
    "MatchStatsService": "src/server/MatchStatsService.lua",
    "MatchRewardService": "src/server/MatchRewardService.lua",
    "MatchResultsService": "src/server/MatchResultsService.lua",
    # Puro (sem Roblox services), seguro carregar de verdade: MatchResultsService
    # usa isto pra calcular o nivel da conta antes/depois de creditar o MatchXP.
    "LevelSystem": "src/ReplicatedStorage/Modules/LevelSystem.lua",
}

binary = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else pathlib.Path("luau")
compiler = binary.with_name("luau-compile")


def quote(source: str) -> str:
    """Envolve o fonte num long string com separador que nao colida com ele."""
    separator = "="
    while f"]{separator}]" in source:
        separator += "="
    return f"[{separator}[\n{source}\n]{separator}]"


with tempfile.TemporaryDirectory(prefix="match-stats-") as temporary:
    directory = pathlib.Path(temporary)

    # Passo 1: os modulos precisam COMPILAR. Pega erro de sintaxe antes de o
    # spec rodar, com a mensagem apontando o arquivo de verdade.
    if compiler.exists():
        subprocess.run(
            [str(compiler), "--null", *[str(ROOT / path) for path in MODULES.values()]],
            check=True,
        )

    # Passo 2: o spec, com os fontes reais embutidos.
    sources = "local sources = {}\n" + "\n".join(
        f'sources["{name}"] = {quote((ROOT / path).read_text())}'
        for name, path in MODULES.items()
    )
    test = directory / "match_stats.luau"
    test.write_text(sources + "\n" + (ROOT / "tests/match_stats.luau").read_text())
    subprocess.run([str(binary), str(test)], check=True)
