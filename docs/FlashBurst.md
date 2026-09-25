# Disparo concentrado da lanterna

A habilidade usa a mesma Tool, bateria, `Remotes.Flashlight`, controlador,
HUD e apresentacao da lanterna normal. Nao adiciona scripts dentro da Tool,
outro RemoteEvent, outro loop servidor ou outro sistema de velocidade.

## Uso e comportamento

- PC: **V**. Controle: **L2**. Mobile: botao **Clarao**.
- Funciona equipada, com a luz normal ligada ou desligada. Esgotar a reserva
  impede novos claroes, mas nao apaga a iluminacao normal.
- Custa **25 pontos percentuais** da bateria e exige **8 segundos** entre usos.
  Trocar de lanterna ou passar a mesma Tool a outro jogador nao burla o cooldown.
- Um disparo valido consome carga mesmo sem monstro por perto. Errar a mira ou
  atingir uma parede mostra **SEM ACERTO**. Um alvo imune nao recebe efeitos.
- Acerto: **2s parado**, **2,5s sem poderes/ataque**, **4s de ofuscamento e
  zumbido decrescentes**. O clarão nao adiciona dano: o dano gradual normal
  da lanterna e a fraqueza existente a luz continuam com suas regras.
- O primeiro monstro visivel dentro do cone recebe o efeito. O proprio
  sobrevivente e outros sobreviventes nunca sao alvos.
- O HUD indica custo, acerto/erro/recusa e cooldown. O anel de bateria existente
  recebe o mesmo atributo `Battery` atualizado pelo servidor.

## Configuracao central

Editar `src/ReplicatedStorage/Modules/FlashlightConfig.lua`:

| Campo | Valor inicial | Efeito |
| --- | --- | --- |
| `FlashBurstCost` | 25 | Custo em pontos percentuais da bateria |
| `FlashBurstCooldown` | 8 | Segundos entre disparos |
| `FlashBurstRange` | 32 | Alcance em studs |
| `FlashBurstAngle` | 24 | Abertura total do cone em graus |
| `FlashBurstStunDuration` | 2 | Duracao do atordoamento |
| `FlashBurstPowerBlockDuration` | 2,5 | Duracao do bloqueio de poderes |
| `FlashBurstBlindDuration` | 4 | Duracao de tela clara/zumbido |
| `FlashBurstKey` | `V` | Tecla, sem conflito com X/amarrar |
| `FlashBurstGamepadKey` | `ButtonL2` | Gatilho do controle |
| `FlashBurstInputInterval` | 0,15 | Limite de pedidos, inclusive invalidos |
| `FlashBurstMaxAimYaw` / `FlashBurstMaxAimPitch` | 100 / 88 | Tolerancia da mira frente ao corpo |
| `FlashBurstVisualDuration` | 0,32 | Duracao do clarão/recuo |
| `FlashBurstBrightness` | 16 | Intensidade extra do foco |
| `FlashBurstBlindOpacity` | 0,82 | Opacidade maxima do branco |
| `FlashBurstSound` / `FlashBurstSoundVolume` | som embutido / 0,35 | Descarga espacial |
| `FlashBurstRingSound` / `FlashBurstRingVolume` / `FlashBurstRingPitch` | tom embutido / 0,12 / 3 | Zumbido privado |
| `Animations.Burst` | vazio | Clip R6 opcional publicado pelo dono/grupo |

As duracoes devem obedecer: blind > bloqueio >= stun > 0. O custo deve ficar
entre 0 e BatteryMax (exclusivo em zero). O modulo valida esses limites no boot.
Sem clip Burst, o recuo procedural funciona; Equip, Idle e Click continuam usando
os assets existentes. O zumbido padrao reaproveita um trecho em loop do tom
embutido, com pitch alto; um asset proprio pode substitui-lo nessa configuracao.

## Autoridade e estados

`FlashlightSystem` valida posse, Tool normalizada/equipada, papel, rodada,
vida, condicoes impeditivas, bateria, cooldown e sequencia monotona. O limitador
de pedidos atua antes dos raycasts. Origem, custo, duracoes e alvo nunca vem do
cliente. A direcao deve ser finita, aproximadamente unitaria e coerente com a
orientacao do personagem. O servidor nao conhece a camera real; valida uma
faixa de mira com tolerancia para a camera de ombro e replicacao.

`FlashlightTargeting` reutiliza a verificacao cabeca/lente para impedir uma
mao atravessando parede. O cone do disparo faz raycasts contra geometria solida,
com o proprio personagem excluido. Alcance e angulo opcionais preservam a
detecao da luz normal.

O servidor publica `FlashBurstAt`/`FlashBurstReadyAt` na Tool e cooldown tambem
no Player. Apenas o atirador recebe `BurstResult`. No alvo, publica
`FlashStunned`, `FlashPowerBlocked`, `FlashBurstAt` e `FlashBurstBlindUntil`.
O atributo `MonsterCombatState` permanece sob autoridade de `DamageSystem`.

O atordoamento reutiliza `SurvivorPowerStatus.Stun` com a fonte `FlashBurst`.
Esse gerenciador preserva velocidade, estado de salto e network ownership,
retira o movimento horizontal durante o stun e restaura o que possui ao sair.
Fontes de stun independentes possuem prazos independentes; limpar o clarão nao
remove um stun aplicado por outra habilidade.

Antes de capturar o estado, callbacks sincronos encerram F/Shadow Rush,
teleporte e agarrão pelos caminhos de cancelamento existentes. O apagao cancela
suas sessoes e uma conjuracao atrasada nao pode desligar as luzes depois disso.
Os cooldowns desses poderes nao sao devolvidos. Novas ativacoes de F, Q, E, R e
ataque verificam `FlashlightRules.PowerBlocked` tanto no cliente quanto no
servidor. Esse helper tambem e o ponto de integracao para futuros poderes.

Ha uma entrada por monstro. Outro acerto renova os prazos, sem empilhar GUIs,
sons ou multiplicadores. Morte, respawn, saida, fim da rodada e mudanca de
`MonsterCombatState` limpam o efeito do clarão. A tela e o zumbido leem apenas
os atributos do personagem local vivo com papel de monstro; o brilho corporal
e a descarga da Tool sao efeitos no mundo para observadores proximos.

## Arquivos alterados nesta integracao

Todos os caminhos abaixo sao relativos a raiz do projeto.

| Area | Arquivos |
| --- | --- |
| Configuracao/contrato | `src/ReplicatedStorage/Modules/FlashlightConfig.lua`, `FlashlightRules.lua`, `Remotes.lua` |
| Autoridade | `src/server/FlashlightSystem.lua`, `FlashlightTargeting.lua`, `SurvivorPowerStatus.lua` |
| Poderes do monstro | `src/server/ShadowRush.lua`, `MonsterTeleport.lua`, `GrabService.lua`, `MonsterCombat.lua`, `AbyssBlackout.lua` |
| Lanterna cliente | `src/client/FlashlightController.client.luau`, `FlashlightPose.lua`, `FlashlightVisuals.lua`, `FlashlightHUD.lua`, `FlashlightExposureFX.lua` |
| Entradas do monstro | `src/client/ShadowRushController.client.luau`, `MonsterTeleportController.client.luau`, `GrabController.client.luau`, `MonsterController.client.luau`, `AbyssBlackoutController.client.luau` |
| Testes servidor | `tests/run_flashlight_tests.rb`, `flashlight.luau`, `flashlight_burst.luau`, `run_flash_burst_powers.py`, `flash_burst_powers.luau` |
| Testes cliente/regressoes | `tests/run_flashlight_presentation.py`, `flashlight_presentation.luau`, `run_abyss_blackout.py`, `abyss_blackout.luau`, `run_shadow_presentation.py`, `shadow_presentation.luau` |
| Auditoria/documentacao | `tests/check_flashlight_build.py`, `docs/FlashBurst.md`, `docs/Lanterna.md` |

## Verificacoes automatizadas

```sh
ruby tests/run_flashlight_tests.rb
python3 tests/run_flashlight_presentation.py
python3 tests/run_flash_burst_powers.py
python3 tests/run_survivor_powers.py
python3 tests/run_abyss_blackout.py
python3 tests/run_shadow_presentation.py /caminho/para/luau
rojo build default.project.json -o /tmp/meujogo-flash-burst.rbxlx
python3 tests/check_flashlight_build.py /tmp/meujogo-flash-burst.rbxlx
```

Os testes executam os modulos reais com jogadores/servicos simulados. Cobrem
bateria vazia, cooldown, spam de 1000 pedidos, repeticao de sequencia, troca de
Tool, paredes, mira falsa, origem distante, condicoes impeditivas, imunidade,
limpeza e restauracao, fontes de stun simultaneas, F/teleporte/agarrão/ataque/R,
efeitos privados e ausencia de duplicacao. A suite anterior de poderes continua
validando o comportamento dos stuns normais.

A auditoria do build exige exatamente um controlador, um servidor, cada modulo
da lanterna e um RemoteEvent Flashlight. O pacote Arczis ainda contem seus scripts
de autoria em ServerStorage, onde ficam inertes; `ToolFactory.sanitizeTool`
remove esses scripts quando cria a Tool de jogo.

## Playtest real com dois clientes — pendente

Nesta sessao nao houve acesso ao controle do Roblox Studio. Build, compilacao
e testes com servicos simulados nao equivalem a validar rede, renderizacao,
audio e animacoes em dois clientes reais.

1. No Studio, abrir/sincronizar o projeto e iniciar um servidor local com **2
   clientes**. Iniciar uma rodada pelo fluxo normal: um Sobrevivente e um Monstro.
   Pegar a lanterna no mapa e equipa-la no sobrevivente.
2. Ficar a 10–15 studs, sem obstaculos. Apontar ao torso do monstro e apertar V.
   Confirmar queda de 25 pontos de bateria, flash, recuo, som e ACERTOU no
   sobrevivente. No monstro: parada de 2s, branco/zumbido por 4s. O sobrevivente
   nao deve receber o branco nem o zumbido (a descarga espacial e audivel).
3. No monstro, tentar F, Q, E, R e ataque durante os 2,5s. Todos devem ser
   recusados. Depois, repetir e confirmar o funcionamento quando o cooldown
   proprio do poder permitir. Acertar durante F/agarrão/teleporte e conferir
   cancelamento e retorno correto de movimento, visibilidade e controle.
4. Apertar V varias vezes durante os 8s; nao deve gastar novamente. Trocar de
   slot/lanterna e repetir. Esgotar com quatro disparos (com luz normal apagada)
   e confirmar BATERIA INSUFICIENTE. Com luz ligada, conferir que os quatro
   disparos nao a apagam e que ela continua disponivel em 0% de carga.
5. Com monstro perto, mirar ao lado e disparar: SEM ACERTO com consumo. Colocar
   uma parede solida entre os dois: mesmo resultado, sem stun/branco. Levar o
   monstro para mais de 32 studs: SEM ACERTO com consumo. Mirar no sobrevivente
   nunca deve aplicar stun ou ofuscamento nele.
6. Desequipar, morrer, entrar em lobby ou ficar sob Apagao/GrabLocked/etc.:
   nenhum disparo deve ser aceito. Morrer/trocar personagem/sair durante o
   ofuscamento deve remover branco, zumbido e bloqueios.
7. Para testar renovacao sem aguardar 8s, temporariamente reduzir o cooldown
   em FlashlightConfig para 1s; acertar novamente antes dos 4s e conferir apenas
   um efeito de tela e um zumbido. Restaurar o cooldown para 8 depois.
8. Repetir com controle e com emulacao mobile: L2 e o botao Clarao devem
   disparar; R2/ativacao normal continua ligando/desligando. Conferir que o
   botao e o cooldown nao cobrem os controles de movimento.

Para dar carga durante o teste, usar no Command Bar do **servidor** o nome
real do sobrevivente, mantendo a mesma API autoritativa:

```lua
local p = game.Players:FindFirstChild("NOME_DO_SOBREVIVENTE")
local tool = p and p.Character and p.Character:FindFirstChildOfClass("Tool")
if tool and tool:GetAttribute("Lanterna") then
    require(game.ServerScriptService.Server.FlashlightSystem).Recharge(tool, 100)
end
```

Para testar mudanca de estado no alvo durante o efeito, usar a API existente
`DamageSystem.SetMonsterState(monster.Character, "Vulneravel")` no servidor.
Confirmar que os atributos do clarão somem sem sobrescrever esse novo estado.
