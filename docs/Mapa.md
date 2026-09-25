# Mapa — ilha estilo Friday the 13th

Ilha de ~1400–1600 studs de diâmetro (terreno real 1920×1920), noite fechada,
com **pontos de interesse espalhados** ligados por **trilhas de terra** e
**floresta fechada** entre eles. Correndo em linha reta leva ~60–70s pra
atravessar; na prática mais, por causa do relevo e do mato.

## Módulos

| Arquivo | Papel |
|---|---|
| `Tools/IslandLayout.lua` | O plano: costa, relevo, biomas, **onde cai cada POI**, trilhas. Só matemática, fixo por seed. Exporta `Height/Material/WaterLevel` por coluna e `CoastRadiusMax()/AreaHalf()` pros sistemas de runtime. |
| `Tools/IslandGenerator.lua` | Escreve o terreno por chunks a partir do layout; rochas, caverna, floresta, vegetação rasteira, ruínas; chama `PoiGenerator`. |
| `Tools/AbyssStationGenerator.lua` | Estação Abismo: laboratório subterrâneo na costa oposta à montanha, com entrada em uma pequena caverna, duas escadas curtas, salão de testes e saída seca na costa (ver [EstacaoAbismo.md](EstacaoAbismo.md)). |
| `Tools/RadioTowerGenerator.lua` | Estação de Rádio: torre, abrigo, gerador, combustível, cerca e estrada (ver [Radio.md](Radio.md)). |
| `Tools/CaveInterior.lua` | O covil do Monstro dentro da montanha: escava o terreno e monta os três níveis e as zonas de escuridão (ver [Caverna.md](Caverna.md)). |
| `Tools/Structures.lua` | Peças em `Part` primitiva: cabana, lodge, celeiro, casa de barcos, píer, barco, torre de vigia, farol, fogueira, mesa, lampião, alvo, fardo, secador, canoa, cabana nativa, totem, arbusto, tronco caído. |
| `Tools/PoiGenerator.lua` | Monta cada POI no site do layout com as peças de `Structures`. |
| `Tools/HouseGenerator.lua` + `Tools/Houses/` | Casas grandes nas clareiras Acampamento, CabanasA, CabanasB e VilaNativa: lote, terreno, casa (ver [Casas.md](Casas.md)). |
| `Tools/PlaneCrashGenerator.lua` | Queda de avião internacional (260 studs): fuselagem no impacto, peças próximas, destroços distantes e rastro do mar à floresta; desvia dos POIs. |
| `Tools/ItemSpawner.lua` | Itens; zona nova `Construcoes` = marcadores `PontoLoot` dentro das construções. |
| `server/DoorSystem.lua` | Portas (`Porta` Attribute) com prompt Abrir/Fechar. |

## Pontos de interesse

| Site | O que tem | Spawn / loot |
|---|---|---|
| **Acampamento / CabanasA / CabanasB** | Clareira nivelada com 2 casas grandes (uma CampCabin e uma CasaDoCaseiro), portas e gavetas funcionais, caminho de terra até a trilha. Ver [Casas.md](Casas.md) | SpawnPOI na frente de cada casa; PontoLoot no piso; SpawnArma na cozinha da CasaDoCaseiro; loot nas gavetas (DrawerSystem) |
| **Lago** | Bacia com água (nível próprio), píer de 30 studs com barco amarrado, casa de barcos aberta, barco furado virado, canoa, secador de peixe | PontoLoot no píer e na casa de barcos (SpawnArma) |
| **Campo (Fazenda)** | Planície de grama (r≈130) com a fazenda: celeiro grande (palheiro, baias, selaria, telheiro com trator, silo, curral) e casa de fazenda de dois andares com cata-vento, poço e casinha. Ver [Casas.md](Casas.md) | SpawnPOI na frente das duas; PontoLoot no celeiro e nos dois andares da casa; SpawnArma na selaria e na sala |
| **Torre** | Torre de vigia no site mais alto, escada `TrussPart` escalável, lampião aceso no topo | SpawnArma na plataforma |
| **Farol** | Ponta rochosa elevada na costa, farol de 6 segmentos com lâmpada acesa (range 120), barraco do faroleiro | SpawnPOI/PontoLoot |
| **VilaNativa** | Clareira com 2 casas grandes, como acima (a vila nativa antiga não é mais gerada) | idem |
| **Ruinas** | Círculo de pedras + Lança Ancestral | SpawnPOI |
| **Caverna** | Covil dentro da montanha (Peak 95, Radius 150): túnel em S descendo 9, salão de raio 40 com 56 de pé-direito, poço rochoso, galeria no meio, ponte de tábuas, laje de cima com o ninho, câmara mineral e depósito. Spawn do Monstro no ninho. Ver [Caverna.md](Caverna.md) | — |
| **Radio** | Estação repetidora cercada (132x112): torre de 105 studs com baliza, abrigo técnico 36x26 com duas portas, gerador, tanque e galões, caixa de fusíveis, holofotes, portão e estrada de manutenção. É o objetivo de socorro — ver [Radio.md](Radio.md) | 2 PontoLoot no abrigo + 1 no depósito |
| **Estação Abismo** | Caverna escondida na floresta **do lado oposto à montanha do Monstro**, porta industrial e escada curta. Recepção, área técnica, laboratório, arquivo, enfermaria, controle e o salão de testes de 76×76 com o **Frog Generator** (cápsula), celas de contenção e mesas de necropsia; 120 studs de corredor e outra escada até a saída seca na costa. Ver [EstacaoAbismo.md](EstacaoAbismo.md) | PontoLoot em cada sala e dois no salão de testes |
| **Trilhas** | Loop pelos POIs habitados (ordem angular) + ramais pra Torre, Farol, Ruínas e boca da Caverna; `Ground` rebaixado, `Mud` perto do lago; postes de rua a cada ~120 studs e reforço nas entradas de vilas e torre | — |

Tamanhos: árvores 30–56 studs (R6 ≈ 5), cabana 16×14 com pé-direito 8,5 e
porta de 7, lodge 34×24, celeiro 28×40×13, torre com plataforma a 24, farol
com 40 de torre.

## Biomas (em `IslandLayout.Material`/`Height`)

- **Praia** em anel (Sand, 45 studs) em volta da ilha inteira.
- **Floresta** (Grass/LeafyGrass) — bioma dominante; ~2600 árvores + 1400
  arbustos + 160 troncos caídos, espaçamento 16.
- **Campo** — nivelado no plano, Grass puro, sem floresta.
- **Lago** — bacia de 9 de profundidade, água no nível do rim −1,4, areia na
  margem, Ground em volta. Água = Swimming (o pacote de movimento corta a
  velocidade), então é pequeno (r 60).
- **Montanha** — Rock/Ground, escavada por dentro pela caverna.
- **Ponta do farol** — Rock, +4 de altura.
- `Terrain.Decoration = true` liga a grama animada.

## Runtime

- **Spawn dos sobreviventes**: `LobbyManager` embaralha os marcadores
  `SpawnPOI` e põe um jogador em cada (porta de cabana, lodge, celeiro,
  torre, farol, vila, ruínas). Monstro no ninho, no nível de cima da caverna. Antes de teleportar chama
  `RequestStreamAroundAsync` (StreamingEnabled está ligado).
- **Loot**: `LootCrateSystem` põe caixas nos `PontoLoot`; `ItemSpawner` tem a
  zona `Construcoes`; `WeaponSpawner` já usava `SpawnArma`.
- **Lobby e sala de espera** mudaram pra `z = -1500` (fora do terreno de
  ±960). `LOBBY_ORIGIN` em `LobbyManager`, `origin` em `WaitingRoomManager`,
  e `default.project.json`.
- **Clima**: `GameConfig.Environment.LightingPreset = "Night"` (FogEnd 320 —
  não se vê um POI do outro). `CloudyMorning` (FogEnd 1400) serve pra depurar
  o layout de dia.

## Gerar e salvar (Studio, modo de edição, Command Bar)

```lua
local Gen = require(game.ServerScriptService.Server.Tools.IslandGenerator)
Gen.Generate()        -- ~3-6 min; o Output mostra "terreno N/400 chunks"
```
Depois, um por vez:
```lua
require(game.ServerScriptService.Server.Tools.PlaneCrashGenerator).Generate()
require(game.ServerScriptService.Server.Tools.ItemSpawner).Generate()
```
**Salve (Ctrl+S).** O rádio e a extração são inicializados no boot.

Ao atualizar apenas o código do acidente, regenere a ilha antes do avião. O
gerador remove os modelos antigos, mas o sulco anterior faz parte do Terrain e
só `IslandGenerator.Generate()` o reconstrói. Depois rode novamente o avião e o
`ItemSpawner`, pois os pontos de loot acompanham as novas peças.

Etapas isoladas: `Gen.GenerateTerrain()`, `GenerateRockFormations()`,
`GenerateCave()`, `GenerateForest(1.0)`, `GenerateUndergrowth()`,
`GenerateRuins()`, `require(...PoiGenerator).Generate()`. Outra seed:
`Gen.Generate(42)`. Limpar: `Gen.ClearAll()`.

Para atualizar **somente a vila** no mapa existente, fora do Play, use
`require(game.ServerScriptService.Server.Tools.PoiGenerator).GenerateVillage()`.
O módulo `Tools/NativeVillage.lua` contém as construções e a decoração. A
atualização usa o marcador já salvo `Ilha/Layout/VilaNativa`, mantém o raio de
clareira de 50 studs e guarda a pasta anterior em
`ServerStorage/MapEditBackups/VilaNativa_<data>_<índice>`. Objetos extras na raiz
da vila são preservados; os conteúdos das construções antigas ficam no backup.
Não toca na pasta `Ilha/VilaNativa` usada pelas peças do rádio. Salve o lugar
depois: salvar código no Rojo não salva automaticamente a geometria gerada.

Árvores/rochas usam `InsertService` (só em modo de edição; fora dele entra
placeholder). Tudo o mais é `Part` e roda em runtime.

## Verificação

- `rojo build` e `luau` (sintaxe) nos módulos; testes `run_waiting_room.py`
  (RoundManager) e smoke test do layout/geradores com stub (ver
  scratchpad da sessão).
- No Studio: gere, confira que cada POI existe (`Workspace/Ilha/POIs`),
  que as trilhas ligam os POIs, que a torre tem escada, que as portas abrem,
  que o lago tem água e o píer entra nela; dê Play e veja o spawn espalhado.
