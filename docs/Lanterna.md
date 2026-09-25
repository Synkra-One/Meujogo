# Lanterna

O item `Lanterna` usa primeiro a Tool `Flashlight` do pacote Arczis versionado em
`ServerStorage/ArczisRealisticFlashlight`. Ela fica como template inerte: scripts
embutidos sao removidos, e o sistema existente do jogo continua dono de input,
bateria, luz, dano, HUD, hotbar, drop e pickup. Se o pacote nao existir, o
construtor ainda consegue cair no asset **6715358554** registrado em
`ItemRegistry.lua`. Continua entrando pelos pickups e pelo loot do mapa.

O `StarterPack` fica vazio: o jogador nao comeca com lanterna. Se uma Tool
antiga chamada `Lanterna`/`Flashlight` ou marcada como lanterna aparecer no
Backpack, `StarterGear` ou equipada, `FlashlightSystem` a remove. As lanternas
obtidas no mapa usam a Tool normalizada pelo `ToolFactory`.

A Tool Arczis preserva a escala e o `Grip` do pacote. Na criacao da Tool real,
o jogo remove scripts embutidos, substitui luzes antigas pelas luzes seguras do
jogo e deixa todas as pecas desancoradas, sem colisao, toque ou consulta fisica
e sem massa. A normalizacao para 1,8 studs fica apenas para o fallback via asset.

## Controles

- Equipar pela hotbar existente.
- Clique/toque de uso da Tool ou `T`: alternar a luz.
- Controle: ativacao da Tool ou `Y`.
- Celular: botao com a miniatura da lanterna.
- Disparo concentrado: `V` no PC, `L2` no controle ou botao `Clarao` no celular.
  Custa 25% da reserva de bateria e tem cooldown de 8 segundos. Configuracao,
  arquitetura e roteiro completo: [Disparo concentrado](FlashBurst.md).

`F` continua reservado para interagir com os objetos do jogo. O braco acompanha
o centro da camera com suavizacao curta, inclusive para cima, para baixo e
para os lados (limites de 80 graus em relacao ao personagem). A cabeca acompanha
parte desse movimento. A Tool permanece presa ao `RightGrip` criado pelo Roblox.
O emissor e as duas pontas do feixe ficam no espaco local do Handle: a luz segue
a lente fisica, sem uma segunda rotacao independente da camera.

A mira da camera e recalculada a cada frame. A falta temporaria de atualizacoes
da mira nao desliga a Tool. A verificacao de parede do feixe tambem se renova
quando a lente muda de posicao ou direcao, mesmo antes do intervalo normal de
1/15 segundo. Se a lente atravessar uma parede, somente a origem visual da luz
recua para o lado do jogador; a origem de gameplay continua validada pelo
servidor. A iluminacao permanece ligada mesmo com a lente muito perto de uma
superficie.

## Animacoes R6

Ao equipar, a lanterna usa as animacoes publicadas do pacote Arczis:

| Estado | ID |
| --- | --- |
| Click | `rbxassetid://92755233522139` |
| Equip | `rbxassetid://82905353934076` |
| Idle | `rbxassetid://103502806390125` |

`FlashlightPose` toca `Equip` uma vez ao equipar, mantem `Idle` em loop enquanto
a Tool esta equipada e toca `Click` junto do ligar/desligar. Nao existem clips
proprios de Walk/Run/Sprint da lanterna: as pernas continuam do `Animate` e do
pacote de movimento, enquanto o `Idle` da lanterna deve conter apenas a camada
superior do R6. Se a animacao publicada tambem tiver keyframes das pernas, o
Roblox vai misturar esses joints tambem; nesse caso, republique o clip removendo
as chaves de `Left Leg` e `Right Leg`.

Agachado e Air seguem a mesma regra: locomocao existente por baixo, camada de
lanterna por cima. Crawl libera completamente os bracos para a animacao de
rastejar. Hurt, Death, agarramento, teleporte, stun e tropeço interrompem a
camada da lanterna; por isso a reacao de dano continua ativa sem ser coberta
pelo idle da lanterna.

Os IDs ficam em `src/ReplicatedStorage/Modules/FlashlightConfig.lua`, em
`Animations.Click`, `Animations.Equip` e `Animations.Idle`.

Nao sao necessarios clips novos para olhar nas diferentes direcoes.
`FlashlightPose` converte a rotacao para os eixos dos joints R6 e calcula o
alinhamento do ombro direito usando a orientacao real da lente. A camada anterior
e removida em `PreAnimation`, e a nova pose entra em `PreSimulation`, depois do
Animator. Isso evita tanto a sobrescrita da mira quanto acumulo de rotacao em
joints sem keyframes. O cleanup preserva a animacao-base e escritas posteriores
de outros sistemas. Essa ordem segue o ciclo documentado de
[Motor6D.Transform](https://create.roblox.com/docs/reference/engine/classes/Motor6D/Transform).

O feixe combina foco principal com luz periferica e preenchimento proximo. A
iluminacao continua nao consome bateria e nao pisca com carga baixa. A carga
serve apenas para os claraoes; mesmo em 0%, a luz normal pode ser ligada e
permanece acesa ate o jogador desliga-la ou uma regra do jogo interrompe-la
(por exemplo, desequipar, morte ou apagao do Monstro).

## Balanceamento

Todos os parametros ficam em `src/ReplicatedStorage/Modules/FlashlightConfig.lua`.

| Parametro | Inicial |
| --- | --- |
| BatteryMax | 100 |
| BatteryDrainRate | 0 para iluminacao continua |
| FlashlightRange | 36 studs |
| BeamAngle | 38 graus |
| LightRange (iluminacao visual) | 44 studs |
| LightAngle (iluminacao visual) | 48 graus |
| Brightness | 4,6 |
| SpillAngle / SpillBrightness | 76 graus / 1,0 |
| FillRange / FillBrightness | 9 studs / 0,25 |
| ExposureRate | 1 por segundo |
| ExposureDecayRate | 1,5 por segundo |
| EffectStartExposure | 1 segundo |
| MaxExposure | 6 segundos |
| MonsterSlow | 8% no maximo |
| Damage | ate 4 HP, respeitando reducoes de dano |
| DamageExposure | 2,5 segundos |
| DamageCooldown | 4 segundos por monstro |
| MaxExposureDisorientation | 0,65 segundo |
| ResistanceDuration | 5 segundos apos a desorientacao |
| ResistanceEffectMultiplier | 10% do efeito normal |

`LightRange` e `LightAngle` controlam a iluminacao do cenario; `FlashlightRange`
e `BeamAngle` continuam controlando o cone de exposicao do monstro no servidor.

O primeiro segundo causa somente incomodo visual leve. A lentidao cresce
depois disso. O pico e audiovisual, sem zerar WalkSpeed, bloquear ataques,
remover controle da camera ou aplicar `PowerStunned`. Durante a resistencia
nao ha dano nem acumulo de exposicao, e a lentidao/efeitos caem para 10%.
Apos a resistencia, e preciso reconstruir a exposicao desde zero.

`DamageSystem.Apply` recebe um teto server-only (`MaxDamage`) depois dos
multiplicadores de atributos: bonus de forca nao transformam a lanterna em
uma arma de dano alto. Chamadas existentes sem esse campo mantem seu comportamento.

## Bateria e Ciclo de Vida

A carga exata fica no servidor; o atributo `Tool.Battery` publica decimos de
porcentagem para a HUD. A iluminacao nao gasta carga; cada clarao consome 25
pontos percentuais. Ao zerar, apenas novos claroes ficam indisponiveis. Nao
existe regeneracao passiva.
Trocar de item, largar, recolher ou trocar de dono nao recarrega a Tool.
Uma Tool nova comeca cheia. Desequipar, morrer, perder a funcao de sobrevivente,
ficar preso ou encerrar a rodada desliga a luz.

API de recarga para uso por outros sistemas do servidor:

```lua
local FlashlightSystem = require(game.ServerScriptService.Server.FlashlightSystem)
FlashlightSystem.Recharge(tool, 25)
```

A API limita a carga a 100 e nao religa automaticamente. Nenhum RemoteEvent
aceita pedidos de recarga do cliente. Nao foi acrescentado um novo consumivel.

## Pickups no Mapa

`ItemSpawner` agora coloca a Tool real no chao para itens de categoria `Tool`,
incluindo a Lanterna, em vez de um cubo generico com prompt. `DropItemSystem`
continua sendo a entrada unica para pegar/largar Tools, entao as lanternas do
mapa, de caixa, de drop de jogador e de inventario usam o mesmo ciclo.

Mapas salvos com pickups antigos como `Lanterna_Pickup` sao migrados no boot:
o Part antigo vira uma Tool real no mesmo lugar e ganha o prompt `Pegar`.

## Multiplayer e Organizacao

- `FlashlightSystem`: posse, papel, bloqueios, bateria, ciclo de vida e exposicao.
- `FlashlightTargeting`: origem, alcance, cone e visibilidade por Raycast.
- `FlashlightRules`: regras deterministicas de bateria e exposicao.
- `FlashlightRig`: montagem do modelo e attachments da luz.
- `FlashlightController`: entrada, previsao local e reconciliacao com sequencia.
- `FlashlightPose`: pose procedural local dos bracos ao segurar/apontar.
- `FlashlightVisuals`: luz com sombras, feixe e orientacao para cada observador.
- `FlashlightHUD`: indicador compacto acima da hotbar, com alertas de carga.
- `FlashlightExposureFX`: blur, cor e audio locais exclusivos do monstro.

O servidor aceita somente intencao de ligar/desligar e direcao unitario-finita.
Ele nunca recebe alvo, origem, dano ou bateria como autoridade do cliente.
Uma verificacao entre cabeca e emissor impede iluminar usando uma mao que
atravessou uma parede. Cada amostra de cabeca/torso precisa estar no cone e ter
o proprio monstro como primeiro obstaculo atingido. Outros objetos e jogadores
tambem podem bloquear a luz.

### Attributes que travam a lanterna

`FlashlightConfig.BlockingFlags` e a lista unica lida pelo servidor
(`FlashlightSystem.canUse`) e pelo cliente (`FlashlightController.blockedReason`).
Enquanto qualquer um desses Attributes for `true` no character OU no Player, a
lanterna apaga e nao liga -- a Tool continua no inventario, com a mesma bateria:

`GrabLocked`, `ShadowRushBusy`, `TeleportBusy`, `PowerStunned`, `Amarrado`,
`AbyssBlackout` (Apagao do Abismo, ver [ApagaoDoAbismo.md](ApagaoDoAbismo.md)).

Um poder novo so precisa ligar o Attribute e adiciona-lo a essa lista; nada de
segunda lanterna nem de mexer no inventario. `FlashlightSystem.ForceOff(character)`
apaga no mesmo frame quem ja estava com a luz ligada, sem nunca acender nada.

Ha uma unica exposicao, resistencia e janela de dano por monstro. Duas ou mais
lanternas nao multiplicam essas taxas. Dano/efeitos exigem rodada ativa e ambos
os jogadores na partida; invulnerabilidade e ForceField sao respeitados.

O servidor verifica a cada 0,1 segundo, sem Raycast nos callbacks dos remotes.
O cliente envia mira no maximo a 8 Hz e reduz envios quando ela nao muda;
a ultima direcao valida permanece enquanto a luz esta ligada.
HUD atualiza a 20 Hz; apresentacao e suavizada localmente. O servidor publica
somente atributos alterados. A lentidao usa `MonsterCombat.MonsterSpeedMul`,
que o pacote de movimento ja le, sem um segundo escritor de WalkSpeed.

As tochas e zonas seguras continuam no sistema `MonsterLightWeakness`.
A lanterna nao dispara mais o empurrao por proximidade desse sistema, nem
habilita por si so a finalizacao de lanca ancestral baseada em `IsWeakened`.

## Validacao

```sh
ruby tests/run_flashlight_tests.rb /caminho/para/luau
python3 tests/run_flashlight_presentation.py /caminho/para/luau
rojo build default.project.json -o /tmp/Meujogo-lanterna.rbxlx
```

A suite executa os modulos reais com servicos simulados: bateria, cone,
exposicao, resistencia, duas lanternas, paredes, origem adulterada, remotes
invalidos, limites de frequencia, lobby, drop, morte, recarga e teto de dano.
Compilacao Luau e build Rojo tambem foram verificados. O asset foi inspecionado
no Studio, mas a validacao visual em partida multiplayer e em celular ainda
precisa ser concluida no Studio.

A suite de apresentacao executa `FlashlightPose` e `FlashlightVisuals` com
matrizes 3D e um ombro/pescoco R6 simulado. Verifica mira vertical/lateral,
estabilidade a 30/60/144 FPS, restauracao da animacao-base, bloqueio, desequipar,
alinhamento lente/feixe e oclusao. Nao substitui o playtest dos assets e da
renderizacao no Studio.

Roteiro de playtest: dois sobreviventes apontando para um monstro, com uma
parede entre eles; alternar cobertura, conferir o dano e o pico, largar e
recolher a Tool, esgotar a reserva de claroes e trocar de rodada. Conferir caminhada,
corrida, agachamento, mira vertical e layout em tela pequena.

Referencias das APIs: [SpotLight](https://create.roblox.com/docs/reference/engine/classes/SpotLight)
e [Attachment](https://create.roblox.com/docs/reference/engine/classes/Attachment).
