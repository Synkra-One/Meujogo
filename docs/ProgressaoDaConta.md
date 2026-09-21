# Progressão da conta — Nível persistente

Liga o XP de partida (já existente em `MatchRewardsConfig`/`MatchRewardService`)
a um **nível de conta persistente**, que sobrevive entre sessões e nunca é
sobrescrito por uma gravação concorrente de outro servidor.

## Peças

| Arquivo | Papel |
| --- | --- |
| `ReplicatedStorage/Modules/LevelSystem.lua` | Curva de nível: XP total → nível. Puro, sem estado, sem Roblox services. |
| `server/DataStoreManager.lua` | Persistência do XP total e cosméticos. Gravação **por delta** (ver abaixo). |
| `server/MatchResultsService.lua` | No fim da partida, credita `session.MatchXP` via `DataStoreManager.AddXP` e monta `payload.Account` (nível antes/depois, progresso, level-up). |
| `client/MatchResultsController.client.luau` | Desenha a seção "Progresso da conta" na tela de resultados, com destaque quando `LeveledUp` é true. |
| `ReplicatedStorage/Modules/MatchRewardsConfig.lua` | `Persistence.CommitMatchXP` (liga/desliga) e `Persistence.CommitMultiplier` (reescala o XP persistente sem mexer no que a tela mostra). |

## A curva de nível

`LevelSystem.XPToReach(nível) = BaseXP * (nível - 1) ^ GrowthExponent`

Dois números pra ajustar, os dois no topo do arquivo:

- `BaseXP` (150) — XP entre o nível 1 e o nível 2.
- `GrowthExponent` (1.35) — > 1 faz cada nível pedir progressivamente mais
  XP que o anterior. `MaxLevel` (100) é o teto.

Calibrados só pela ordem de grandeza já documentada em `MatchRewardsConfig`
(uma partida boa rende ~600-900 XP): os primeiros níveis caem em 1-2
partidas, o nível 100 fica perto de ~100 partidas. **Não passou por
playtest real** — mude os dois números à vontade, ninguém mais no projeto
tem essa curva copiada.

Nenhum outro sistema decide nível sozinho: sempre `LevelSystem.GetLevel(xp)`
ou `LevelSystem.GetProgress(xp)` (também disponíveis como atalho em
`DataStoreManager.GetLevel(player)` / `GetProgress(player)`).

## Por que a pessoa nunca perde progresso

`DataStoreManager` antes salvava o **snapshot inteiro** do perfil por cima
do que já estava no DataStore. Isso tinha uma limitação documentada: se o
mesmo jogador caísse em dois servidores ao mesmo tempo, o último a salvar
apagava o que o outro tinha gravado.

Agora cada gravação usa `UpdateAsync` pra **ler o que já está salvo e somar
só o que esta sessão ganhou** desde a última gravação confirmada:

- XP: delta numérico (`data.xp += ganhoNestaSessão`).
- Cosméticos: união de conjuntos (`data.cosmetics[id] = true` pra cada um
  já conhecido nesta sessão — marcar duas vezes é inofensivo).

Isso significa que dois servidores com o mesmo jogador **somam** em vez de
um apagar o outro. Continua não existindo *session locking* (tipo
ProfileService) impedindo os dois de rodar ao mesmo tempo — só que agora,
se isso acontecer, ninguém perde XP por causa disso.

Ver `tests/data_store_manager.luau` pro cenário exato (dois "servidores"
simulados, mesmo UserId, gravando em sequência) que prova isso.

## Ligar/desligar e reajustar

```lua
-- ReplicatedStorage/Modules/MatchRewardsConfig.lua
MatchRewardsConfig.Persistence = {
	CommitMatchXP = true,   -- false = XP de partida continua só na tela, não persiste
	CommitMultiplier = 1,   -- reescala o XP persistente sem mexer no da tela de resultados
}
```

Precisa reajustar o RITMO de progressão sem mexer nos valores de XP por
ação (que também afetam a tela de resultados)? Mexa em `CommitMultiplier`
ou em `LevelSystem.BaseXP`/`GrowthExponent` — nunca nos valores em
`MatchRewardsConfig.Actions`.

## Testes

```sh
python3 tests/run_data_store_manager.py /caminho/para/luau
python3 tests/run_match_stats.py /caminho/para/luau
```

O primeiro cobre: sessão nova, XP ganho durante o load em voo, dois
servidores com o mesmo jogador (XP e cosméticos), falha de leitura (trava
`canSave`), falha de escrita transitória (retry), perfil sem alteração
(não gera gravação), shutdown salvando todo mundo, e paridade com
`LevelSystem`. O segundo cobre que `MatchResultsService` credita e monta
`payload.Account` sem quebrar o resto do relatório de fim de partida.

**Ainda requer Studio:** DataStore real (o dublê é só uma tabela em
memória — cota, latência real e o comportamento exato de `UpdateAsync` sob
carga só aparecem lá) e o visual da nova seção na tela de resultados.
