# Barco de fuga — a segunda rota pra sair da ilha

Independente do rádio e do helicóptero. Os Sobreviventes consertam o motor
(hélice + vela de ignição), abastecem com Gasolina, põem a chave e pilotam
até o **limite do mapa** — um anel de boias no mar. Quem estiver sentado no
barco ao cruzar as boias vence, com a câmera subindo e o barco seguindo pro
mar aberto, como fim de filme.

Na vida real um barco não anda na areia: **se o barco sair da água, o hélice
fica no seco e o motor morre**. Pra voltar, alguém a pé empurra o barco de
volta pra água funda.

| Arquivo | Papel |
|---|---|
| `server/BoatSystem.lua` | Regras: prompts, assentos, motor, encalhe, anti-teleporte, limite e início da cena. |
| `server/BoatBuilder.lua` | Acha o barco do mapa ou monta a lancha padrão + píer; monta as boias do limite. |
| `server/BoatItems.lua` | Hélice, Vela, Chave e uma Gasolina por rodada; largar ao morrer; peça nunca some. |
| `Modules/BoatRules.lua` | Regras puras (testadas): física na água, ondas, encalhe, conserto, limite, trajetória da cena. |
| `Modules/BoatPhysics.lua` | Liga BoatRules aos atuadores do barco e sonda a profundidade debaixo do casco. |
| `client/BoatController.client.luau` | Piloto (roda a física como dono de rede), tecla do motor, prompts escondidos a bordo, cena de fuga. |
| `client/BoatCamera.lua` | Câmera de perseguição e a grua da cena de fuga. |
| `client/BoatEffects.lua` | Esteira, espuma, spray, hélice, escapamento, sons e boias piscando. |
| `client/BoatHUD.lua` | Checklist do barco, painel de pilotagem (nós, motor, limite) e faixas de cinema. |
| `server/RoundManager.lua` | `BoatSystem.Reset` no preparo; `SurvivorsEscaped` encerra; tempo acabando durante a cena vale a fuga. |
| `server/MatchRewardService.lua` | XP por etapa (`Barco_*`), objetivo `Barco` na primeira partida do motor, fuga `Barco`. |

## Linha do tempo

```
  PEÇAS          Hélice, Vela de ignição, Chave e um Galão de Gasolina
                 (teste: no píer, do lado do barco)
        │
        ▼
  MONTAR         capô do motor: "Instalar peça" (reparo de precisão, 3 acertos)
  ABASTECER      bocal na borda: segurar E 4s com a Gasolina
  CHAVE          ignição no painel: "Colocar chave" (ou dar partida com ela no bolso)
        │
        ▼
  PARTIDA        sentado no timão: F / Y / botão MOTOR
                 1,3s de motor de arranque -> motor pega, amarras soltam,
                 luzes de navegação e holofote acendem
        │
        ▼
  PILOTAR        o cliente do piloto vira dono de rede e roda a física;
                 o servidor confere cada deslocamento (anti-teleporte)
        │  saiu da água? motor morre -> "Empurrar pra água"
        ▼
  LIMITE         cruzou as boias com alguém sentado a bordo
        │
        ▼
  CENA (9s)      barco segue pro mar aberto, câmera sobe e se afasta,
                 faixas de cinema, "VOCÊ ESCAPOU", tela escurece
        │
        ▼
  vence quem estava a bordo ("Fuga de barco: nomes")
```

## O barco: o seu ou o padrão

O `BoatBuilder` procura, nesta ordem:

1. **Um Model com o Attribute `BarcoFuga = true`** — o jeito certo de usar o
   barco que você colocou no mapa. Selecione o Model no Explorer, adicione o
   Attribute booleano `BarcoFuga` marcado e salve.
2. Um Model com nome de barco (`Boat`, `SpeedBoat`, `Lancha`, `Barco`...,
   ver `GameConfig.Boat.NomesProcurados`) **com pelo menos um assento**, a até
   ~45 studs da costa pra dentro ou no mar. Construções com "barco" no nome
   não contam (píer, boias, casa de barcos, barco furado e canoa do Lago). É
   só um palpite: o Output avisa quando achou assim e sugere o Attribute.
3. Nada encontrado: a **lancha padrão** — uma lancha de console central em
   Parts (21,5 × 7 studs, 6 lugares, nome "ESPERANÇA" na popa), amarrada num
   píer de madeira na praia perto do **Farol**. O Farol aparece no mapa (M),
   então todo mundo acha o barco sem marcador novo.

**No mapa**: a cada rodada o servidor marca o barco (ícone de âncora azul,
"Barco de fuga") no mapa grande (M), no minimapa e no mapa do Monstro, pelo
mesmo canal dos itens descobertos (`Remotes.MapDiscovery`). Onde o barco
nasce é informação pública, como a estação de rádio.

O Output diz qual dos dois está valendo:
`[Barco] Usando o barco do mapa: Workspace.X` ou
`[Barco] Nenhum barco marcado no mapa -- lancha padrão com píer em (x, z)`.

### O que é feito com o barco do mapa

- Scripts do modelo são **desligados** e movers antigos (`BodyVelocity`,
  `BodyGyro`...) removidos — um barco do Toolbox costuma trazer o próprio
  controle, que brigaria com o nosso. O Output lista cada script desligado.
- Todas as Parts são soldadas numa raiz e soltas (a física é nossa).
- **Timão**: o primeiro `VehicleSeat` do modelo. Se ele só tiver `Seat`, o
  que tiver nome de piloto (`Piloto`, `Driver`, `Helm`...) vira timão (um
  `VehicleSeat` invisível no mesmo lugar). Sem assento nenhum, os lugares
  são criados invisíveis no meio do barco.
- **Frente**: o timão olha pra proa. Se o barco andar de lado ou de ré, ajuste
  `GameConfig.Boat.GuinadaModelo` (0 / 90 / 180 / 270).
- **Linha d'água**: fundo do modelo + `CaladoModelo` (0,8). Água do Terrain
  aparecendo dentro do casco = diminua; barco "voando" = aumente.
- Pontos de interação (motor, tanque, ignição, embarque, empurrar) e efeitos
  (esteira, spray, escapamento) são postos pela caixa do modelo.

## Montar e ligar

| # | Onde | Ação | Exige | Como |
|---|---|---|---|---|
| 1 | Capô do motor | **Instalar peça** | carregar a Hélice ou a Vela | reparo de precisão, 3 acertos seguidos (uma peça por vez) |
| 2 | Bocal na borda direita | **Abastecer** | um Galão de Gasolina | segurar E 4s; consome o galão |
| 3 | Ignição, no painel | **Colocar chave** | a Chave do Barco | toque |
| 4 | Timão | **Pilotar**, depois **F / Y / MOTOR** | 1 a 3 | 1,3s de partida |

- Montar, abastecer e pôr a chave: **só Sobrevivente** (igual a estação de
  rádio). Embarcar e pilotar: **Sobrevivente ou Espião** (igual o
  helicóptero). O Monstro nunca embarca.
- Dá pra dar partida com a chave no inventário: ao apertar F ela vai pra
  ignição. A chave fica no barco depois disso.
- F de novo desliga o motor. O checklist no canto superior esquerdo mostra o
  que falta pra todo mundo da partida — inclusive o Monstro, igual a barra do
  rádio.

## Pilotar

| | Teclado | Controle | Toque |
|---|---|---|---|
| Acelerar / ré | W / S | RT / LT | analógico |
| Virar | A / D | analógico esquerdo | analógico |
| Motor | F | Y | botão MOTOR |
| Sair | Espaço | A | pular |
| Olhar em volta | botão direito arrastando, roda = zoom | analógico direito | arrastar na tela |

O painel de pilotagem mostra a velocidade em **nós**, o estado do motor e
quantos metros faltam pro limite, com uma **seta** apontando o ponto do anel
mais perto (sempre pra fora da ilha) em relação à câmera — no escuro, em mar
aberto, é o que evita rodar em círculo.

Os controles vêm do próprio Roblox: o timão é um `VehicleSeat`, e o
`ControlModule` traduz teclado, controle e toque em `ThrottleFloat` /
`SteerFloat`. Sentado no barco nenhum prompt aparece (o E não abre
"Embarcar" do próprio barco).

### Como ele anda (BoatRules.Drive)

- **Arrancada**: empuxo forte que cai perto do máximo (58 studs/s ≈ 31 nós;
  o Monstro correndo faz ~27). Em 5s: ~160 studs e ~55 studs/s.
- **Proa sobe** na arrancada (~7°), assenta em ~2° planando e o casco sobe
  0,35 stud. Cortar o motor afunda a proa.
- **Sem acelerador a água freia**: de 58 pra ~12 em 5s, parado em ~10s.
- **Curva desliza**: a proa gira antes do casco mudar de rumo; o deslize morre
  pela aderência. Parado, só o empuxo do motor gira (30%); muito rápido, o raio
  de curva abre. O barco **deita pra dentro da curva**. De ré o volante inverte.
- **Ondas**: arfagem, caturro e balanço de mar calmo; em alta velocidade o
  casco bate no picado (spray na proa + tranco na câmera).

### Rede e anti-trapaça

O piloto é **dono de rede** do conjunto barco + passageiros: a física roda no
cliente dele, sem atraso, e a posição replica sozinha (é como todo veículo do
Roblox funciona). O servidor, a cada 0,1s:

- confere o deslocamento desde a última posição válida (tempo medido até 1s,
  pra rede engasgada não virar falso positivo): andou mais do que o motor
  consegue (`VelocidadeMax × ValidacaoFolga` + folga de replicação) = barco
  volta pra última posição válida;
- sonda a profundidade e decide o encalhe (a autoridade do motor é dele);
- decide se cruzou o limite (e quem estava sentado).

Sem piloto, o servidor assume o barco e roda a mesma física em ponto morto: o
barco desacelera sozinho e fica boiando nas ondas.

## Encalhe — igual na vida real

`BoatPhysics.Probe` solta dois raios no Terrain em três pontos do casco (proa,
meio, popa): o primeiro acha a superfície da água, o segundo o fundo.

| Situação | Estado | O que acontece |
|---|---|---|
| Água funda embaixo do casco | **Água** | navega normal |
| Proa ou popa raspando (menos que o calado) | **Raso** | velocidade máxima cai pra 35%, proa sobe, som de raspar, areia voando |
| Meio do casco sem água (ou assentado no fundo) | **Encalhado** | hélice no seco: **o motor morre**, sem flutuação, o casco arrasta até parar e fica |

Encalhado, o prompt **"Empurrar pra água"** aparece na proa e na popa pra quem
está a pé (segurar E 2,5s). O barco desliza pra água funda mais próxima, com a
proa virada pro mar, e aí é só dar partida de novo. A praia da ilha tem um
degrau de ~4 studs acima do mar: subir nela exige bater em velocidade — e o
barco fica lá, parado, até alguém empurrar.

## Limite do mapa e a cena de fuga

- O limite é um **anel de raio 900** em volta do centro da ilha (a costa fica
  entre 560 e 820; as paredes invisíveis em 952). 54 boias vermelhas com
  lanterna piscando marcam o anel; umas têm a placa "LIMITE · FUGA". O painel
  do piloto mostra quantos metros faltam.
- Cruzou com alguém sentado a bordo: o servidor **ancora** o barco e manda
  `BoatControl("Fuga")` pra todos. Cada cliente anima o barco seguindo reto
  pro mar (liso, a 60 fps, com ondas e esteira), então quem ficou na praia vê
  o barco indo embora.
- Quem estava a bordo ganha a cena: a câmera começa atrás do barco e vira uma
  **grua que sobe e se afasta** (até ~100 studs de altura) enquanto o barco
  continua pro horizonte; faixas de cinema entram, "VOCÊ ESCAPOU" aparece e a
  tela escurece no fim. Pular do barco fica desligado durante a cena.
- Depois de `DuracaoCinematica` (9s): `SurvivorsEscaped` → a partida acaba com
  "Fuga de barco: nomes". Se o tempo da partida acabar no meio da cena, a
  fuga vale do mesmo jeito.

## Espião e Monstro

- **Espião**: sabota a **fiação do motor** (`FiacaoMotor`, alvo `Sabotavel` do
  `SabotageSystem` que já existe). O motor morre na hora e não liga até um
  Sobrevivente fazer o "Reparar". O Espião também embarca e pilota, mas não
  carrega as peças do barco (igual as do rádio).
- **Monstro**: não embarca. Nadando até o barco devagar, ele ainda acerta quem
  está sentado; o Grab ignora quem está sentado. Com o barco em velocidade não
  há como alcançar.
- **O motor é barulhento** (igual o gerador do rádio): o ronco da partida vira
  um ping de 420 studs na super audição do Monstro, com a mensagem "Um motor
  de barco acabou de pegar...", e com o motor ligado sai um ping a cada 3,5s —
  220 studs em marcha lenta, até 480 acelerando tudo (`Ruido*` em
  `GameConfig.Boat`). Dar partida e ficar parado no píer esperando alguém é
  anunciar onde você está. A fonte do ping é o piloto (ou outro Sobrevivente
  a bordo), porque é assim que o `NoiseService` valida um ruído.

## Peças: onde nascem

`GameConfig.Boat.ItensPertoDoBarco = true` (**teste**, padrão): Hélice, Vela,
Chave e uma Gasolina no píer, do lado do barco — igual as peças do rádio ao
lado do gerador. Com `false`: Hélice na casa de barcos do Lago, Chave no
Farol, Vela e Gasolina em construções aleatórias (sem a construção no mapa,
caem no lugar de teste).

- Uma de cada por rodada; o reset da rodada some com as antigas (no chão, em
  gaveta ou na mochila de alguém).
- Quem morre carregando larga as peças onde caiu.
- Peça destruída sem ter sido instalada (quem carregava saiu do jogo, o drop
  expirou) **reaparece** no lugar de origem. A Gasolina não: é combustível
  comum, e repor viraria gasolina infinita pro gerador do rádio.
- Pegar uma peça dá XP de item importante; instalar cada etapa, XP de etapa.

## Ajustes

`GameConfig.Boat`: velocidades, aceleração, arrasto, giro, deslize, planeio,
ondas, calado e encalhe, raio do limite e espaçamento das boias, duração da
cena, lotação, tempos de segurar e onde as peças nascem. As peças vêm de
`ItemRegistry` (`HeliceBarco`, `VelaIgnicao`, `ChaveBarco`) e `ToolFactory`.

## Sons

`AssetRegistry.Sounds.Barco` — todos da **ProSoundEffects** (parceira oficial
do Roblox, domínio público: tocam em qualquer experiência), escolhidos pelo
nome e conferidos na API do Roblox, mas **não ouvidos**: vale escutar no
Studio e trocar o que não combinar.

| Chave | Id | Som | Quando |
|---|---|---|---|
| `Motor` | `9112780932` | Fishing Boat 1 | loop; pitch e volume seguem a rotação |
| `Partida` | `9112952113` | Jaguar E-Type cold start 2 | nos 1,3s de partida |
| `Morreu` | `9116985197` | Motor Wind-Down 7 | encalhe, sabotagem, desligar |
| `Agua` | `9112750448` | Bow Wash Slow Trolling Speed 1 | loop; sobe com a velocidade |
| `Raspando` | `9113467572` | Boat Slide 1 | loop no raso/areia |
| `Batida` | `rbxasset://sounds/impact_water.mp3` | nativo | casco batendo em onda |

## Falta

- Ícones das três peças (`ItemIcons.Map`) — até lá a hotbar mostra o modelo 3D.

## Testes

```sh
python3 tests/run_boat.py ~/.rokit/bin/luau
```
Regras puras contra a GameConfig real: arrancada, arrasto, ré, motor
desligado, encalhe, raso, leme, deslize, independência de FPS, ondas,
classificação de profundidade, conserto, limite, anti-teleporte e a
trajetória da cena.

```sh
python3 tests/run_boat_system.py ~/.rokit/bin/luau
```
O `BoatSystem` real com jogadores, assentos, prompts e relógio falsos:
sentar/levantar/morrer sentado, dono de rede, motor (peças, gasolina, chave,
sabotagem, desligar), ruído pro Monstro, anti-teleporte (inclusive rede
engasgada), encalhe e empurrão (F logo depois do empurrão), limite, cena,
fim de rodada, reset e lotação.

Física de verdade no engine (lugar descartável, abre o Studio sozinho — feche
o seu Studio antes, senão o `run-in-roblox` não consegue subir o dele):

```sh
rojo build tests/Boat.project.json --output /tmp/boat-validation.rbxlx
run-in-roblox --place /tmp/boat-validation.rbxlx --script tests/boat.studio.luau
```
Gera o trecho da ilha perto do Farol e dirige a lancha padrão com os
atuadores reais: boiar parado, arrancar, virar, frear pela água, não andar na
areia e o `BoatSystem.Init` completo (prompts, peças, boias, ponto morto).

### Checklist no Studio (Test → Server & Clients, 2+ jogadores)

1. Output: `[Barco] ...` dizendo qual barco está valendo e
   `[Barco] Pronto -- limite do mapa a 900 studs`.
2. Vá ao Farol pelo mapa (M): píer com a lancha amarrada e o lampião aceso.
   As quatro peças estão nas tábuas, com destaque e etiqueta.
3. Tente "Pilotar" e F sem nada instalado: a mensagem diz o que falta.
4. Instale Hélice e Vela no capô (minigame), abasteça (4s), ponha a chave. O
   checklist marca cada etapa; ao fechar, aviso grande "O barco está pronto!".
5. Pilote e aperte F: 1,3s de partida, amarras somem, luzes acendem, fumaça.
6. W: proa sobe, espuma e fita de esteira atrás, spray na proa planando,
   câmera afasta e abre o FOV. A/D: o barco deita pra dentro e desliza.
7. Solte W: desacelera sozinho. S: freia, depois ré (volante invertido).
8. Jogue o barco contra a praia em alta: "RASPANDO NO FUNDO", e se subir na
   areia, **"ENCALHADO"**, motor morre, W não faz nada. Desça e segure
   "Empurrar pra água" na proa/popa: o barco volta pra água; F liga de novo.
9. Espião: sabote a fiação do motor — o motor apaga e não liga; Sobrevivente
   repara pelo minigame.
10. Com um passageiro a bordo, pilote até as boias: ao cruzar, faixas de
    cinema, câmera subindo, barco seguindo pro mar, "VOCÊ ESCAPOU", tela
    escura e o resultado "Fuga de barco: nomes". Um jogador na praia vê o
    barco indo embora.
11. Segunda rodada: barco de volta no píer, desmontado, peças novas (sem
    cópias da rodada anterior).
12. Controle e celular: acelerar/virar pelo analógico, botão MOTOR, pular pra
    sair, arrastar a tela pra olhar em volta.
