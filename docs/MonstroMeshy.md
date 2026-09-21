# Monstro Meshy (Charred Hollow Figure)

Duas etapas, ambas sem alterar o rig do monstro:

1. **Rig de teste** (`Workspace/R6 Monster Meshy`): um R6 separado só para ver o
   modelo e validar juntas. Não é usado por nenhum script.
2. **Aparência no monstro atual** (seção abaixo): as MeshParts do Meshy vestidas
   sobre o R6 que o jogo já usa, sem criar outro rig.

## O que o FBX é (limitação)

`model/Meshy_AI_Charred_Hollow_Figure_0918193209_texture.fbx` é **uma única
malha estática**: 1 `Geometry`, 1 `Model`, 1 `Material`, **sem esqueleto, sem
skin, sem animação**. Além disso é uma superfície única e fechada (0 arestas de
borda, 1 casca) — as partes do corpo **não** são objetos separados no arquivo.

Ela não pode ser "deformada" como um R6. Mas o desenho já é um R6 blocado
(cabeça, torso, 2 braços, 2 pernas, separados por ranhuras), e um R6 é feito de
blocos **rígidos** ligados por Motor6D. Então a adaptação foi:

1. Cortar a malha nos vincos reais em 6 peças rígidas (sem mover nem deformar
   nenhum vértice; só rotação de 180° em Y e escala uniforme).
2. Tampar cada abertura de corte (leque de triângulos), para o interior não
   ficar visível quando um membro gira.
3. Montar o R6 com os **mesmos eixos de junta** do R6 padrão.

O que isso **não** dá: nada dobra (cotovelo, joelho, pescoço, torso); os
membros giram como blocos, igual a qualquer R6 de Roblox.

Cortes (coordenadas originais do FBX, ver `tools/build_meshy_monster.py`):

| Junta | Plano |
| --- | --- |
| cabeça / torso | `y = 0.566` (os dentes da boca que pendem sobre o peito, 50 quads, ficam na cabeça) |
| braço / torso | `\|x\| = 0.368` |
| torso / pernas | `y = -0.104` |
| perna E / perna D | `x = 0` |

Cada peça resultante é uma única casca conectada e fechada (verificado).

## Arquivos gerados

| Arquivo | Para quê |
| --- | --- |
| `model/roblox_upload/parts/*.obj` | as 6 malhas (Head, Torso, LeftArm, RightArm, LeftLeg, RightLeg), em studs, já olhando para −Z, centradas no bbox, com o mesmo UV do atlas original |
| `model/roblox_upload/textures/*.png` | ColorMap, NormalMap, MetalnessMap, RoughnessMap em 2048 px (metal/rugosidade estavam em 4096 e são cinza puro → 1 canal) |
| `model/roblox_upload/asset_ids.json` | onde colar os ids depois do upload |
| `src/Workspace/R6MonsterMeshy.rbxmx` | o rig |
| `tools/build_meshy_monster.py` | gera tudo acima a partir do FBX e **verifica** o rig |

Os arquivos originais em `model/` não foram tocados.

## Para ver o monstro no Studio

O Roblox só mostra malha depois do upload, e isso precisa da sua conta:

1. Studio → **View → Asset Manager → Bulk Import** e importe os 6 `.obj` de
   `model/roblox_upload/parts/` e os 4 `.png` de `model/roblox_upload/textures/`.
2. No Asset Manager copie o id de cada um (botão direito → *Copy ID*) para
   `model/roblox_upload/asset_ids.json`. Malhas em `meshes`, imagens em
   `textures` (aceita só o número ou `rbxassetid://...`).
3. `python3 tools/build_meshy_monster.py` — regrava o rig com os ids
   (`MeshId` em cada peça + um `SurfaceAppearance` com os 4 mapas).
4. Com o Rojo conectado, o modelo aparece em `Workspace/R6 Monster Meshy`,
   ao lado do `R6 Monster` (x = 15, mesmo chão, y = 10).

Sem os ids o rig já carrega (estrutura, juntas, Humanoid), mas as peças ficam
sem malha visível.

## Aparência Meshy no monstro atual

O monstro em jogo continua sendo o `StarterCharacter` R6 que o `AppearanceManager`
escala em 1.2x. Nada disso mudou: `HumanoidRootPart`, `Humanoid`, os 6 Motor6D
(C0/C1), `Animate`, poderes, combate, colisão/hitbox, `Size` e `CFrame` de cada
parte R6 e a escala 1.2 seguem idênticos. A aparência entra **por cima**:

- `server/MonsterMeshyVisuals.lua` clona as 6 MeshParts do template
  `ServerStorage.MonsterMeshyVisuals` (com `MeshId`, `TextureID` e
  `SurfaceAppearance` do próprio clone), encaixa cada uma na parte R6 de mesmo
  nome e solda com `WeldConstraint`. Ficam em `character.MeshyVisuals`, com
  nomes `MeshyHead`, `MeshyTorso`… (nunca o nome de uma parte R6, para o
  `MonsterAnimationRigValidation` não achar peça duplicada).
- As partes R6 originais ficam `Transparency = 1` (o valor original é guardado
  num Attribute e devolvido por `Clear`). Continuam mandando no movimento,
  na animação e na hitbox.
- Os visuais são só cosméticos: `CanCollide/CanQuery/CanTouch = false`,
  `Massless = true`. O fade do teleporte (`MonsterTeleport`) já passa por todas
  as `BasePart` do character e os inclui sozinho.
- O `AppearanceManager` aplica **depois** do `ScaleTo(1.2)`, então cada peça é
  dimensionada a partir do `Size` que a parte R6 tem naquele momento: acompanha
  a escala do monstro e não fica gigante. Máscara, olhos, arranhão, cinto e
  corte no peito (o corpo antigo) não são criados quando o Meshy é aplicado;
  o facão continua.
- **Sem template válido** (falta MeshId em alguma peça, peça ausente, template
  inexistente) nada é aplicado e o monstro fica exatamente como antes, com um
  `warn` por motivo. Nunca fica meio invisível.

### Ajuste de cada peça

`AssetRegistry.Monstro_Modelo.Meshy.Parts`, uma entrada por peça:

```
tamanho do visual = Size ATUAL da parte R6 * Fit        (por eixo)
centro do visual  = CFrame da parte R6 * (Size * Offset)
```

Padrão: `Fit = 1,1,1` e `Offset = 0` (a peça ocupa a caixa inteira da parte R6,
então ombros, quadris e pescoço caem nas mesmas juntas de hoje). A cabeça usa
`Fit = 0.625, 1.25, 1.25` e `Offset = 0, 0.125, 0`: o R6 mostra a cabeça como
uma malha de `Size.Y * 1.25` apoiada no pescoço. Para mexer numa peça só, altere
só a entrada dela.

Cada peça é esticada por eixo até a caixa do R6, e as proporções do Meshy não
são exatamente as do R6. Deformação em relação a uma escala uniforme (calculada
com os tamanhos de `model/roblox_upload`; o script de Studio imprime os valores
reais do seu import):

| Peça | x | y | z |
| --- | --- | --- | --- |
| Head | +6% | −10% | +5% |
| Torso | −4% | +4% | +1% |
| Left/Right Arm | +2…4% | −10…11% | +8…9% |
| Left/Right Leg | −3% | −13% | +18% |

As pernas são o pior caso (mais longas e finas que a caixa do R6). Se incomodar,
reduza `Fit.Z` das pernas (por exemplo `1, 1, 0.85`): a perna fica mais fina
que a hitbox, sem mexer em nada do rig.

### Passo a passo

1. **Importar** (se ainda não fez): Asset Manager → Bulk Import dos 6 `.obj` de
   `model/roblox_upload/parts/` e dos 4 `.png` de `model/roblox_upload/textures/`.
   Precisa ser os 6 `.obj`: o FBX original inteiro é uma malha única e não dá
   para dividir dentro do Studio.
2. **Command Bar**, em modo de edição, com o Rojo conectado: colar
   `tools/meshy_appearance_once.server.luau`. Ele localiza o import no
   Workspace, imprime os ids no formato do `asset_ids.json` e cria
   `Workspace/R6 Monster (Meshy Preview)`, uma cópia do `R6 Monster` vestida com
   as peças pelo mesmo código do jogo, com a verificação do rig. Não altera o
   import nem o `R6 Monster`. Para apagar o preview: `REMOVER_PREVIEW = true`.
3. **Tornar permanente**: colar o JSON impresso em
   `model/roblox_upload/asset_ids.json` e rodar
   `python3 tools/build_meshy_monster.py`. Isso grava
   `src/ServerStorage/MonsterMeshyVisuals.rbxmx`, que o Rojo entrega em
   `ServerStorage`. Na próxima partida o Monstro nasce com a aparência Meshy.
   (Aceita também `texture_ids` por peça e `part_textures` com ids de mapas
   diferentes por peça, caso o import tenha gerado assim.)

### Desfazer

`AssetRegistry.Monstro_Modelo.Meshy.Enabled = false` desliga sem apagar nada.
Uma cópia dos arquivos antes desta etapa está em `backups/monstro_antes_meshy/`
(ver o `LEIA-ME.md` de lá).

### Verificado x não verificado

Verificado fora do Studio (`python3 tests/run_meshy_visuals.py <luau>`, com
dublês do Roblox): encaixe numérico de cada peça em um R6 escalado 1.2x, o
mesmo R6 em 1.0x (proporcional), rig idêntico antes/depois (Size, CFrame,
colisão, Motor6D C0/C1, Humanoid), nomes sem colisão com o validador de
animação, `Clear` restaura tudo, reaplicar não duplica, e as recusas (falta
MeshId/peça/template) não escondem nenhuma parte. O teste foi confirmado
mutando o módulo (não esconder a parte, inflar o tamanho, alterar `Size` do rig,
não soldar): todas as mutações são pegas. O script de Studio foi simulado nos
mesmos dublês (import em 6 Models, MeshParts diretas, FBX inteiro recusado,
proporção trocada, remoção).

**Não verificado — precisa do Studio:** como o monstro realmente fica (proporção
visual, deformação das pernas, textura/PBR, rosto), se o importador manteve os
eixos e a escala dos `.obj`, e o comportamento em jogo (animação, teleporte,
câmera em primeira pessoa). O script de Studio faz a checagem numérica do rig e
avisa se as proporções importadas divergem, mas quem confirma a aparência é você
com o preview ou um Play como Monstro.

## Como o rig foi montado

- Escala **uniforme única**: metade da largura do torso = 1 stud (torso com 2
  studs, como o R6). Resultado: 5,16 studs de altura, escala 1 (o jogo aplica
  o `ScaleTo(1.2)` do monstro por cima, como já faz com o R6 atual).
- Estrutura idêntica ao template: `Humanoid` R6 + `Animator`, `HumanoidRootPart`
  (PrimaryPart, transparente, ancorado como o template de autoria), `Torso`,
  `Head`, `Left/Right Arm`, `Left/Right Leg` (as 6 últimas são `MeshPart`).
- Motor6D `RootJoint`, `Neck`, `Right/Left Shoulder`, `Right/Left Hip` com as
  **matrizes de eixo do R6 padrão** (é isso que faz as animações R6 existentes
  servirem). Só as posições de C0/C1 mudam, para cair nos pivôs da malha:
  pescoço na base da cabeça, ombro na borda interna do braço, quadril na borda
  externa do topo da perna. Em repouso, `Part0 * C0 == Part1 * C1` em todas.
- Attachments do R6 padrão (grip, ombro, pé, chapéu, face, cintura…),
  escalados pelo tamanho de cada peça.
- Colisão como no template: só `Head` e `Torso` colidem. `CollisionFidelity =
  Box` (hitbox = caixa de cada peça), `RenderFidelity = Precise`.
- `HipHeight = -0.0328`. Vem de: altura do centro do torso até a sola (3,216)
  − perna (2,320) − metade do `HumanoidRootPart` (0,929). Com o `HRP` do
  tamanho do torso o valor fica quase 0, como no R6 padrão.

| Peça | Size (studs) |
| --- | --- |
| Head | 1.031 × 1.222 × 1.043 |
| Torso / HumanoidRootPart | 2.011 × 1.858 × 0.954 |
| Left Arm / Right Arm | 0.888 × 2.082 × 0.853 / 0.907 × 2.076 × 0.853 |
| Left Leg / Right Leg | 1.034 × 2.320 × 0.851 / 1.039 × 2.314 × 0.851 |

## O que foi verificado e o que não foi

Verificado (`tools/build_meshy_monster.py` roda isso sozinho, e a compilação
com `rojo build` passa):

- Nomes de peças e Motor6D exigidos por `MonsterAnimationConfig` presentes.
- Juntas coincidem em repouso; C0 e C1 com a mesma rotação.
- As 6 malhas fechadas (cada aresta em 2 triângulos); pés em y = 10.
- Renderização própria das peças montadas em repouso (idêntica ao FBX
  original) e em pose de caminhada (pernas ±35°, braços ±40°, pescoço girado):
  sem buracos, pivôs corretos.

**Não verificado — precisa de você no Studio** (não há Studio aqui e o upload
exige sua conta):

- Que o importador do Studio aceite os `.obj` com a escala/orientação
  esperadas. O rig define `Size` explícito, então uma escala uniforme
  diferente do importador seria absorvida; uma orientação trocada não.
- Se o pé encosta no chão ao jogar com o rig como personagem. A fórmula do
  `HipHeight` assume `HipHeight + altura da perna + metade do HRP` para o R6;
  se os pés flutuarem/afundarem, ajuste só `HipHeight`.
- A aparência com o `SurfaceAppearance` (o normal map do Meshy é OpenGL; se o
  relevo parecer invertido, inverta o canal verde do `NormalMap.png`).

## Próximos passos (não feitos, por não serem necessários para o teste)

- (Feito na seção "Aparência Meshy no monstro atual") vestir o monstro em jogo
  com as MeshParts, mantendo o rig do `StarterCharacter`.
- Se depois você gerar o modelo com esqueleto (rig humanoide do Meshy) dá para
  usar skin de verdade em vez de peças rígidas.
