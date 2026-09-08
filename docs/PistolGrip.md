# Calibrar a Glock17 no R6

O Grip original é identidade. O Muzzle aponta para -Z no espaço do Handle;
a posição do Muzzle nesse espaço é aproximadamente (-0.003, 0.705, -1.048).
O eixo Handle→Muzzle NÃO é a direção do cano: há uma diferença de altura entre
o ponto de empunhadura e a boca da arma. Usar esse vetor como direção inclina a pistola.

Identidade não prova um erro de Grip. O alinhamento final depende também do
RightGrip criado pelo Roblox e da pose animada do braço. Sem visualizar a pose
com a arma equipada, não existe um ângulo final verificável a partir deste XML.

Foi instalado `Modules.PistolGrip`, observado no servidor por
`PistolGripCalibration.server.luau`. Ele aplica:

```lua
tool.Grip = baseGrip
    * CFrame.new(position)
    * CFrame.Angles(math.rad(rx), math.rad(ry), math.rad(rz))
```

O offset inicial da mira ficou definido no codigo como:

```lua
PistolAimGripPosition = Vector3.new(0, 0.04, -0.08)
PistolAimGripRotation = Vector3.new(-13, -318, 0)
```

`baseGrip` é salvo no Attribute `PistolGripBase`. Existem dois offsets:

| Attribute | Uso |
|---|---|
| `PistolGripPosition` / `PistolGripRotation` | arma normal, fora da mira |
| `PistolAimGripPosition` / `PistolAimGripRotation` | somente enquanto mira |

A calibração é fixa, em espaço local; não acompanha a câmera nem altera Motor6D,
Transform, animações ou cano isolado. O controller da pistola aplica o offset
de mira ao segurar o botão direito e restaura o Grip normal ao soltar.

## Ajustar durante o Play

### Jeito rápido: dentro do jogo

Seu UserId tem um calibrador secreto. No Studio, ele também fica liberado para
teste. Dê Play, equipe a Glock17, segure o botão direito e pressione `L`. O
painel mostra os valores da mira e as teclas fazem o ajuste
na hora, então você não precisa abrir Command Bar, pausar ou soltar a mira.

| Teclas | Ajuste |
|---|---|
| `L` | abre/fecha o painel |
| `T` | trava/destrava pose: congela posição/rotação do player e mantém mirando |
| `V` | liga/desliga modo fantasma/freecam |
| `I` / `K` | rotação X ±1° |
| `J` / `H` | rotação Y ±1° |
| `U` / `P` | rotação Z ±1° |
| `A` / `D` | posição X ±0,02 |
| `Q` / `E` | posição Y ±0,02 |
| `W` / `S` | posição Z/frente ±0,02 |
| mouse | olha ao redor no modo fantasma |
| setas | move a câmera no modo fantasma |
| `R` / `F` | sobe/desce no modo fantasma |
| `Z` / `X` | diminui/aumenta a velocidade do modo fantasma |
| `Shift` + tecla | passo maior (5° ou 0,10) |
| `Backspace` | zera o ajuste |

Enquanto o painel está aberto, essas teclas são capturadas pela ferramenta de
calibração; `W/A/S/D` não devem mover o personagem. Com `T` ativo, o
HumanoidRootPart fica travado no CFrame salvo e marcado com `CrawlLock`, para o
shift-lock/câmera não virar o corpo durante a inspeção.

Esse painel altera `PistolAimGripPosition` e `PistolAimGripRotation`, então a
arma parada/fora da mira continua usando o Grip normal. Os valores ficam
visíveis no painel: anote ou envie uma
captura deles antes de parar o Play para eu gravar no arquivo da Tool.

### Command Bar

Equipe a Glock17, mantenha a mira e execute na **Command Bar em contexto Server**:

```lua
local player = assert(game.Players:FindFirstChild("SEU_NOME"), "Jogador não encontrado")
local tool = assert(player.Character and player.Character:FindFirstChild("Glock17"), "Equipe a pistola")
local grip = require(game.ReplicatedStorage.Modules.PistolGrip)
grip.Set(tool, Vector3.new(0, 0, 0), Vector3.new(0, 0, 0), true)
```

Troque `SEU_NOME` pelo nome de usuário. O primeiro Vector3 é posição em studs;
o segundo é rotação X/Y/Z em graus; o `true` no final significa "offset de
mira". Altere **um eixo de cada vez**, usando passos
pequenos (por exemplo 5 graus ou 0,05 stud). Esses passos são para comparar,
não uma sugestão de Grip final. Os argumentos são absolutos: repetir não acumula.

Após o primeiro comando, também é possível editar os Attributes
`PistolAimGripPosition` e `PistolAimGripRotation` na Tool pelo Explorer do servidor.
A alteração é imediata; não é preciso recomeçar a animação/equipar de novo.

Teste a mira no frame 10, o disparo completo 10–20, idle/holster, recarga,
mirar para cima/baixo, desequipar/reequipar e trocar para R6 novo. Se somente
uma pose fica correta, verifique a compatibilidade entre as animações antes de
criar offsets diferentes por estado. Um Grip fixo não conserta poses incompatíveis.

Para desfazer ou copiar o resultado, encontre a mesma Tool e execute:

```lua
-- Desfazer:
require(game.ReplicatedStorage.Modules.PistolGrip).Reset(tool, true)
-- Ou exportar o resultado ajustado (antes de resetar):
print(require(game.ReplicatedStorage.Modules.PistolGrip).Export(tool, true))
```

`tool` acima representa a variável local do primeiro trecho; para executar em
outra entrada da Command Bar, inclua novamente as duas linhas que a localizam.

## Salvar definitivamente

Alterações feitas no Play desaparecem no Stop. Antes de parar, envie os valores
que aparecem no painel (`PistolAimGripPosition` e `PistolAimGripRotation`) para
eu gravar como novo padrão em `src/ReplicatedStorage/Modules/PistolGrip.lua`.
Não transfira isso para `CoordinateFrame name="Grip"`, porque isso deixaria a
arma torta também fora da mira.

Referência: [Tool.Grip no Roblox](https://create.roblox.com/docs/reference/engine/classes/Tool#Grip).
