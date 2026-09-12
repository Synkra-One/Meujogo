# Sistema de movimento (Ultimate R6 Movement System)

Substituiu o sistema de câmera/arma OTS (`src/client/CameraWeapon`, removido).
A doc antiga daquele sistema está em `docs/CameraWeapon.md` só como histórico.

## Origem

`Animations/Ultimate R6 Movement System.rbxm` (by Arczi). É um `.rbxm` binário
que cobre 6 serviços diferentes, então **não dá** pra apontar um `$path` só
pra ele. O que foi feito:

1. `rojo build` do pacote gera um `.rbxlx`, que é **XML**.
2. Um script fatiou esse XML em um `.rbxmx` por instância, em `src/MovementPack/`.
3. `default.project.json` monta cada arquivo no serviço certo.

O `.rbxm` original continua em `Animations/` — é de lá que sai o **Dummy com
os AnimSaves** (8 MB de Keyframes), que ficou **fora do build** de propósito:
só serve pra reabrir as animações no Animation Editor. Arraste o `.rbxm` pro
Studio quando precisar editar.

## NÃO importe o `.rbxm` na mão

O tutorial do pacote manda arrastar o `.rbxm` pro Studio e dar
`Ungroup` na pasta `Ultimate R6 Movement System by Arczi` pra espalhar o
conteúdo pelos serviços. **Aqui isso já foi feito no `default.project.json`** —
cada arquivo de `src/MovementPack/` é montado DIRETO no serviço certo
(`rojo build` prova: nenhuma pasta-invólucro no lugar errado).

Se você importar o `.rbxm` na mão E rodar o `rojo serve`, vai ficar com
**tudo em dobro** (dois `PlayerModule`, dois `Animate`, dois de cada script) —
e isso quebra o movimento. Se você já fez isso e salvou o `Meujogo.rbxlx`:

1. No Explorer, apague a pasta `Ultimate R6 Movement System by Arczi`
   (e qualquer duplicata solta que ela tenha deixado nos serviços).
2. `rojo build -o "Meujogo.rbxlx"` de novo, abre esse arquivo, `rojo serve`.

O `.rbxm` só serve pra **uma coisa**: abrir num Studio à parte pra pegar as
animações do Dummy (`Anims R6`) e republicar na sua conta — ver o fim deste
arquivo.

## Onde cada coisa foi parar

| Serviço | Vindo do pacote |
|---|---|
| `ReplicatedStorage` | `RayPart`, `ViewModel`, `idk`, `UpdateRunningState`, `FallDamageEvent`, `CameraShaker`, `CameraShakeCall`, `FallSystem` |
| `ReplicatedStorage.Modules` | `FootstepModule` (**mesclado** na pasta que já existia) |
| `ReplicatedStorage.Remotes` | os 19 remotes do pacote (**mesclados** na pasta que já existia) |
| `ServerScriptService` | `R6Ragdoll`, `NoCollision`, `DisableDefaultShiftLock`, `DeathRespawnHandler` |
| `StarterGui` | `Vignette`, `Ui` (barra de vida pixel-art), `Bobbing Camera` |
| `StarterPlayer.StarterCharacterScripts` | `Animate`, `Crouching`, `CustomShiftLock`, `FallSystem`, `Turning` |
| `StarterPlayer.StarterPlayerScripts` | `PlayerModule`, `StaminaSystem`, `RbxCharacterSounds`, `IK`, `Footsteps`, `DeathScreenUI`, `DamageScreen` |
| `SoundService` | `Main` (SoundGroups), `FallSounds` |

### Colisões de nome que precisaram de cuidado

- **`Modules`** — o pacote tem uma pasta com esse nome. Como `default.project.json`
  é JSON, duas chaves `"Modules"` fariam a segunda **apagar** a primeira, e o
  jogo perderia `GameConfig`/`Remotes`/`ItemRegistry`/etc. O `FootstepModule`
  foi extraído pra dentro de `src/ReplicatedStorage/Modules/`.
- **`Remotes`** — mesma coisa. Os 19 remotes do pacote viraram arquivos soltos
  em `src/ReplicatedStorage/Remotes/`, então o path `ReplicatedStorage.Remotes.X`
  que os scripts dele esperam continua valendo.

## Bug do "boneco travado" (corrigido)

Sintoma: no spawn, o boneco anima e se inclina pra frente mas **não anda**.

Causa: o `FallSystem` do pacote, ao pousar, fazia `Humanoid.WalkSpeed = 0`,
tocava uma animação de pouso (ID **privado do autor** → `:Play()` dá "not
authorized") e um efeito de poeira, e **só depois** de um `task.wait`
restaurava `WalkSpeed = 16`. O handler não tinha `pcall`: qualquer erro no
meio estourava antes da linha que devolve a velocidade → WalkSpeed 0 pra
sempre. E disparava logo no primeiro pouso (o assentamento do spawn).

Correções:
- `src/MovementPack/StarterCharacterScripts/FallSystem.rbxmx` **removido**.
- `src/client/FallEffects.client.luau` — reescrita: mesmas 3 faixas de queda,
  som, poeira, shake e `FallDamageEvent`, mas **nunca zera WalkSpeed** (a
  cambaleada da queda longa é uma lentidão que se cura sozinha com teto de
  tempo), tudo em `pcall`, e **ignora a queda do spawn**.
- `src/client/MovementWatchdog.client.luau` — rede de segurança: se o
  WalkSpeed ficar ~0 por >1,5s (ou >5s numa transição de rastejar) **sem
  motivo** (não está amarrado/eliminado/morto/sentado), devolve a velocidade
  padrão e avisa no Output. Respeita as paradas propositais do jogo.

Se o boneco travar de novo, o Output vai dizer qual script deixou o WalkSpeed
em 0 — quase sempre é **ID de animação privado que não carregou**.

## O que foi deixado de fora, e por quê

- **`TrueHealthController`** — não é um script inteiro: o Source dele começa
  com `-- Add near the top of TrueHealthController...`, é um **trecho** pra
  colar em outro lugar. Ele só trata `FallDamageEvent` chamando
  `humanoid:TakeDamage` direto, o que furaria as guardas do `DamageSystem`
  (invulnerável / já eliminado / ForceField). O dano de queda foi reimplementado
  em `DamageSystem.Init()` com o mesmo cálculo (`4` studs de graça, `1.5` de
  dano por stud) e a mesma validação anti-cheat (o cliente manda a distância,
  nunca o dano).
- **`Anims R6`** (Dummy + AnimSaves) — 8 MB de dado de editor, inútil em
  runtime. Fica só no `.rbxm`.

## Conflito resolvido: respawn x eliminação

`DeathRespawnHandler` põe `Players.CharacterAutoLoads = false` e dá
`player:LoadCharacter()` ~5s depois de `Humanoid.Died`.

O jogo é de **eliminação** (`RoundManager` conta vivos por
`Elimination.IsEliminated`). Se a marca de eliminado vivesse só no character,
o respawn traria um character novo sem a marca e **a rodada nunca terminaria**.

Solução (sem editar código de terceiros): `Elimination.Eliminate` marca o
Attribute `Eliminado` **no Player** também, e `IsEliminated` checa os dois.
Resultado: você renasce (o feel do pacote), mas continua fora da rodada.
`RoundManager.prepareRound` chama `Elimination.Reset(player)` no começo de
cada partida pra limpar.

## Rig: precisa ser R6

O pacote inteiro é R6 (`Animate` lê `Torso`/`Left Leg`, o ragdoll tem
`assert(RigType == R6)`). As animações da pistola do OTS também foram feitas
pra R6 — então bate.

**Isso não dá pra setar por Rojo.** No Studio:
`Game Settings → Avatar → Avatar Type → R6`.

Se ficar em R15: `Animate` e `Turning` travam pra sempre num
`WaitForChild("Torso")` (parte que só existe em R6) — o boneco nasce e não
anima nada.

### Atalho secreto de teste do rig

Para testar o boneco R6 salvo no Explorer, deixe o Model chamado exatamente
`R6 novo` dentro do `Workspace`, com `Humanoid` e `HumanoidRootPart`. No Play,
o UserId `11555748600` pode apertar `M`: o servidor clona esse rig e troca o
Character do jogador por ele. O atalho e o RemoteEvent existem só para teste
e ignoram qualquer outro UserId.

## Animações — IDs em uso

Tudo nos **defaults R6 da Roblox** (públicos, garantido que carregam). O
usuário fez `walk` e `run` próprias — quando publicar e passar os IDs, é só
trocar essas duas linhas em `Animate.rbxmx`.

| Arquivo | Anim | ID | Origem |
|---|---|---|---|
| `Animate.rbxmx` (tabela `animNames` no código) | idle | `109143561038911` | **animação do usuário** |
| | walk | `84329977047483` | **animação do usuário** |
| | run | `87202665361349` | **animação do usuário** |
| | jump | `125750702` | Roblox R6 |
| | fall | `180436148` | Roblox R6 |
| | climb | `180436334` | Roblox R6 |
| | sit | `178130996` | Roblox R6 |
| `Crouching.rbxmx` (6 objetos `Animation`) | Crouching | `125164434023167` | crouch idle indicado pelo usuário |
| | CrouchWalk | `80429715000556` | crouch andando indicado pelo usuário |
| | CrouchToCrawl / CrawlIdle / CrawlWalk / CrawlToCrouch | vazio | opcional; o script procura aliases como `CrouchIdle`, `Agachar`, `AndarAgachado`, `RastejarIdle` |
| `src/client/FallEffects.client.luau` | FALL_ANIM_LONG / SHORT | `180436148` | Roblox R6 (mesma do fall) |
| | FALL_ANIM_LAND | vazio | pouso normal só volta pro idle |

`Animate` lê do **código** (tabela `animNames`). `Crouching` prefere objetos
`Animation` preenchidos no Explorer e cai nos IDs de fallback só quando não
encontra uma animação customizada.

### Publicar uma animação da AnimSaves

O que fica em `Dummy > AnimSaves` é dado cru de editor (`KeyframeSequence`) —
o jogo NÃO usa direto. Precisa publicar:

1. Botão direito no Dummy → **Animation Editor**
2. Abre a animação salva (walk / run)
3. Menu **⋯** (canto superior esquerdo) → **Publish to Roblox…**
4. Preenche nome → Submit → copia o **Asset ID**

Aí é só pôr `rbxassetid://<ID>` nas linhas `walk` / `run` da tabela `animNames`
em `src/MovementPack/StarterCharacterScripts/Animate.rbxmx`.

## Câmera de ombro (3ª pessoa colada)

O `CameraWeapon` (OTS) foi removido porque brigava com o `PlayerModule` do
pacote pelo CFrame do Camera. Em vez de trazer ele de volta, a câmera de ombro
agora vem do **próprio pacote**: `CustomShiftLock > SmoothShiftLock`, que já
fazia isso mas vinha **desligado** e preso no LeftControl.

Mudanças:
- `SmoothShiftLock` agora **liga sozinho** no primeiro spawn e **religa no
  respawn** (o original forçava desligado toda vez que o character nascia).
- `LOCKED_CAMERA_OFFSET` `1.75, 0.25` → **`2.25, 0.35`** (ombro mais marcado).
- `default.project.json` → `StarterPlayer.CameraMinZoomDistance = 6` /
  `CameraMaxZoomDistance = 9`: prende a câmera perto do personagem (é isso que
  dá o "colado", o offset sozinho só desloca pro lado).

**LeftControl continua alternando.** Desligar solta o mouse do centro — é
assim que dá pra clicar na hotbar. Com ela ligada o cursor fica travado no
meio da tela, o que também faz o `PistolController` mirar exatamente no centro
(`GetMouseLocation` devolve o centro quando `MouseBehavior = LockCenter`).

## Números de corrida / fôlego (ajustados)

| Onde | Valor | Antes | Efeito |
|---|---|---|---|
| `Crouching.rbxmx` CONFIG.SprintSpeed | **23** | 27 | corrida um pouco mais lenta (andar = 12, limiar de sprint = 20) |
| `StaminaSystem.rbxmx` CONFIG.MaxStamina | **140** | 100 | pool de fôlego maior |
| `StaminaSystem.rbxmx` CONFIG.DrainRate | **16** | 22 | ~8,7s de corrida cheia (era ~4,5s) |
| `StaminaSystem.rbxmx` CONFIG.RegenRate | **16** | 14 | recupera um pouco mais rápido |
| `StaminaSystem.rbxmx` CONFIG.MinStaminaSprint | **20** | 15 | mesmo ~14% do pool pra voltar a correr |

`SprintSpeed` tem que ficar **acima de 20** (`SprintSpeedThreshold` em
StaminaSystem, `SPRINT_SPEED_THRESHOLD` em Animate/Turning) — é o que detecta
"está correndo" pra drenar fôlego, tocar a animação de run, a fumaça e a
inclinação do corpo.

## Fumaça ao começar a correr

O pacote já tinha o efeito (`Animate > SprintImpact`, um Attachment com 4
ParticleEmitters) mas ele quase não aparecia por causa de um bug: o código
fazia `FindFirstChildWhichIsA("ParticleEmitter2")` — só que `ParticleEmitter2`
é o **nome** do emissor, não um ClassName. Os 3 últimos vinham `nil` e só um
dos quatro disparava.

Corrigido em `Animate.rbxmx`:
- junta todos os `ParticleEmitter` por `IsA` numa lista (`sprintEmitters`)
- Attachment movido pra **atrás do pé**: `FOOT_OFFSET + Vector3.new(0, 0, 1.2)`
  (em R6 o LookVector da HumanoidRootPart é `-Z`, então `+Z` são as costas)
- `Emit(20)`/`Emit(60)` → **`Emit(8)`** nos dois pontos de disparo, via
  `emitSprintDust()` — baforada curta, não explosão

Dispara quando `WalkSpeed >= 20` (o `Crouching` põe 27 no sprint) e rearma
quando cai abaixo disso.

## Armas depois da troca

`src/client/CameraWeapon` (câmera de ombro, mira, recuo, HUD de arma) foi
removido porque brigava com o `PlayerModule` do pacote pelo CFrame da câmera.

O `PistolController.client.luau` agora integra somente a Glock17: clique atira,
botão direito mira, `R` recarrega. A HUD tem pente/reserva, progresso da recarga,
crosshair, recuo e hitmarker confirmado. O servidor calcula o tiro e controla
a recarga; as animações usam apenas `PistolAnimations`.

A câmera de ombro continua sendo o `CustomShiftLock`. O controlador da pistola
adiciona apenas recuo angular. `Crouching` continua dono do FOV e da velocidade:
o atributo local `Character.FirearmAiming` pede FOV de mira e bloqueia o sprint
enquanto se mira. Não há outro PlayerModule/Animate nem outro tween de FOV.

Instalação, bancada do lobby, limitações de assets e testes: [PistolaOTS.md](PistolaOTS.md).
