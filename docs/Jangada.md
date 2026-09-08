# Jangada — construção e fuga

Uma das rotas de fuga de "Náufragos": os Sobreviventes coletam material,
entregam no canteiro de obras **no meio da praia**, veem a jangada **sendo
montada peça por peça** e, quando ela fica pronta, **empurram-na para o mar**.

## Peças no mundo

Tudo é gerado por `server/Tools/RaftGenerator.lua` — **só `Part` primitiva,
nenhum asset** — então funciona em runtime sem cair em placeholder.

| Instância | O que é |
|---|---|
| `Workspace/Ilha/PraiaJangada/` | Folder que segura tudo |
| `.../Jangada` (Model) | a jangada, `PrimaryPart = Root` (invisível) |
| `.../LocalJangada` (Part) | zona de entrega, atrás da popa (lado da praia) — `RaftObjective` liga o `.Touched` dela |
| `.../Estaca_*`, `CordaObra_*`, `TabuaBruta_*`, `Placa*` | decoração do canteiro (fixa) |

`RaftGenerator` acha sozinho o **meio da faixa de areia** com mar livre à
frente (varre radiais por raycast), e vira a proa da jangada pro mar. O
`server/RaftObjective.lua` chama `RaftGenerator.Build()` no boot se a Jangada
ainda não existir; dá pra rodar na mão em modo de edição pra reposicionar e
salvar:

```lua
local Raft = require(game.ServerScriptService.Server.Tools.RaftGenerator)
Raft.Build()      -- acha a praia, constrói, devolve o Model
Raft.Build(42)    -- outra seed = outro trecho de praia
Raft.Clear()      -- remove tudo
```

## Montagem visual (12 etapas)

Cada peça estrutural nasce como **"planta baixa"** (azul, translúcida, sem
colisão) e carrega o estado construído nos Attributes (`CorConstruida`,
`MaterialConstruido`, `TransparenciaConstruida`, `ColidivelConstruido`,
`EtapaConstrucao`).

Conforme o progresso do objetivo sobe (`GameConfig.RaftObjective`), as etapas
vão sendo **reveladas em sequência** (com poeira de serragem e som de martelo):

| Etapa | Peça |
|---|---|
| 1–5 | troncos do convés (do centro pra fora) |
| 6 | travessas amarradas |
| 7 | proa erguida |
| 8 | plataforma da popa + leme |
| 9 | mastro |
| 10 | verga + vela (dois panos) |
| 11 | cordame (4 estais) |
| 12 | suprimentos: barril, caixa, rolo de corda, lampião (acende) |

Progresso visível = `floor(progress/100 * 12)`. Entregar vários materiais de
uma vez revela várias etapas em cadência rápida — parece a jangada crescendo.

No `RaftObjective.Reset()` (início de cada rodada) todas as peças voltam pra
planta baixa e a jangada volta pra posição original na praia.

## Empurrar pro mar

Ao chegar em 100%: `JangadaPronta = true` e o `ProximityPrompt`
`EmpurrarJangada` (no **leme**, do lado da praia) fica ativo.

Ao acionar:

1. `collectPassengers` pega quem está **em cima do convés** (caixa
   delimitadora do Model; `GetTouchingParts` de reserva).
2. Cada passageiro é preso à pose relativa que tinha na largada
   (`HumanoidRootPart.Anchored = true`, offset guardado).
3. A jangada **desliza da praia pro mar aberto** ao longo de `DirecaoMar`
   (~96 studs, ~5,5s): empurrão forte que desacelera (cúbica de saída) no
   plano, e afunda no surf só na segunda metade (quadrática de entrada). Ao
   entrar na água: som de respingo, jato de espuma na proa, rastro atrás e
   **balanço/roll/pitch** que aumenta com a distância.
4. `RaftEscaped` dispara (~1,2s depois do empurrão, pra fuga "ler" na tela) e
   o `RoundManager` encerra a partida com vitória dos Sobreviventes.
5. Passageiros são soltos ~3s depois (a partida já acabou; o
   `LobbyManager` teleporta todo mundo no fim do intervalo).

Não restrinjo por Role — um Espião infiltrado também pode escapar.

## Kit de teste

`GameConfig.Testing.RaftKit = true` (ligado por padrão, junto dos outros
atalhos de teste) larga **20 unidades de material** (8 Madeira, 6 Corda, 6
Lona) numa grade ao lado da `LocalJangada`, do lado da praia. Dá pra montar
100% da jangada e empurrá-la sem catar material pela ilha — margem folgada até
pro personagem de Reparo mais baixo (fecha ~132% numa entrega só).

O kit é recriado a cada rodada (`RaftObjective.Reset`). `RaftKit = false`
remove no próximo Play. Os materiais "de verdade" espalhados pelo mapa
(`ItemSpawner` / `ItemRegistry`: 12 Madeira + 7 Corda + 3 Lona) continuam
existindo independente disso.

## Verificação

- `rojo build` valida a montagem do projeto.
- `luau src/server/Tools/RaftGenerator.lua` / `luau src/server/RaftObjective.lua`
  validam sintaxe.
- No Studio: sincronize pelo Rojo, dê Play. Sem a ilha gerada/salva a Jangada
  não é construída (aviso no Output). Confira: entregar material vai montando
  as peças; 100% habilita o prompt no leme; empurrar desliza a jangada pro mar
  com respingo/rastro carregando quem está a bordo; nova rodada reseta tudo.
