# Monster Animation Rig

O template canônico está em `ReplicatedStorage/MonsterAnimationRig`. Ele é a
mesma fonte serializada de `Workspace/R6 Monster` e coincide com o
`StarterCharacter` real após `AppearanceManager` aplicar `Model:ScaleTo(1.2)`:
não é um R6 novo aumentado por `Size`. Os offsets de Motor6D preservados são
os do Monster real. O `Animator` dentro do `Humanoid` permite reprodução e o
uso pelo Animation Editor.

## Auditoria da estrutura atual

- Tipo: R6 (`Humanoid.RigType = R6`), com `Humanoid` e `Animator`; não usa
  `AnimationController`.
- `PrimaryPart`: `HumanoidRootPart`.
- Escala do modelo: `1.2`.
- Hierarquia de movimento: `HumanoidRootPart > RootJoint > Torso`; no `Torso`
  ficam `Neck`, `Right Shoulder`, `Left Shoulder`, `Right Hip` e `Left Hip`.
- Partes R6 (todas filhas do Model): `HumanoidRootPart`, `Torso`, `Head`,
  `Right Arm`, `Left Arm`, `Right Leg`, `Left Leg`.

Os CFrames abaixo estão no formato `(X, Y, Z; R00,R01,R02 / R10,R11,R12 /
R20,R21,R22)`. São valores auditados; não devem ser ajustados manualmente.

| Motor6D | Part0 → Part1 | C0 | C1 |
| --- | --- | --- | --- |
| RootJoint | HumanoidRootPart → Torso | `(0,0,0; -1,0,0 / 0,0,1 / 0,1,0)` | igual a C0 |
| Neck | Torso → Head | `(0,1.2,0; -1,0,0 / 0,0,1 / 0,1,0)` | `(0,-0.6,0; -1,0,0 / 0,-.01348186,.999909103 / 0,.999909103,.01348186)` |
| Right Shoulder | Torso → Right Arm | `(1.2,.6,0; 0,0,1 / 0,1,0 / -1,0,0)` | `(-.6,.6,0; 0,0,1 / 0,1,0 / -1,0,0)` |
| Left Shoulder | Torso → Left Arm | `(-1.2,.6,0; 0,0,-1 / 0,1,0 / 1,0,0)` | `(.6,.711124277,-.0149012737; 0,0,-1 / .132905796,.991128683,0 / .991128683,-.132905796,0)` |
| Right Hip | Torso → Right Leg | `(1.2,-1.2,0; 0,0,1 / 0,1,0 / -1,0,0)` | `(.6,1.2,0; 0,0,1 / 0,1,0 / -1,0,0)` |
| Left Hip | Torso → Left Leg | `(-1.2,-1.2,0; 0,0,-1 / 0,1,0 / 1,0,0)` | `(-.6,1.2,0; 0,0,-1 / 0,1,0 / 1,0,0)` |

## Criar e publicar uma animação

1. Em modo de edição, execute
   `tools/create_monster_animation_rig_once.server.luau` na Command Bar.
   Ele cria `Workspace/Monster Animation Rig (Authoring)` sem substituir nada.
2. Selecione essa cópia e abra **Plugins > Animation Editor**. Crie a animação
   no próprio rig, não em `R6 novo` e não em R15.
3. Publique pelo Animation Editor usando o mesmo dono/grupo da experiência.
4. Cole o `rbxassetid://...` publicado em
   `ReplicatedStorage/Modules/MonsterAnimationConfig.lua`, no campo correto de
   `AnimationIds`: `Idle`, `Walk`, `Run`, `Attack`, `Damage` ou `Death`.

`Idle`, `Walk` e `Run` assumem a locomoção real apenas quando os três IDs foram
preenchidos. `Attack` é acionado pelo golpe; `Damage` e `Death` são acionados
no `DamageSystem`. IDs vazios não têm fallback para assets R15 ou para o antigo
slash padrão.

## Preview por plugin do Studio

O preview não é mais uma UI do jogo e não aparece no Play. O plugin é gerado
por `tools/MonsterAnimationPreview.project.json` e instalado na pasta de
plugins locais do Studio. O botão **Monster Preview**, na toolbar **Monster
Animation**, abre ou fecha o painel. Ele permite selecionar
Idle/Walk/Run/Attack/Damage/Death, informar o ID, criar o rig de autoria no
Workspace, criar o clone de preview, tocar, pausar, reiniciar e limpar.
Ao limpar ou descarregar o plugin, o clone e a câmera de preview são removidos.
Fechar o painel pelo botão da toolbar também limpa o preview.

## Validação automática

`server/MonsterAnimationRigValidation.lua` compara o template ao Monster real
depois de `AppearanceManager` aplicar a escala 1.2x. Ele verifica Humanoid R6,
Animator, partes obrigatórias sem duplicatas, seis Motor6D, nomes, Part0/Part1,
C0, C1, tamanhos, `PrimaryPart` e `RootJoint`. O Output mostra
`[MonsterAnimationRig] Validado` somente quando a assinatura é idêntica.

O antigo `fix_monster_animation_rig_pose_once.server.luau` foi convertido em
proteção: ele não altera mais C0/C1. Caso a cópia de autoria tenha sido editada
ou danificada, apague somente essa cópia e recrie-a pelo script de autoria.
