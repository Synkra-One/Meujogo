# Monstro — combate, velocidade e o sorteio de papel

## Sorteio de papel (`client/RoleRevealController`)

Tela cheia no começo de cada partida (1ª fase, "Queda"). Embaralha
"SOBREVIVENTE / MONSTRO / ESPIÃO" feito caça-níquel, desacelera (~2,6s) e trava
no papel real com flash + cor + som, depois mostra o objetivo em uma linha e
some sozinha (~7s no total). O movimento fica travado durante o sorteio
(`ControlModule:Disable()`, com rede de segurança de 12s).

Substituiu o `OnboardingController` + `OnboardingHUD` (era um cartão de texto
estático). Toda a UI é feita em código — os textos/cores por papel estão em
`ROLE_INFO` no topo do arquivo.

Dispara em `Remotes.RoundStateChanged` (1ª fase) e lê o Attribute `Role` do
jogador (que `RoleAssignment` sorteia e replica sozinho — nenhum remote novo).

## Onde o Monstro nasce

Já era assim: `LobbyManager.teleportToIsland` põe o Monstro no marcador
`MonstroSpawn` (Attribute `MonstroSpawn == true`), dentro de
`Workspace/Ilha/Caverna`, criado por `IslandGenerator.GenerateCave()`. Todo o
resto desembarca num ponto de praia achado por raycast.

**Se o Monstro nascer na praia junto com os outros:** a caverna não foi
gerada. Rode no Command Bar (modo de edição) e salve:
```lua
require(game.ServerScriptService.Server.Tools.IslandGenerator).Generate()
```

## Combate (`server/MonsterCombat` + `client/MonsterController`)

Botão esquerdo (ou R2 no controle) → golpe em cone à frente.

| Passo | Onde |
|---|---|
| input + anima o golpe + cooldown local | `MonsterController` (cliente) |
| `Remotes.MonsterAttack:FireServer()` | — |
| valida (é Monstro, vivo, partida ativa, não amarrado, cooldown) | `MonsterCombat` (servidor) |
| hitbox: cone `Range` / `ConeCos` à frente do HumanoidRootPart | servidor |
| dano por `DamageSystem.Apply(vítima, dano, {Cause="Monstro"})` | servidor |
| `FireClient(Monstro, "confirm", nºacertos)` → lunge + kick de câmera + som | cliente |
| `FireClient(vítima, "knockback", posDoMonstro)` → empurrão no cliente dela | cliente |

O cliente só **pede** o golpe. Alcance, cone, cooldown, dano e morte são todos
decididos no servidor. O knockback é aplicado no cliente da vítima porque a
física do character dela pertence a ela (velocity setada pelo servidor não
gruda).

**Alvos:** Sobreviventes **e** o Espião. O Monstro nunca é alvo dele mesmo.

### Números (`GameConfig.Monster`)

| Campo | Valor | O que faz |
|---|---|---|
| `SpeedMultiplier` | 1.16 | Monstro anda ~16% mais rápido (alcança quem foge) |
| `WeakenedSpeedMultiplier` | 0.7 | velocidade enquanto fraco pela luz |
| `Attack.Damage` | 34 | 3 golpes limpos matam (100 HP) |
| `Attack.Range` | 9 | alcance do golpe (studs) |
| `Attack.ConeCos` | 0.35 | ~69° de meio-ângulo — precisa **mirar** |
| `Attack.Cooldown` | 1.1 | segundos entre golpes |
| `Attack.Knockback` / `KnockbackUp` | 26 / 8 | empurrão na vítima |
| `Attack.LungeForce` | 20 | dash pra frente do Monstro ao golpear (0 = sem) |
| `Attack.WeakenedDamageMul` | 0.45 | golpe enfraquecido enquanto fraco pela luz |
| `Attack.MaxHitsPerSwing` | 3 | teto de vítimas por golpe |
| `SwingAnimationId` | `129967390` | tool slash R6 padrão (pública) — troque por uma sua |

### Velocidade — como o multiplicador chega no WalkSpeed

O script `Crouching` (pacote de movimento) é o dono do `WalkSpeed` e o reescreve
todo frame. `MonsterCombat` publica o Attribute `MonsterSpeedMul` no character
(num loop de 5 Hz), e o `Crouching` foi patchado pra multiplicar o WalkSpeed
por ele. Fora do Monstro o atributo não existe → multiplicador 1.

Isso também **conserta** a lentidão da fraqueza à luz, que antes o `Crouching`
sobrescrevia: agora `MonsterCombat` lê `MonsterLightWeakness.IsWeakened` e baixa
o multiplicador enquanto o Monstro está na luz.

## O que a morte dispara (já existia)

`DamageSystem` → `Humanoid.Health = 0` → `Humanoid.Died` → o pacote de
movimento mostra a tela de morte (`DeathScreenUI`) e respawna o jogador no
Lobby depois de ~4,5s. A marca `Eliminado` fica no Player, então ele volta como
espectador no Lobby até a partida acabar. Quando os Sobreviventes vivos chegam
a 0, `RoundManager` declara vitória do Monstro.
