# Lobby — terminal de aeroporto

O lobby do Náufragos é a **área interna de um terminal de aeroporto**: a fatia
entre a porta da rua e o portão de embarque, não um aeroporto inteiro. O
jogador nasce dentro dele e circula livremente até entrar na sala de espera.

Fica em `(0, 40, -1500)` — a mesma âncora que `LobbyManager.LOBBY_ORIGIN` já
usava, só que **elevada**: o piso do terminal fica 30 studs acima do nível do
chão externo (`GROUND_LEVEL_Y = 9`), onde ficam a grama e o pátio pavimentado.
A ilha da partida (terreno até `|z| = 960`) não é tocada.

> **Por quê elevado:** a sala de embarque não pode estar na mesma altura de
> onde os aviões vão taxiar — num terminal real o nível de embarque fica um
> andar inteiro acima da rampa. Os 30 studs de diferença são preenchidos por
> uma **fundação visível** (`Foundation`, ver abaixo) que "planta" o prédio no
> chão em vez de deixá-lo flutuando.

## Planta

```
              PÁTIO DE DESEMBARQUE  (fechado, marquise + parapeito)
    ══════════════ FACHADA: 4 PORTAS DE CORRER ABERTAS ══════════════   z = +44
              vestíbulo                                pé-direito 18
    ─────────────────────────────────────────────────────────────────   z = +28
      [CHECK-IN 1-4]        totem          [CHECK-IN 5-8]
       balcão + esteira   ▲ SPAWN ▲         balcão + esteira   pé-direito 26
                          (z = 0, olhando pro vidro)
    ─────────────────────────────────────────────────────────────────   z =  -8
      SEGURANÇA    raia 1 ┃ raia 2                      pé-direito 19
       bandejas → esteira ┃ pórtico  (bagagem e pessoa em vãos separados)
    ══════ divisória ═════╋═════════                                    z = -27
    ─────────────────────────────────────────────────────────────────   z = -32
      CONCOURSE          pilares                        pé-direito 34
    ─────────────────────────────────────────────────────────────────   z = -52
      SALA DE EMBARQUE   3 fileiras │ corredor 30 │ 3 fileiras
    ─────────────────────────────────────────────────────────────────   z = -80
      PASSEIO   [PORTÃO A1: balcão, fila, painel]   bancada da janela
    ║║║║║║║ PAREDE PANORÂMICA: 8 VÃOS, VIDRO INCLINADO NO TOPO ║║║║║║║   z = -104

                    GRAMA — reservado pra pista/aviões/veículos
```

Interno: **112 studs de largura por 148 de profundidade**, pé-direito de 18 a
34. A sequência 18 → 26 → 19 → 34 é intencional: comprimir na segurança é o
que faz o salão parecer grande quando ele abre.

## Módulos

| Arquivo | Papel |
|---|---|
| `Tools/AirportLobbyGenerator.lua` | Monta o terminal inteiro. Só `Part` + assets opcionais do Toolbox; nada depende de asset. |
| `Tools/Structures.lua` | Reaproveitado para as primitivas `Part`/`Marker`. |
| `LobbyManager.lua` | **Não foi alterado.** Continua dono de `LobbySpawn`/`LobbyFloor`/`IniciarPartida`. |

## Gerar no Studio

Em **modo de edição** (sem Play), na Command Bar:

```lua
local Lobby = require(game.ServerScriptService.Server.Tools.AirportLobbyGenerator)
Lobby.Generate()
```

**Salve o lugar (Ctrl+S).** Geometria gerada não volta pelo Rojo — é o mesmo
fluxo da ilha (ver [Mapa.md](Mapa.md)).

Variantes: `Lobby.Generate({ Terrain = false })` não escreve a grama;
`Lobby.Generate({ Assets = false })` ignora o Toolbox e usa só `Part`;
`Lobby.Clear()` apaga.

> `Generate()` **destrói `Workspace.Lobby`** antes de refazer. Assets que você
> posicionou na mão lá dentro vão junto — tire-os da pasta antes de regerar.

## Assets do Toolbox

O gerador tenta `InsertService:LoadAsset` (**só funciona em modo de edição**),
normaliza a escala pro tamanho que a arquitetura reservou e assenta no chão.

| Asset | ID | Onde | Quantos |
|---|---|---|---|
| Airport Seats | `10183298246` | Sala de embarque, 3 fileiras por bloco | 6 |
| Luggage Scanner | `10131830908` | Segurança, eixo da bagagem (`x = ±26`) | 2 |
| Security Gate | `10759833003` | Segurança, eixo do pedestre (`x = ±11,5`) | 2 |
| Airport Sign | `13776711189` | Placa suspensa do portão A1 | 1 |
| Ceiling Light | `91305696624692` | Luminárias do teto | 19 |
| Vending machine | `5645721073` | Parede oeste da sala de embarque | 2 |
| Computador | `8301328809` | Telas dos balcões de check-in (8) + balcão do portão (2) | 10 |
| Relógio | `8084763732` | Parede oeste do salão principal | 1 |

**Se um asset não carregar**, o gerador não falha: constrói a versão
equivalente em `Part` (pasta `*_Fallback`) e deixa um marcador invisível em
`Lobby/Airport/AssetPlaceholders` com o `CFrame` exato no Attribute
`CFrameAlvo` e o `AssetId`. O Output lista o que faltou.

Para colocar na mão: insira pelo Toolbox, alinhe com o `CFrameAlvo` do
placeholder e apague o placeholder junto com a pasta `_Fallback` ao lado.

## Organização no Explorer

```
Workspace/Lobby/Airport/
  Architecture/   Floor  Walls  Facade  Ceiling  Pillars  Glass
  CheckIn/        2 balcões de 4 posições, esteiras, filas, totem
  Security/       divisória segmentada, 2 raias, bandejas, supervisor
  WaitingArea/    blocos de poltronas, bancada da janela, painel de partidas
  BoardingGate/   balcão, fila, PainelVoo, PontoEmbarque, placa suspensa
  Lighting/       19 luminárias + foco do portão
  Props/          vending, quiosque, lixeiras, jardineiras, carrinhos, malas
  AssetPlaceholders/
  ExteriorFutureArea/   pátio de concreto + marcador AreaFuturaPista
```

`LobbySpawn`, `LobbyFloor` e `IniciarPartida` **continuam na raiz do
Workspace** — `LobbyManager` os procura com `FindFirstChild` não recursivo, e
movê-los pra dentro de `Lobby/` faria ele criar duplicatas no próximo boot.

## Como o terminal convive com o LobbyManager

`LobbyManager` reescreve posição/tamanho dessas três peças a todo boot. Em vez
de disputar, o terminal foi desenhado **em volta** delas:

| Peça | Posição (forçada) | Virou |
|---|---|---|
| `LobbySpawn` | `(0, 40.5, -1500)` | Meio do saguão de check-in, olhando pro vidro |
| `IniciarPartida` | `(0, 40.5, -1480)` | Totem de auto-atendimento entre os balcões |
| `LobbyFloor` | `(0, 39, -1500)` | Enterrado no piso novo |

O gerador só ajusta o que `LobbyManager` **não** reescreve: `Transparency`,
`CanCollide`, `Duration` e a rotação do `CFrame`. O spawn fica invisível, sem
colisão, sem forcefield e com `LookVector = (0,0,-1)` — ou seja, o jogador
nasce vendo a fascia da segurança, o salão alto, as poltronas e a janela
panorâmica em enfiada.

## Fundação — o terminal não flutua

Entre o piso do terminal (`y = 40`) e o chão externo (`y = 9`) sobram 30
studs que precisam de alguma coisa embaixo, senão o prédio fica pairando no
ar. `Lobby/Airport/Foundation` fecha esse vão com um **podium** visível:

- Quatro paredes ocas de concreto escuro envolvendo todo o perímetro do
  prédio (um pouco além das paredes externas, efeito clássico de podium —
  a base é mais larga que o que ela sustenta).
- Encaixa por cima direto no `Plinth` do piso (sem fresta na emenda) e
  "planta" por baixo uns studs abaixo do nível do pátio/grama (sem fresta
  no chão também).
- Frisos horizontais marcando as três transições (prédio → fundação → chão)
  e pilastras verticais nas quatro faces, pra não ler como uma caixa lisa
  gigante enterrada.
- Contraventamento diagonal (viga metálica) nas duas quinas do lado da
  janela — é o primeiro pedaço de estrutura que aparece quando o jogador
  olha pro vidro, então foi o ponto escolhido pra parecer "apoio de
  verdade" em vez de só um paredão.

Isso também tira de vez o problema da grama aparecendo por dentro: o piso
do terminal e o topo da grama (`y = 9`) agora estão **30 studs distantes um
do outro**, ao invés dos ~5 studs de antes — qualquer resíduo de `Terrain`
que ainda sobre nessa faixa (de uma versão anterior do gerador) fica bem
abaixo da fundação, nunca visível de dentro do salão.

## Área externa

Logo depois do vidro (`z = -1604` no mundo) tem um **pátio pavimentado**
(`ExteriorFutureArea/Apron`): `Asphalt` escuro com eixo pintado, faixas de
borda e traços laterais — leitura de pista/táxi, não concreto liso. Só
depois dele começa a **grama plana**: `Terrain` `Grass` de `x = ±460`,
`z = -1652` a `-2800`, escrito em 4 blocos.

> **Bug corrigido nesta revisão:** a grama chegava a começar em `z = -1400`
> (mundo), que é **na frente da fachada de entrada** (`z` relativo `+100`,
> contra `+44` da fachada) — ela cobria o chão por baixo do terminal inteiro
> e aparecia pelas portas da frente. Agora `EXTERIOR.ZNear` é travado
> exatamente na borda de trás do pátio pavimentado
> (`ORIGIN.Z + L.ZGlass - 25 - APRON_DEPTH/2`), então a grama nunca fica sob
> nem ao lado do prédio — só estritamente atrás do vidro.

Sobram ~1150 studs de profundidade livres para pista, aviões, ônibus, veículos
de serviço, iluminação e construções distantes — nada disso encosta no
terminal.

O marcador `AreaFuturaPista` guarda esse envelope em Attributes.
`IslandGenerator.ClearAll()` só limpa `|x|,|z| ≤ 960`, então regerar a ilha
não apaga essa grama nem o pátio.

O pátio pavimentado existe só pra o vidro não encostar direto na grama — é a
primeira coisa a apagar quando a pista de verdade for construída.

## Preparado para o futuro (ainda sem lógica)

| Marcador | Attribute | Para |
|---|---|---|
| `PontoEmbarque` | `PontoEmbarque`, `PortaoId="A1"`, `VooId="815"` | Âncora do matchmaking no balcão do portão |
| `PainelVoo` | `PainelVoo`, `PortaoId` | `SurfaceGui` com os labels `Voo` / `Destino` / `Status` / `Passageiros` já separados — um sistema futuro só troca o `.Text` |
| `AreaFuturaPista` | `AreaFuturaPista`, `LarguraStuds`, `ProfundidadeStuds`, `BordaDoVidroZ` | Envelope reservado da pista |

O painel mostra `VOO 815 / DESTINO: ??? / STATUS: AGUARDANDO / PASSAGEIROS:
0/10` como texto fixo. Nada de matchmaking foi ligado.

## Performance

706 peças, das quais **153 com colisão** — toda a decoração é `CanCollide`,
`CastShadow`, `CanQuery` e `CanTouch` desligados. **25 luzes**, todas com
`Shadows = false`; o brilho dos letreiros e das luminárias vem de material
`Neon`, que não custa fonte de luz. Tudo `Anchored`.

## Validação

```sh
python3 tests/run_airport_lobby.py /caminho/para/luau
rojo build -o /tmp/Meujogo-check.rbxlx
```

`tests/airport_lobby.luau` roda o gerador **real** sobre dublês determinísticos
do Roblox (`tests/robloxstub.luau`: `Vector3`, `CFrame` com matriz de verdade,
`Instance`, `Terrain`) e verifica:

- nada invade a sala de espera (`x 94..146`) nem a área da ilha (`|z| ≤ 960`),
  nem a geometria nem os blocos de `Terrain`;
- a grama externa começa exatamente na borda de trás do pátio pavimentado —
  nunca embaixo nem na frente do terminal (o bug corrigido acima);
- a fundação existe, chega perto do chão (não flutua) e encosta no piso do
  terminal sem vão — e a diferença de altura entre os dois é de pelo menos
  25 studs (a sala de embarque não fica na altura dos aviões);
- as peças do `LobbyManager` continuam na raiz do Workspace, e ficaram
  invisíveis / sem colisão / sem forcefield / olhando pro vidro;
- ninguém nasce dentro de uma peça;
- **BFS no nível do chão**: dá pra andar do spawn até o vestíbulo, as duas
  raias da segurança, o salão, os corredores das poltronas, as duas laterais,
  a fila do portão, o passeio junto ao vidro e o meio-fio — e **não** dá pra
  atravessar o vidro nem contornar o prédio até o lado da pista;
- a parede panorâmica está inteira (8 vãos, 9 montantes, largura cheia), dá
  pra encostar nela em toda a largura, e nada opaco flutua na altura do olho
  entre as poltronas e o vidro (a faixa por onde a pista vai aparecer);
- todas as pastas existem, e os marcadores de futuro também;
- sem Toolbox, cada posição de asset vira `Part` + placeholder com `CFrameAlvo`;
- `Generate()` duas vezes seguidas dá o mesmo resultado, sem duplicar pastas.

Esses testes não validam renderização, física nem replicação do motor. No
Studio, confira: gere, dê Play, veja o enquadramento do spawn, atravesse a
segurança, ande entre as poltronas até encostar no vidro, e confirme que o
prompt `Entrar na sala` do totem ainda funciona.
