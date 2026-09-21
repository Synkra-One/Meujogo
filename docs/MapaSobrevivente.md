# Mapa do Sobrevivente/Espião (M) + descoberta de itens + mapa menos "blocado"

## O que mudou

1. **Mapa menos quadriculado.** `Modules/IslandMapData.lua`: resolução 100 →
   144, sombreamento 7 → 16 níveis (faixa mais estreita). `server/IslandMap.lua`:
   hillshading mais suave (1.55 → 1.25) e uma **linha de costa** (terra colada
   na água escurece um pouco) em vez do limite cru entre um retângulo de praia
   e um de mar. `Modules/IslandMapUI.lua` (antes `MonsterMapUI.lua`): mais
   sobreposição entre retângulos vizinhos (`Style.RectBleed` 0.06 → 0.22) pra
   matar as costuras que apareciam como grade fixa.

2. **Mapa do Sobrevivente/Espião**, tecla **M** (`client/SurvivorMapController`).
   Mesmo desenho que o mapa do Monstro (Q), em modo **"view"**: mostra POIs,
   trilhas, um marcador verde de "você" e os itens já descobertos -- **não**
   mostra a Caverna (spawn do Monstro). Não trava o movimento nem prende o
   mouse: é um overlay, o personagem continua andando/vulnerável com o mapa
   aberto. Fecha com M de novo, botão direito, ou no fim da partida. Q
   continua sendo o Poder 1 do Sobrevivente (`SurvivorPowersController`) --
   por isso o mapa dele não usa Q.

3. **Descoberta de itens.** Passar a `GameConfig.MapDiscovery.Radius` (14
   studs, sem exigir linha de visão) de um item do mundo marca ele **para
   sempre** no mapa daquele jogador especificamente -- outros jogadores não
   são avisados. A marca nunca é desfeita durante a sessão do servidor (nem
   ao morrer/respawnar/trocar de rodada): os itens do mapa não são
   resorteados a cada partida, então "esquecer" seria perder uma informação
   que continua verdadeira.

## Arquivos

**Criados**

| Arquivo | O quê |
|---|---|
| `src/ReplicatedStorage/Modules/MapMarkers.lua` | Categoria (arma, corpo-a-corpo, luz, cura, material, peça de rádio, raro, caixa) → cor + glifo. `ImageFor(itemId)` delega a `ItemIcons`: quando um PNG real for colado lá, substitui o glifo sozinho. |
| `src/server/ItemDiscovery.lua` | Autoridade: observa o Workspace (Parts/Tools reconhecíveis), varre proximidade de cada jogador `InRound` a cada 0,5s e dispara `Remotes.MapDiscovery` na primeira vez que cada um passa perto de cada item. |
| `src/client/DiscoveredItemsStore.lua` | ModuleScript: acumula os itens descobertos deste jogador (dedupe por `key`), persistente pela sessão inteira. Consumido pelos dois controladores de mapa. |
| `src/client/SurvivorMapController.client.luau` | Input M/botão direito, monta o `IslandMapUI` em modo "view". |
| `src/ReplicatedStorage/Remotes/MapDiscovery.model.json` | RemoteEvent, servidor → cliente apenas. |

**Renomeado**

| De | Para |
|---|---|
| `src/ReplicatedStorage/Modules/MonsterMapUI.lua` | `src/ReplicatedStorage/Modules/IslandMapUI.lua` -- ganhou `opts = { mode, onPick }` (`"teleport"` = comportamento antigo do Monstro, `"view"` = novo, sem clique), marcador "você" (`UpdateSelf`) além do marcador do Monstro, e a camada de itens descobertos (`AddDiscoveredItem`/`SetDiscoveredItems`). Aceita a assinatura antiga (`onPick` solto) por compatibilidade. |

**Modificados**

| Arquivo | Mudança |
|---|---|
| `GameConfig.lua` | `GameConfig.MapDiscovery` (Enabled/Radius/ScanInterval). |
| `Remotes.lua` | Contrato de `MapDiscovery`. |
| `ItemIcons.lua` | Chaves vazias pra Antena/Bateria/Transmissor/Bandagem (mesma convenção: cole o `rbxassetid` quando tiver o PNG). |
| `client/MonsterTeleportController.client.luau` | `require` do módulo renomeado, passa `{ mode = "teleport", onPick = ... }`, alimenta `SetDiscoveredItems`/`AddDiscoveredItem`. |
| `server/init.server.luau` | `safeInit("ItemDiscovery", ...)` depois de WeaponSpawner/LootCrateSystem. |

## O que conta como "item do mundo" hoje

Faca/Lança/Pedra/Tocha/Lanterna/Chocolate/Bandagem (pickup no chão), Antena/
Bateria/Transmissor, caixa de munição, caixa de loot, arma
de fogo (Glock17) e a Lança Ancestral. Ver o cabeçalho de `server/ItemDiscovery.lua`
para os Attributes exatos de cada um -- todos já existentes em outros
sistemas (`ItemSpawner`, `WeaponSpawner`, `DropItemSystem`, `AmmoSystem`,
`LootCrateSystem`), nenhum Attribute novo foi criado.

## Ícones

Sem PNG próprio ainda: cada categoria ganha uma cor + uma letra/símbolo
desenhados em código (`Modules/MapMarkers.lua`). Quando publicar um ícone de
verdade, cole o `rbxassetid` em `ItemIcons.Map[itemId]` (ex: `Glock17 =
"rbxassetid://..."`) -- o marcador do mapa passa a usar a imagem sozinho, sem
mudar nada em `IslandMapUI.lua` nem em `MapMarkers.lua`.

## Pânico bloqueia o mapa

Com Fear a partir de `GameConfig.Fear.FullMapBlockFear` (86), **M não abre** o
mapa -- e ele fecha sozinho se já estiver aberto. É o mesmo limiar em que o
minimapa apaga, pelo mesmo `FearPresentationRules.HudFade`; ver
[Fear.md](Fear.md). O medo vem do Attribute replicado pelo servidor, então o
cliente não decide nada. Quando o Fear cai, M volta a funcionar normalmente e
os itens descobertos continuam todos lá.

## Verificação

- `rojo build -o /tmp/Meujogo-check.rbxlx` valida a montagem do projeto.
- No Studio, com a ilha gerada: Sobrevivente/Espião aperta **M** -- mapa
  abre sem travar o movimento, mostra POIs/trilhas e um ponto verde na sua
  posição, sem a Caverna. Aproxime-se (≤14 studs) de uma pistola, uma tocha,
  uma peça do rádio e uma caixa de loot: cada um deve aparecer marcado
  ao reabrir o mapa (até 0,5s de atraso), com cor/letra diferentes por
  categoria. Morra/reapareça e confira que as marcas continuam. O Monstro
  (Q) deve continuar funcionando exatamente como antes, agora também vendo
  os itens que ele mesmo descobriu.
- Com o mapa aberto, deixe o Monstro te encurralar até o Fear passar de 86: o
  mapa fecha sozinho e M para de responder. Fuja, espere o Fear cair e
  confirme que M volta a abrir com as mesmas marcas.
