# CameraWeapon — câmera de ombro + armas em terceira pessoa

> Histórico: este controlador foi removido. A integração atual, somente da
> pistola, está em [PistolaOTS.md](PistolaOTS.md). Não siga os passos de instalação abaixo.

Sistema unificado nascido da fusão de dois módulos que estavam na pasta do jogo:

| Origem | O que foi aproveitado | O que foi descartado |
|---|---|---|
| **ShiftUnlocked-main** (câmera) | núcleo matemático: yaw/pitch → offset → foco, velocity offset (câmera atrasa no movimento), correção de colisão por eixo com reversão gradual, popper de 4 cantos do viewport, transparência do personagem perto, curva-S do gamepad, shake (Sleitnick) | dependências Wally `janitor` e `smartraycast` (**não estavam no repo** — o módulo original nem rodaria); zoom livre por roda; ícone de mouse customizado |
| **Sistema de armas** (`Digital's OTS Patch2.rbxm`) | as 9 Tools com meshes, 18 animações, sons, efeitos de impacto/tracer, HUD `Weapon`; a lógica do `Framework` (equipar, mirar, ombro, tiro, recarga por markers, laser, lanterna), `LookController`, `CrosshairService`, `ServerHandler` | o `PlayerModule` inteiro (era o **stock do Roblox**, sem nenhuma modificação — a "câmera OTS" era shift-lock + tween em `Humanoid.CameraOffset` + `BodyGyro`); 8 `RenderStepped` separados; `Mouse.Hit` como direção de tiro |

Nenhum dos dois roda mais por conta própria. Um controlador central orquestra tudo num **único** `BindToRenderStep`.

## Estrutura de pastas

```
src/client/CameraWeapon/            -> StarterPlayerScripts/Client/CameraWeapon (LocalScript + módulos filhos)
  init.client.luau                  controlador central: loop único, máquina de estados, wiring
  Config.lua                        TODOS os parâmetros (câmera por estado, springs, recoil, input, HUD, efeitos)
  Springs.lua                       spring analítico genérico (number/Vector2/Vector3) + ConstrainedSpring
  CameraShake.lua                   instâncias Sleitnick + presets + trauma-based; sem loop próprio
  CameraCore.lua                    port do ShiftUnlocked, dirigido por alvos (offset/zoom/FOV) suavizados
  CameraStates.lua                  Idle / Sprint / WeaponReady / Aiming + sway/bob procedural
  InputController.lua               ContextActionService (mouse+teclado e gamepad), curva-S, roda, Alt livre
  RecoilSystem.lua                  recuo câmera+arma sincronizado (springs), fração permanente
  LookController.lua                cabeça/ombros seguem a câmera (R6 e R15), suavização exponencial
  WeaponConfig.lua                  lê Settings/Components da Tool + Attributes de override
  WeaponController.lua              equipar/mirar/atirar/recarregar/laser/lanterna/locomoção armada
  WeaponHUD.lua                     crosshair dinâmico, vinheta de mira, hitmarkers, kill feed
  CameraEffects.lua                 motion blur no sprint, vinheta/dessaturação ao levar dano

src/ReplicatedStorage/Modules/WeaponEffects.lua   tracer + impacto (criados no servidor, replicam)
src/ReplicatedStorage/Remotes/Firearm{Shoot,Hit,Damage,Reload,Feed}.model.json
src/ReplicatedStorage/WeaponAssets/               fatiado do .rbxm em .rbxmx (Rojo sincroniza sozinho)
  Tools.rbxmx        9 armas (AKS_74U, AKS_74U MOD, AK_101, Glock17, M4A1, M4A1 MOD, MP5, Scar_L, Spas_12)
  Animations.rbxmx   CharacterAnimations + Rifle/Pistol/ShotgunAnimations
  Audios.rbxmx       tiros, AimIn/AimOut, impactos por material, passos, HUD
  Effects.rbxmx      Tracers (Start/End/MissIndicator) e ImpactEffects por material
src/StarterGui/Weapon.rbxmx                       HUD da arma (Crosshair, Vignette, hitmarkers, feed)
src/server/FirearmServer.lua                      munição, dano, armadura, recarga, kill -> Elimination
default.project.json                              + ReplicatedStorage.WeaponAssets, + Workspace.System/{Tracers,Impacts,Misc}
```

Removido: `src/client/SprintController.client.luau` (o Shift agora é estado do controlador; velocidades continuam em `GameConfig.Movement`, com `AimSpeed` novo).

## Máquina de estados

| Estado | Entra quando | Câmera (Config.Camera.States) | Personagem |
|---|---|---|---|
| **Idle** | padrão | offset 1.6/1.45, zoom 8, FOV 70, respiração leve | `AutoRotate` normal |
| **Sprint** | Shift + se movendo | zoom 9.5, FOV 76, bob + shake sustentado, motion blur | `AutoRotate` normal |
| **WeaponReady** | arma de fogo equipada | offset 1.9 (ombro), zoom 5.5, FOV 68 | gira com a câmera, cabeça segue |
| **Aiming** | arma + botão direito | offset 2.15, zoom 3.4, **FOV 55** (ou `AimFOV` da arma), sensibilidade 55%, suavização de olhar | gira com a câmera, cabeça+ombros seguem |

Prioridade: Aiming > Sprint > WeaponReady > Idle. Começar a correr sai da mira (`AimBlocksSprint`); recarregar sai da mira (`ReloadCancelsAim`). Todas as transições são springs críticos com `TransitionTime` de 0.15–0.28 s.

## Ordem do frame (prioridade `Camera - 1`)

1. `InputController:Update` — gamepad → delta; mouse já acumulado por evento
2. `CameraStates:Evaluate/Set` — dispara `Changed` (reconfigura alvos, sensibilidade, WalkSpeed, efeitos)
3. `RecoilSystem:Update` — springs de câmera e arma; fração permanente vai pro pitch base
4. `CameraCore:Update` — foco, velocity offset, sway/bob, shake, colisão por eixo, popper, FOV
5. `LookController:Update` — pescoço/ombros
6. `WeaponController:Update` — locomoção armada, auto-fire, cano bloqueado, laser
7. `WeaponHUD:Update`, `CameraEffects:Update`

## Controles

| Ação | Mouse/teclado | Gamepad |
|---|---|---|
| Mirar (segurar) | botão direito | L2 |
| Atirar | botão esquerdo | R2 |
| Correr | Shift | L3 |
| Recarregar | R | X |
| Sacar/guardar | H | Y |
| Trocar ombro | Q ou roda do mouse | R3 |
| Laser / Lanterna | Z / T | D-pad baixo / cima |
| Liberar cursor (UI) | segurar Alt esquerdo | — |

Sem arma equipada, botão esquerdo/direito **passam** (Pass) — as Tools brancas do jogo (Faca, Lança, Pedra) e a UI continuam funcionando.

## Config por arma

Fonte principal: a estrutura que as Tools do OTS já têm (`Weapon` BoolValue, `Settings/Config/*`, `Settings/Damage/*`, `Components/*`). Nada mudou nelas. Overrides opcionais por **Attribute** na Tool:

`Firearm` (bool, alternativa ao BoolValue) · `AnimationSet` ("Rifle"/"Pistol"/"Shotgun") · `AimFOV` · `AimZoom` · `CameraOffset` (Vector3) · `RecoilPitchScale` · `RecoilYawScale` · `WeaponKickScale` · `SpreadDegrees` · `SoundName`

## Instalar e testar no Studio

1. `rojo serve` conectado (ou `rojo build` + reabrir). Confira no Explorer: `ReplicatedStorage.WeaponAssets` com 4 pastas, `StarterGui.Weapon`, `StarterPlayerScripts.Client.CameraWeapon`.
2. `GameConfig.Testing.GiveTestWeapons = { "M4A1", "Glock17" }` já está ligado: ao dar Play você recebe as duas no Backpack.
3. Play → tecla `1` (ou `H`) saca a M4A1 → câmera vai pra WeaponReady → botão direito mira (FOV cai, ombro cola) → botão esquerdo atira → `R` recarrega → `Q` troca ombro → Shift corre (sai da mira).
4. Output deve mostrar `[Boot] Servidor de Náufragos pronto.` sem `FirearmServer.Init() falhou`.

**Rig:** as animações e a detecção de partes do OTS foram feitas pensando em **R6** (`Torso`, `Right Arm`). O código suporta R15 (LookController, hit detection), mas se as animações ficarem tortas em R15, force R6 em Game Settings → Avatar.

## Pontos de ajuste fino (Config.lua)

- **Feel geral:** `Camera.States.*.Offset/Zoom/FOV/TransitionTime`, `Camera.States.Aiming.Sensitivity`, `Input.AimLookSmoothing`
- **Ombro:** `Camera.DefaultShoulder`, `Input.ScrollSwapsShoulder` (false = roda volta a ser zoom)
- **Peso do movimento:** `Camera.VelocityOffset.Frequency/Damping/VelocityThreshold`
- **Respiração/bob:** `Camera.IdleSway.*`, `Camera.SprintBob.*`, `Camera.SprintShake.*`
- **Recuo:** `Recoil.Camera.PitchDegreesPerUnit`, `YawDegreesJitterPerUnit`, `Frequency/Damping` (< 1 = overshoot), `PermanentPitchFraction`; `Recoil.Weapon.*` (o grip); `Recoil.FireShake.*`
- **Colisão:** `Camera.Collision.ObstructionRange`, `TimeUntilReversion`, `ReversionSpeed`
- **Tiro:** `Weapon.RequireAimToFire`, `HipFireSpreadMultiplier`, `SpreadDegreesPerUnit`, `MuzzleBlockDistance`
- **Animações:** `Weapon.Animation.FadeIn/AimFadeIn/FireFadeIn` e as prioridades
- **Efeitos:** `Effects.MotionBlur.MaxSize`, `Effects.Damage.*` (ou `Enabled = false`)
- **HUD:** `HUD.CrosshairBaseRadius`, `CrosshairSpring`, `AimVignetteTransparency`
- **Movimento:** `GameConfig.Movement.WalkSpeed/SprintSpeed/AimSpeed`
- **Por arma:** `Settings/Config/{AimFOV,Recoil,Spread,Delay,Auto,CrosshairShove}` na Tool, ou os Attributes acima

## Limitações conhecidas

- Hitscan é calculado no cliente (como no OTS) — o servidor valida arma equipada, cadência, alcance e alvo, mas não refaz o raycast.
- Não existe aberração cromática nativa no Roblox; o efeito de dano usa tint + dessaturação + vinheta.
- Touch não foi implementado (pedido era mouse+teclado e gamepad).
- Os 4 ImageLabels do crosshair do OTS usam a imagem placeholder do Roblox (`GuiImagePlaceholder.png`) — troque as imagens em `StarterGui/Weapon/Crosshair`.
- Recarga sem marker `End` na animação fecha ao terminar a track (fallback).
