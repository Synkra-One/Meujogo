# Estação de Rádio — o objetivo de socorro

O local físico do objetivo do Rádio: torre de transmissão, abrigo técnico,
gerador, combustível, quadro elétrico, cerca e a estrada de manutenção. É um
sítio de repetidora semi-realista — tudo que existe lá existiria de verdade —
mas as distâncias e os tempos são de gameplay, não de engenharia.

| Arquivo | Papel |
|---|---|
| `Tools/RadioTowerGenerator.lua` | **Constrói** o local (ferramenta de editor). Terraplana o pátio, abre a estrada e monta tudo. |
| `server/RadioSiteSystem.lua` | **Faz funcionar**: combustível, fusível, gerador, painel, pedido de socorro, baliza, barulho, sabotagem. |
| `server/RadioPieces.lua` | Teste: três peças e um item Gasolina junto do gerador, repostos por rodada. |
| `server/RadioInstallSystem.lua` | Instala as peças no rack do abrigo. |
| `server/InteractionGuard.lua` | Valida distância e caminho sem obstáculos no servidor para coleta e tasks. |
| `Modules/ItemRegistry.lua` + `ToolFactory.lua` | Item "Gasolina" (`Tool`, achado no mapa via `ItemSpawner`) que também abastece o gerador. |
| `server/RadioObjective.lua` | Estado do objetivo; `CompleteRescueCall` dispara a contagem de resgate. |
| `client/ObjectivesController.client.luau` | HUD: barra de peças, texto de status da torre (transmitindo/enviado), notificações. |
| `server/ExtractionSystem.lua` | O que vem DEPOIS do socorro: helicóptero na praia (ver [Extracao.md](Extracao.md)). |

## A corrente de interações

Seis etapas, nesta ordem. Cada uma é um `ProximityPrompt` criado a partir do
Attribute `InteracaoRadio` das Parts geradas.

| # | Onde | Ação | Exige | Como |
|---|---|---|---|---|
| 1 | Rack, dentro do abrigo | **Instalar peça** | as 3 peças achadas no mapa | minigame: 3 acertos seguidos |
| 2 | Bocal do gerador | **Abastecer** | item Gasolina no inventário do jogador | segurar E, 4s |
| 3 | Prateleira → caixa na parede | **Pegar fusível** → abrir a caixa e arrastar o fusível até o encaixe vazio | carregar o fusível | 0s / arrasta-e-solta |
| 4 | Painel de partida | **Ligar gerador** | fusível + combustível + não sabotado | minigame: 3 acertos seguidos |
| 5 | Painel de controle, dentro | **Ativar painel** | gerador ligado + peças instaladas | minigame: 3 acertos seguidos |
| 6 | Console do rádio, dentro | **Enviar socorro** | painel ativo | canalizado 14s |

As etapas 1, 4 e 5 abrem o **reparo de precisão**
([ReparoMinigame.md](ReparoMinigame.md)): o jogador só conclui
acertando o timing **3 vezes seguidas**; errar zera a sequência e faz barulho
pro Monstro. Segurar sem apertar nada nunca conclui. A dificuldade depende do
atributo Reparo. **Desligar** o gerador (etapa 4 com ele já
ligado) continua instantâneo. A etapa 2 (**Abastecer**) continua sendo
"segurar E" (`HoldAbastecer`): é um `ProximityPrompt` de segurar, e é o
`PromptButtonHoldBegan` dele que liga a pose de interação. `HoldPartida` e
`HoldPainel` só valem se o minigame daquela etapa for desligado em
`RepairMinigameConfig.Tasks`.

No fim da etapa 6 sai `RadioObjective.CompleteRescueCall` -> `RescueCountdownStarted`
-> `RoundManager` chama a **extração**: nasce uma zona de pouso na praia com
fumaça vermelha e começa a contagem do helicóptero. **Concluir o rádio não
ganha a partida** -- ainda é preciso atravessar a ilha e embarcar. Ver
[Extracao.md](Extracao.md).

**Onde as peças ficam agora para teste rápido:** Antena, Bateria e Transmissor
nascem ao lado do gerador da estação de rádio, junto de um item Gasolina. Assim dá para validar coleta,
instalação no rack, combustível, fusível, partida, painel e transmissão sem
atravessar a ilha.

## Combustível: somente o item Gasolina

O bocal exige uma Tool `Gasolina` no Character ou Backpack de quem interage.
O servidor valida tempo de interação, alcance, partida e posse novamente ao
concluir. Só então consome um item e enche o tanque com até 270s. Gasolina de
outro jogador não é aceita; tanque cheio não consome o item.

Os galões fixos antigos, incluindo alças e bicos, são removidos por
`RadioTowerGenerator.Ensure()` nos mapas salvos. O tanque grande é cenográfico.
`Ensure()` valida pontos únicos de interação, motor, escapamento e rack antes
de conectar os sistemas; uma estação incompleta é reconstruída no boot.

O item de teste usa `ToolFactory` e `DropItemSystem`, como os demais itens.
Cada rodada remove a cópia anterior, mesmo carregada, e cria uma nova.
Falha no asset visual usa uma Tool funcional de reserva; `ItemSpawner` só
contabiliza Tools realmente criadas. Após enviar o socorro, o gerador desliga
e as ações da estação são bloqueadas. O resgate continua válido sem energia.

## Planta do sítio

Visto de cima. O portão fica virado pro centro da ilha, que é de onde a trilha
de manutenção chega.

```
  ┌────────────────── cerca 132 x 112 (9 de altura) ───────────────────┐
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
  │   [bateria]                               ║ tanque  ║               │
  │                                           ╚═════════╝               │
  │   ○ holofote            ‖ ‖ manobra                     holofote ○   │
  └──────────────────────── PORTÃO (18) ────────────────────────────────┘
                                 │
                          estrada (72 x 16)
                                 │
                          trilha da ilha
```

O pátio passou de **88 x 76 para 132 x 112**: aproximadamente **2,2 vezes a
área anterior**. O abrigo passou de **20 x 14 para 36 x 26**, com 13 studs de
altura. Gerador, combustível, torre e depósito foram redistribuídos; os
acessos de pedestres têm marcação própria e não atravessam as bancadas.

- **Torre** (fundo à direita): 105 studs — o dobro da árvore mais alta (30–56).
  Estais ancorados em blocos de concreto, plataforma de serviço a 28 studs com
  escada de treliça escalável, baliza vermelha piscando no topo e outra no
  meio. Asset `8788183000`; se ele não carregar, entra uma treliça em Parts com
  a mesma silhueta.
- **Abrigo** (frente à esquerda): 36 x 26, alvenaria com pilares aparentes,
  marquise de entrada, telhado metálico e duas portas de aço controladas pelo
  `DoorSystem`. Janela com vidro sólido. Interior com corredor livre de 12
  studs, sinalização dos setores, rack do transmissor (fundo esquerdo),
  painel de controle (parede lateral), mesa do operador com o rádio (direita),
  prateleira baixa com o fusível reserva e 2 `PontoLoot`. Luz de emergência
  independente e luminárias principais vinculadas ao gerador.
- **Gerador** (meio do pátio): base de concreto com faixa zebrada, escapamento
  que solta fumaça quando roda, bocal de combustível e painel de partida.
  Asset `10685426940`, com fallback em Parts.
- **Combustível** (canto direito, longe do abrigo): tanque horizontal sobre
  cavaletes dentro de uma bacia de contenção. Tanque apenas cenográfico.
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
- **Estrada**: 72 studs do portão até o terreno natural, 16 de largura, com marcas de pneu e
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
- **O abrigo oferece duas rotas.** Entrada principal e porta de serviço
  lateral; o vidro deixa entrar luz, mas não permite atravessar nem coletar
  itens através dele. Ambas as portas abrem pelo sistema já existente.
- **Sabotagem do Espião.** Gerador e painel têm `Sabotavel = true`, então o
  `SabotageSystem` já põe o prompt "Reparar" neles. Sabotar corta a energia na
  hora e derruba a transmissão — o Espião não precisa matar ninguém pra
  estragar a corrida inteira.
- **O chamado é público.** O progresso do socorro vai por
  `ObjectiveProgress("RadioSocorro", …)` pra todo mundo. O Monstro vê a barra
  subindo: os últimos 14 segundos são uma corrida declarada.

## Gerar / regerar

Conecte/sincronize o projeto pelo Rojo. Fora do Play, execute na Command Bar
e **salve** (Ctrl+S) depois. Isto atualiza apenas a estação; não é necessário
regerar a ilha inteira. Sincronizar scripts sozinho não modifica a geometria
de uma estação já salva.

```lua
local tools = game.ServerScriptService.Server.Tools
local builder = tools.RadioTowerGenerator:Clone()
builder.Parent = tools -- evita reutilizar o cache de require da versão anterior
local ok, result = pcall(function() return require(builder).Build() end)
builder:Destroy()
assert(ok, result)
```

`Build()` preserva a posição/rotação da estação existente, terraplana o pátio,
abre a estrada e monta tudo. Antes disso, em modo de edição, cria um backup
em `ServerStorage.MapEditBackups.Radio_<data>_<índice>` com a construção
anterior, a vegetação/rochas retiradas e `TerrenoAnterior` (`TerrainRegion`).
O atributo `MinCell` guarda a origem para `Terrain:PasteRegion`; as pastas de
vegetação mantêm os nomes originais para restauração manual. Não use
`Radio.Clear()` depois de construir — esse método remove a estação.

Se os assets não carregarem, a versão em Parts entra no lugar. Para validar
sem downloads, use `Radio.CONFIG.Assets.Tower = 0` e `Generator = 0` antes do
Build. O fallback em runtime não altera terreno nem remove vegetação.

O site "Radio" foi adicionado ao `IslandLayout.CONFIG.Sites` (no fim da lista,
pra não mudar onde os outros POIs caem na mesma seed). Isso dá **clareira
nivelada + ramal de trilha + marcador no mapa do Sobrevivente**, mas só depois
de regerar o terreno:

```lua
local Gen = require(game.ServerScriptService.Server.Tools.IslandGenerator)
Gen.Generate()        -- regera a ilha toda (alguns minutos)
Gen.GenerateCave()    -- a caverna é terreno: refaça depois de GenerateTerrain
require(game.ServerScriptService.Server.Tools.RadioTowerGenerator).Build()
```

Sem regerar a ilha, `Build()` ainda funciona: mantém a estação salva, ou usa
o site Radio do layout para uma nova estação, e faz o próprio terraplano e
estrada. A clareira dos mapas novos reserva raio de 96 studs. O ramal de
trilha e os marcadores de um mapa antigo não são regerados por esse comando.

## Paredes, câmera e coleta

Os prompts de itens, munição, caixas e tarefas do rádio exigem linha de
visão. As peças do rádio usam destaque ocluído e etiquetas que não aparecem
por cima das paredes. A câmera padrão usa oclusão `Zoom`, sem tornar paredes
transparentes para mostrar o jogador.

Além do visual, `InteractionGuard.CanReach` verifica no servidor a distância,
vida do jogador e um raycast da cabeça até o alvo. Paredes, portas fechadas e
vidros sólidos bloqueiam a ação; detalhes sem colisão não bloqueiam os botões.
Isso também cobre coleta por toque das peças e materiais legados. A
transmissão de socorro para quando o jogador se esconde atrás de um obstáculo.

Teste automatizado no engine, em lugar descartável:

```sh
rojo build tests/RadioStation.project.json --output /tmp/radio-validation.rbxlx
run-in-roblox --place /tmp/radio-validation.rbxlx --script tests/radio_station.studio.luau
```

Valida os sete pontos de interação, nomes/atributos, inicializadores reais,
as duas portas, parede, vidro, distância e backup em modo de edição. As
regressões de coleta de armas/munição ficam em `tests/firearms.luau`.

## Poder da Sobrevivente: Conserto Relâmpago

`SurvivorPowerSystem` chama `RadioSiteSystem.ApplyPowerRepair(player)` (igual
já fazia com os objetivos anteriores). Só funciona em quem **está transmitindo agora**
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
2. Confira que não existem galões decorativos na estação. No Play, há um
   item Gasolina junto das peças. `ItemSpawner.Generate()` continua criando
   os itens distribuídos pelo restante do mapa.
3. **Teste a cerca**: ande contra ela em vários pontos (não só nos postes) e
   tente pular — só deve dar pra entrar pelo portão ou pelo rasgo da lateral.
4. Play Solo com pelo menos os jogadores mínimos pra rodada começar.
5. Ache Antena, Bateria, Transmissor e Gasolina ao lado do gerador.
6. Leve as 3 até o rack do abrigo, instale (prompt "Instalar peça"). HUD deve
   ir a 3/3 e notificar.
7. No pátio: "Pegar" o fusível reserva → "Instalar fusível" na caixa externa.
8. Sem Gasolina no inventário, tente abastecer: o combustível deve continuar
   zerado. Repita com outro jogador carregando gasolina longe do bocal.
9. Pegue o item, segure Abastecer por 4s: deve consumir exatamente uma Tool
   e encher o tanque com 270s. Interrompa, largue o item durante a ação e
   repita o evento: nunca deve duplicar combustível. Tanque cheio não consome item.
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
    rodam no preparo de cada rodada. As três peças e o item Gasolina de teste
    reaparecem uma única vez, inclusive se alguém os carregava antes.
15. Do lado de fora, encoste na parede: não deve aparecer a etiqueta nem ser
    possível coletar itens internos. Repita com as duas portas fechadas e a
    janela. Abra uma porta e aproxime-se pela passagem: a coleta deve funcionar.
16. Aproxime a câmera de paredes/cantos em terceira pessoa e com mira;
    confira que não atravessa nem torna o abrigo transparente.

Regressão determinística: `python3 tests/run_radio_escape.py` executa os
módulos reais de rádio, instalação, extração, passageiros e câmera, cobrindo
interrupções, consumo, autorização e resets. O timing do reparo é coberto por
`python3 tests/run_repair_minigame.py`. Renderização/física exigem Play no Studio.

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
