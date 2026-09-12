# Estação de Rádio — o objetivo de socorro

O local físico do objetivo do Rádio: torre de transmissão, abrigo técnico,
gerador, combustível, quadro elétrico, cerca e a estrada de manutenção. É um
sítio de repetidora semi-realista — tudo que existe lá existiria de verdade —
mas as distâncias e os tempos são de gameplay, não de engenharia.

| Arquivo | Papel |
|---|---|
| `Tools/RadioTowerGenerator.lua` | **Constrói** o local (ferramenta de editor). Terraplana o pátio, abre a estrada e monta tudo. |
| `server/RadioSiteSystem.lua` | **Faz funcionar**: combustível, fusível, gerador, painel, pedido de socorro, baliza, barulho, sabotagem. |
| `server/RadioPieces.lua` | As 3 peças (Antena/Bateria/Transmissor) espalhadas pelo mapa. |
| `server/RadioInstallSystem.lua` | Instala as peças no rack do abrigo. |
| `Modules/ItemRegistry.lua` + `ToolFactory.lua` | Item "Gasolina" (`Tool`, achado no mapa via `ItemSpawner`) que também abastece o gerador. |
| `server/RadioObjective.lua` | Estado do objetivo; `CompleteRescueCall` dispara a contagem de resgate. |
| `client/ObjectivesController.client.luau` | HUD: barra de peças, texto de status da torre (transmitindo/enviado), notificações. |
| `server/ExtractionSystem.lua` | O que vem DEPOIS do socorro: helicóptero na praia (ver [Extracao.md](Extracao.md)). |

## A corrente de interações

Seis etapas, nesta ordem. Cada uma é um `ProximityPrompt` criado a partir do
Attribute `InteracaoRadio` das Parts geradas.

| # | Onde | Ação | Exige | Segurar |
|---|---|---|---|---|
| 1 | Rack, dentro do abrigo | **Instalar peça** | as 3 peças achadas no mapa | — |
| 2 | Bocal do gerador | **Abastecer** | um galão cheio no pátio OU Gasolina carregada | 4s |
| 3 | Prateleira → caixa na parede | **Pegar fusível** → abrir a caixa e arrastar o fusível até o encaixe vazio | carregar o fusível | 0s / minigame |
| 4 | Painel de partida | **Ligar gerador** | fusível + combustível + não sabotado | 2,5s |
| 5 | Painel de controle, dentro | **Ativar painel** | gerador ligado + peças instaladas | 4s |
| 6 | Console do rádio, dentro | **Enviar socorro** | painel ativo | canalizado 14s |

No fim da etapa 6 sai `RadioObjective.CompleteRescueCall` -> `RescueCountdownStarted`
-> `RoundManager` chama a **extração**: nasce uma zona de pouso na praia com
fumaça vermelha e começa a contagem do helicóptero. **Concluir o rádio não
ganha a partida** -- ainda é preciso atravessar a ilha e embarcar. Ver
[Extracao.md](Extracao.md).

**Onde as peças ficam agora para teste rápido:** Antena, Bateria e Transmissor
nascem ao lado do gerador da estação de rádio. Assim dá para validar coleta,
instalação no rack, combustível, fusível, partida, painel e transmissão sem
atravessar a ilha.

## Combustível: dois jeitos de abastecer

O bocal do gerador (etapa 2, "Abastecer") aceita **duas fontes**, e
`RadioSiteSystem.onRefuel` sempre prefere a que o jogador está carregando:

1. **Galão de Gasolina** (`ItemRegistry.Gasolina`, asset `8679995948`) — item
   de verdade, achado espalhado pelo mapa como qualquer outro (mesmas zonas
   de destroços/construções da Lanterna e do Chocolate, raridade Média).
   Carrega no inventário como Tool; usar no bocal consome e destrói o item.
2. **Galão fixo do pátio** — os 3 galões já parados do lado do gerador
   (`Tools/RadioTowerGenerator.buildFuel`), que voltam cheios a cada rodada
   (`RadioSiteSystem.Reset`). Só entra em jogo quando ninguém tem Gasolina
   carregada.

As duas rendem os mesmos `GameConfig.RadioSite.CombustivelPorGalao` (90s), até
o teto de `CombustivelMaximo` (270s). Isso significa que os galões fixos
GARANTEM o objetivo sempre completável mesmo se toda a Gasolina do mapa já
tiver sido gasta em rodadas anteriores (itens de `ItemSpawner` não respawnam
sozinhos entre rodadas, igual Lanterna/Chocolate/Bandagem já funcionavam) —
a Gasolina é um reforço que recompensa quem sai catando pelo mapa, não uma
dependência.

## Planta do sítio

Visto de cima. O portão fica virado pro centro da ilha, que é de onde a trilha
de manutenção chega.

```
  ┌──────────────────── cerca 88 x 76 (9 de altura) ────────────────────┐
  │                                                                     │
  │   ┌────────────┐                          ╱ TORRE 105 studs         │
  │   │  DEPÓSITO  │  ○○ carretéis           ╱  (estais, baliza)        │
  │   └────────────┘                        ▓▓   plataforma 28          │
  │                                         ▓▓                          │
  │                                         ▓▓                          │
  │  ┌──────────────┐      [TRAFO]                          ╭───╮       │
  │  │    ABRIGO    │                                       │ ⌓ │ ← rasgo│
  │  │ rack  painel │                                       ╰───╯   na   │
  │  │    console   │                                    parabólica cerca│
  │  └──┬───────────┘        [GERADOR]        ╔═════════╗          (14) │
  │  [caixa fusíveis]         cabos           ║ TANQUE  ║               │
  │   [bateria]                               ║ galões  ║               │
  │                                           ╚═════════╝               │
  │   ○ holofote            ‖ ‖ manobra                     holofote ○   │
  └──────────────────────── PORTÃO (14) ────────────────────────────────┘
                                 │
                            estrada (60)
                                 │
                          trilha da ilha
```

Folgas reais entre as estações: abrigo → gerador **9 studs**, gerador →
combustível **13**, abrigo → combustível **34**, abrigo → torre **25**. Na
primeira versão o pátio era 48x42 e essas folgas eram **zero** — as lajes
encostavam umas nas outras e não havia espaço pra correr de ninguém.

- **Torre** (fundo à direita): 105 studs — o dobro da árvore mais alta (30–56).
  Estais ancorados em blocos de concreto, plataforma de serviço a 28 studs com
  escada de treliça escalável, baliza vermelha piscando no topo e outra no
  meio. Asset `8788183000`; se ele não carregar, entra uma treliça em Parts com
  a mesma silhueta.
- **Abrigo** (frente à esquerda): 20 x 14, alvenaria, porta de aço (o
  `DoorSystem` abre/fecha), janela suja. Dentro, cada estação numa parede
  diferente e o meio da sala livre: rack do transmissor (fundo esquerdo),
  painel de controle (parede lateral), mesa do operador com o rádio (direita),
  prateleira com o fusível reserva e 2 `PontoLoot`.
- **Gerador** (meio do pátio): base de concreto com faixa zebrada, escapamento
  que solta fumaça quando roda, bocal de combustível e painel de partida.
  Asset `10685426940`, com fallback em Parts.
- **Combustível** (canto direito, longe do abrigo): tanque horizontal sobre
  cavaletes dentro de uma bacia de contenção + 3 galões. Cada galão = 90s.
- **Elétrica**: caixa de fusíveis na parede externa do abrigo (com o soquete
  vazio à vista), bateria reserva no estrado logo embaixo, eletroduto, haste de
  aterramento e os cabos com barriga ligando gerador → caixa → abrigo → torre.
- **Transformador, parabólica de solo, depósito aberto e carretéis de cabo**:
  equipamento que ocupa o resto do pátio — e serve de cobertura parcial numa
  perseguição. O depósito tem 1 `PontoLoot`.
- **Cerca**: 9 studs de altura (o `JumpHeight` do personagem é 7,2, então **não
  dá pra pular**), postes a cada 8, malha de arames horizontais e verticais,
  arame farpado inclinado no topo, portão de duas folhas e placas de perigo.
  A malha é decoração; quem colide é uma **barreira invisível** por trecho —
  sem ela dava pra atravessar a cerca andando entre os postes.
  **Tem um rasgo de 14 studs na lateral +X** — de propósito.
- **Estrada**: 60 studs do portão até o terreno natural, com marcas de pneu e
  um pátio de manobra logo depois do portão. No terreno, o ramal de trilha sai
  do POI mais próximo (`IslandLayout`).

## Layout pensado pra gameplay

O pátio inteiro é **espaço aberto sem cobertura** — isso é o ponto.

- **O vaivém é o risco.** As etapas alternam dentro/fora de propósito: rack
  (dentro) → gerador (fora) → prateleira (dentro) → caixa (fora) → painel
  (dentro) → console (dentro). Ninguém termina o objetivo sem cruzar o pátio
  aberto quatro vezes.
- **Segurar o prompt é a moeda de tensão.** 4s abastecendo de costas pro pátio
  é o momento mais exposto do jogo. Quem está sozinho vai querer olhar em volta
  — e não vai poder.
- **O gerador é um chamariz.** Enquanto roda, faz barulho (`Sound` com
  `RollOffMaxDistance` 320), dispara `WeaponSystem.NoiseMade` a cada 12s e
  manda mensagem pro Monstro. Ligar o gerador é dizer "estamos aqui". Dá pra
  desligar de novo pra despistar — e perder o progresso do painel.
- **A baliza é o farol.** Pisca devagar mesmo sem energia (bateria de
  emergência): o Sobrevivente acha a estação no escuro, e o Monstro também.
  Com o gerador ligado ela pisca rápido e os holofotes acendem — o pátio vira
  o lugar mais iluminado (e mais visível) da ilha.
- **Duas entradas, duas fugas.** Portão na frente, rasgo na cerca na lateral.
  Quem entra pelo portão pode ser cortado; o rasgo é a saída de emergência —
  e a entrada favorita do Monstro, que não precisa do portão.
- **A torre é isca e armadilha.** A plataforma a 28 studs é escalável e dá
  visão do pátio inteiro, mas é beco sem saída: subir pra fugir é morrer mais
  devagar.
- **O abrigo é o único abrigo.** Porta de aço que fecha, uma janela, duas
  saídas impossíveis. Bom pra se esconder por 10 segundos, péssimo pra 30.
- **Sabotagem do Espião.** Gerador e painel têm `Sabotavel = true`, então o
  `SabotageSystem` já põe o prompt "Reparar" neles. Sabotar corta a energia na
  hora e derruba a transmissão — o Espião não precisa matar ninguém pra
  estragar a corrida inteira.
- **O chamado é público.** O progresso do socorro vai por
  `ObjectiveProgress("RadioSocorro", …)` pra todo mundo. O Monstro vê a barra
  subindo: os últimos 14 segundos são uma corrida declarada.

## Gerar / regerar

Modo de edição, Command Bar, e **salve** (Ctrl+S) depois:

```lua
local Radio = require(game.ServerScriptService.Server.Tools.RadioTowerGenerator)
Radio.Build()    -- apaga e refaz Workspace.Ilha.TorreDeRadio
Radio.Clear()
```

`Build()` terraplana o pátio, abre a estrada, apaga a vegetação que estava em
cima e monta tudo. Os dois assets só carregam em modo de edição; em runtime a
versão em Parts entra no lugar, sem erro.

O site "Radio" foi adicionado ao `IslandLayout.CONFIG.Sites` (no fim da lista,
pra não mudar onde os outros POIs caem na mesma seed). Isso dá **clareira
nivelada + ramal de trilha + marcador no mapa do Sobrevivente**, mas só depois
de regerar o terreno:

```lua
local Gen = require(game.ServerScriptService.Server.Tools.IslandGenerator)
Gen.Generate()        -- regera a ilha toda (alguns minutos)
Gen.GenerateCave()    -- a caverna é terreno: refaça depois de GenerateTerrain
Radio.Build()
```

Sem regerar, `Build()` ainda funciona: ele cai num ponto ao lado da Torre de
Vigia e faz o próprio terraplano e a própria estrada — só não ganha o ramal de
trilha nem o marcador no mapa.

## Poder da Sobrevivente: Conserto Relâmpago

`SurvivorPowerSystem` chama `RadioSiteSystem.ApplyPowerRepair(player)` (igual
já fazia com a Jangada). Só funciona em quem **está transmitindo agora**
(etapa 6): dá um empurrão instantâneo de `GameConfig.RadioSite.PowerBoostPercent`
(25 pontos) no chamado de socorro. É a única etapa com barra contínua pra
acelerar — as outras (abastecer, fusível, partida, painel) são "segurou o
prompt ou não".

## HUD (cliente)

`ObjectivesController` já mostra tudo:

- **Peças: X/3** — conforme instala no rack.
- **"Transmitindo socorro: X%"** — durante a etapa 6.
- **"Socorro enviado!"** em verde — ao concluir.
- Notificação temporária quando as 3 peças terminam de instalar e quando o
  socorro é enviado.

O texto/cor da torre reseta sozinho no início de cada rodada (fase "Queda") —
sem isso ficaria "Socorro enviado!" em verde grudado da rodada anterior até
alguém transmitir de novo.

## Ajustes

`GameConfig.RadioSite`: tempos de segurar, duração e raio do chamado,
decaimento do progresso, segundos por galão, intervalo do ruído, alcance das
interações e o bônus do Conserto Relâmpago. `RadioTowerGenerator.CONFIG`:
altura/base da torre, tamanho do pátio, da estrada e do abrigo, e o bloco
`Fence` (altura da cerca, espaçamento de postes e da malha, vão do portão e
onde fica o rasgo). Mudar `Yard`/`Shelter` reposiciona o interior junto — as
posições de dentro do abrigo são fração de W/D, não números soltos.

## Checklist de teste (Studio)

1. Modo de edição, Command Bar: `require(...RadioTowerGenerator).Build()` e
   salve. Confira visualmente torre, abrigo, gerador, tanque, cerca, estrada.
2. Ainda em modo de edição: `require(...ItemSpawner).Generate()` e salve —
   sem isso a Gasolina (e Lanterna/Chocolate/Bandagem/etc.) não existe no
   mapa nenhuma. Confira que apareceram uns galões portáteis pelo cenário
   (zonas de destroços/construções).
3. **Teste a cerca**: ande contra ela em vários pontos (não só nos postes) e
   tente pular — só deve dar pra entrar pelo portão ou pelo rasgo da lateral.
4. Play Solo com pelo menos os jogadores mínimos pra rodada começar.
5. Ache a Antena (destroços do avião), a Bateria (caverna) e o Transmissor
   (vila nativa) — ou olhe o Attribute de cada um (`PecaRadio`/`TipoPeca`).
6. Leve as 3 até o rack do abrigo, instale (prompt "Instalar peça"). HUD deve
   ir a 3/3 e notificar.
7. No pátio: "Pegar" o fusível reserva → "Instalar fusível" na caixa externa.
8. **Gasolina**: ache um Galão de Gasolina pelo mapa, carregue até o bocal do
   gerador e "Abastecer" — deve consumir o item (some do inventário) em vez
   do galão fixo do pátio. Teste também sem Gasolina no inventário: o prompt
   ainda usa o galão fixo normalmente.
9. "Abastecer" de novo com um galão fixo do pátio (repare que ele fica
   caído/vazio depois).
10. "Ligar gerador" no painel de partida — luzes/baliza aceleram, escapamento
    solta fumaça, e (quando o som existir) o motor toca.
11. Dentro do abrigo: "Ativar painel" — o som `RadioLigado` deve começar.
12. Na mesa: "Enviar socorro" e segure — HUD mostra "Transmitindo socorro: X%"
    e o som `PedidoSocorro` toca. Teste também: sair do alcance (`SinalRaio`
    = 9) cancela; desligar o gerador no meio cancela; sabotar o
    gerador/painel (prompt "Reparar" do Espião) cancela — e os dois sons
    param nessas três situações.
13. Ao chegar em 100%: HUD mostra "Socorro enviado!" e logo em seguida o
    aviso de extração ("corra até a fumaça vermelha na praia") com a
    contagem do helicóptero. A partida NÃO acaba aqui -- o resgate só vale
    se alguém chegar na praia depois do pouso (ver [Extracao.md](Extracao.md)).
14. Rode uma segunda rodada e confira que tudo volta a zero (combustível,
    fusível, peças, HUD) — `RadioSiteSystem.Reset()`/`RadioObjective.Reset()`
    rodam no preparo de cada rodada. A Gasolina NÃO respawna sozinha entre
    rodadas (mesmo comportamento de Lanterna/Chocolate/Bandagem); os 3
    galões fixos do pátio, sim.

## Som

Em `AssetRegistry.Sounds.RadioSite`. `RadioSiteSystem.syncSounds()` liga e
desliga pelo estado, num lugar só — nenhuma saída (sabotagem, combustível
acabando, reset de rodada) esquece de calar o rádio.

| Chave | Id | Quando toca | Alcance |
|---|---|---|---|
| `RadioLigado` | `4860560167` | loop no console a partir de "Ativar painel" | 70 |
| `PedidoSocorro` | `6985678040` | loop no console durante a canalização; para se cancelar | 140 |
| `Gerador` | **falta** | loop no motor enquanto o gerador roda | 320 |

O alcance do pedido de socorro (140) é maior que o do rádio parado (70) de
propósito: o chamado no ar vaza pra fora do abrigo, e é assim que o Monstro
descobre que tem alguém no console.

## Falta

Um `SoundId`: **`Gerador`** (hoje `rbxassetid://0`, o padrão de placeholder do
projeto — não toca, mas nada quebra). É o mais importante dos três: com
`RollOffMaxDistance` 320, é ele que denuncia a estação de longe e transforma
"ligar o gerador" numa decisão de risco. Sem ele o sistema funciona normal pra
teste, só fica mudo nesse ponto.
