# Lanterna

O item `Lanterna` usa o modelo **117648733552528**, registrado em
`ItemRegistry.lua`. Continua entrando pelo loot e pelo inventario existentes.
O modelo foi carregado no Studio: possui a peca `Flashlight`, um `Bulb` com
SpotLights e um `Holder`. A montagem preserva o ponto e a direcao da luz do
`Bulb`, normaliza o comprimento para 1,8 studs e remove scripts embutidos pelo
`AssetLoader`. Todas as pecas ficam desancoradas, sem colisao e soldadas ao Handle.

## Controles

- Equipar pela hotbar existente.
- Clique/toque de uso da Tool ou `T`: alternar a luz.
- Controle: ativacao da Tool ou `Y`.
- Celular: botao com a miniatura da lanterna.

`F` continua reservado para interagir com os objetos do jogo. A luz acompanha
o centro da camera. O ajuste visual usa apenas `RightGrip`, restaurando seu
valor original ao desligar/desequipar, sem modificar as animacoes do corpo.

## Balanceamento

Todos os parametros ficam em `src/ReplicatedStorage/Modules/FlashlightConfig.lua`.

| Parametro | Inicial |
| --- | --- |
| BatteryMax | 100 |
| BatteryDrainRate | 100 / 60 por segundo |
| FlashlightRange | 36 studs |
| BeamAngle | 38 graus |
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
porcentagem para a HUD. So ha consumo enquanto ligada. Ao zerar, a luz apaga,
soa um aviso e a HUD mostra `BATERIA ESGOTADA`. Nao existe regeneracao passiva.
Trocar de item, largar, recolher ou trocar de dono nao recarrega a Tool.
Uma Tool nova comeca cheia. Desequipar, morrer, perder a funcao de sobrevivente,
ficar preso, encerrar a rodada ou deixar de enviar mira desliga a luz.

API de recarga para uso por outros sistemas do servidor:

```lua
local FlashlightSystem = require(game.ServerScriptService.Server.FlashlightSystem)
FlashlightSystem.Recharge(tool, 25)
```

A API limita a carga a 100 e nao religa automaticamente. Nenhum RemoteEvent
aceita pedidos de recarga do cliente. Nao foi acrescentado um novo consumivel.

## Multiplayer e Organizacao

- `FlashlightSystem`: posse, papel, bloqueios, bateria, ciclo de vida e exposicao.
- `FlashlightTargeting`: origem, alcance, cone e visibilidade por Raycast.
- `FlashlightRules`: regras deterministicas de bateria e exposicao.
- `FlashlightRig`: montagem do modelo e attachments da luz.
- `FlashlightController`: entrada, previsao local e reconciliacao com sequencia.
- `FlashlightVisuals`: luz com sombras, feixe e orientacao para cada observador.
- `FlashlightHUD`: indicador compacto acima da hotbar, com alertas de carga.
- `FlashlightExposureFX`: blur, cor e audio locais exclusivos do monstro.

O servidor aceita somente intencao de ligar/desligar e direcao unitario-finita.
Ele nunca recebe alvo, origem, dano ou bateria como autoridade do cliente.
Uma verificacao entre cabeca e emissor impede iluminar usando uma mao que
atravessou uma parede. Cada amostra de cabeca/torso precisa estar no cone e ter
o proprio monstro como primeiro obstaculo atingido. Outros objetos e jogadores
tambem podem bloquear a luz.

Ha uma unica exposicao, resistencia e janela de dano por monstro. Duas ou mais
lanternas nao multiplicam essas taxas. Dano/efeitos exigem rodada ativa e ambos
os jogadores na partida; invulnerabilidade e ForceField sao respeitados.

O servidor verifica a cada 0,1 segundo, sem Raycast nos callbacks dos remotes.
O cliente envia mira no maximo a 8 Hz e reduz envios quando ela nao muda.
HUD atualiza a 20 Hz; apresentacao e suavizada localmente. O servidor publica
somente atributos alterados. A lentidao usa `MonsterCombat.MonsterSpeedMul`,
que o pacote de movimento ja le, sem um segundo escritor de WalkSpeed.

As tochas e zonas seguras continuam no sistema `MonsterLightWeakness`.
A lanterna nao dispara mais o empurrao por proximidade desse sistema, nem
habilita por si so a finalizacao de lanca ancestral baseada em `IsWeakened`.

## Validacao

```sh
ruby tests/run_flashlight_tests.rb /caminho/para/luau
rojo build default.project.json -o /tmp/Meujogo-lanterna.rbxlx
```

A suite executa os modulos reais com servicos simulados: bateria, cone,
exposicao, resistencia, duas lanternas, paredes, origem adulterada, remotes
invalidos, limites de frequencia, lobby, drop, morte, recarga e teto de dano.
Compilacao Luau e build Rojo tambem foram verificados. O asset foi inspecionado
no Studio, mas a validacao visual em partida multiplayer e em celular ainda
precisa ser concluida no Studio.

Roteiro de playtest: dois sobreviventes apontando para um monstro, com uma
parede entre eles; alternar cobertura, conferir o dano e o pico, largar e
recolher a Tool, esgotar a carga e trocar de rodada. Conferir caminhada,
corrida, agachamento, mira vertical e layout em tela pequena.

Referencias das APIs: [SpotLight](https://create.roblox.com/docs/reference/engine/classes/SpotLight)
e [Attachment](https://create.roblox.com/docs/reference/engine/classes/Attachment).
