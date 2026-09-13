# Estação Abismo

Laboratório subterrâneo abandonado sob a floresta, com uma rota de fuga que
termina numa caverna costeira dentro d'água.

```
FLORESTA
  v  escotilha escondida entre árvores e pedras
POÇO DE ACESSO (escada de treliça, tubo de concreto)
  v
NÍVEL -1   eclusa / vestiário
  v  caixa de escada fechada (14 degraus)
NÍVEL -2   átrio -> corredor -> LABORATÓRIO | CONTROLE | ALA CLÍNICA
  v
CÂMARA DE BOMBAS
  v
TÚNEL DE EVACUAÇÃO (ACESSO MARÍTIMO) -- vai degradando
  v  comporta estanque
TRECHO ALAGADO (nada-se)
  v  grade antiga
CAVERNA COSTEIRA -> OCEANO
```

Tudo mora em `src/server/Tools/AbyssStationGenerator.lua`. É ferramenta de
EDITOR, como `IslandGenerator` e `PlaneCrashGenerator`: escreve terreno e
baixa assets do Toolbox, coisas que só funcionam em modo de edição.

## Como gerar

Command Bar do Studio, em **modo de edição**, depois de `IslandGenerator.Generate()`:

```lua
local Abismo = require(game.ServerScriptService.Server.Tools.AbyssStationGenerator)
Abismo.Build()
```

E **salve o lugar** (Ctrl+S). `Abismo.Clear()` apaga as Parts (o terreno
escavado não volta -- pra isso, regere a ilha).

## Onde ela nasce

`findSite()` varre a costa de 5 em 5 graus e exige, para aceitar uma direção:

- a escotilha a **178 studs da linha d'água** (a praia tem 45, então sobram
  ~133 studs *dentro* da floresta);
- fora da montanha, fora de clareira/POI/trilha/lago;
- chão a pelo menos **+20** (senão não sobra rocha acima do Nível -1);
- e o **caminho inteiro até a praia** também floresta (9 amostras) -- senão a
  escotilha cairia num corredor de trilha.

Se a ilha não tiver nenhum trecho assim, ele avisa e não constrói.

## Orçamento vertical

`IslandLayout.CONFIG.MinY = -24`: abaixo disso não existe terreno.

| Área | Piso | Teto | Rocha abaixo | Rocha acima |
|---|---|---|---|---|
| Nível -1 | -4 | +8 | — | ~19 (floresta) |
| Nível -2 / túnel | -18 | -6 | ~4,5 | ~33 floresta, ~13 sob a praia |
| Caverna costeira | -20 | +8 | dentro do promontório | idem |

A praia é um platô em +8..+12 e o fundo do mar despenca para -20/-22 a um
stud da linha d'água (`IslandLayout.rawHeight`), então a boca da caverna abre
direto em água funda.

## "Tudo tampado": nenhuma terra, areia ou grama à vista

Duas garantias, porque uma só não basta.

1. **Casca fechada por ambiente.** `roomShell` monta piso, teto e as quatro
   paredes; `wallX`/`wallZ` recortam a parede em segmentos em volta de cada
   vão (peitoril embaixo, verga em cima), então nenhum pedaço "some" quando
   se abre uma porta. `slabWithHole` faz o teto do Nível -1 com o vão do poço
   em quatro retângulos que se encontram sem fresta.
2. **Casca de rocha.** `encaseRock()` converte em ROCHA o miolo em volta da
   instalação inteira **antes** de cavar. Se sobrar qualquer fresta de voxel
   entre o acabamento e o terreno, o que aparece é pedra. O topo desse
   preenchimento fica 9 studs abaixo da superfície (amostrada por raycast em
   5 pontos da largura, todos antes de qualquer escrita) pra não brotar
   mancha de rocha no meio do mato.

A caverna costeira é a única rocha exposta, e é de propósito: ali a estação
já acabou.

O poço de acesso é um tubo **quadrado**: anel de painéis curvos contra um
buraco retangular de laje sempre deixa canto sem cobrir, e canto sem cobrir é
exatamente onde a terra apareceria. Pelo mesmo motivo a caixa de escada leva
parede e teto por degrau, em peças 1,4 mais grossas que o passo de 1,0 -- o
encavalamento de 0,4 fecha o espelho de cada degrau.

## Assets do Toolbox

| Constante | ID | Onde é usado inteiro | Onde vira peça avulsa |
|---|---|---|---|
| `ASSETS.Laboratorio` | 1105615633 | Laboratório (fundo da sala) | Controle, Ala Clínica, Átrio |
| `ASSETS.Complexo` | 12470367049 | Ala Clínica (fundo da ala) | Laboratório, Nível -1, Câmara de Bombas |
| `ASSETS.Porta` | 4590494732 | folha das 4 portas | — |

- `placeAsset` + `fitInto` escalam pela **bounding box** (o Toolbox não segue
  escala nenhuma) e apoiam pelo **centro da caixa**, não pelo pivô -- asset de
  pivô torto ficaria meio enterrado no chão.
- `openPassage` limpa o vão de entrada depois que o cenário entrou: não dá pra
  saber onde o modelo pôs as próprias paredes, então o que for do tamanho de
  móvel e estiver no caminho da porta é apagado, e o que for grande demais pra
  apagar sem furar a cena vira atravessável. Nenhuma das duas saídas prende o
  jogador.
- `harvest` + `scatterPieces` separam o asset em adereços avulsos e os
  espalham nos outros ambientes. Peças com cara de casca (parede/piso/teto,
  por nome ou por serem placas grandes e finas) ficam de fora: soltas viram um
  paredão no meio da sala.
- `assetDoor`: o `DoorSystem` só sabe girar **uma** BasePart. Então a folha de
  verdade é uma Part do tamanho do vão (leva o Attribute `Porta` e a colisão,
  retangular e previsível) e as Parts do asset entram desancoradas, presas nela
  por `WeldConstraint` e **sem colisão** -- malha de asset como colisor num vão
  estreito é o jeito mais curto de prender o jogador.
- Se um asset não carregar (InsertService é restrito fora do modo de edição),
  o ambiente cai no mobiliário procedural de reserva e `Build()` avisa no
  Output quais faltaram. A estação nunca fica vazia.

## Água

- **Poças** do trecho seco: Parts refletivas isoladas (infiltração).
- **Água de terreno** do trecho alagado até o mar aberto. O teto do trecho
  alagado fica em **-8**, muito abaixo do mar (+4): "cheio d'água" é o estado
  coerente, e é isso que obriga a nadar. A **comporta estanque** explica o
  corredor seco atrás.
- A água é preenchida só até o **teto do vazio escavado**, não até o nível do
  mar: senão sobraria um bolsão de água preso dentro da rocha acima do túnel.
- Dentro da caverna a água vai a +4 e o teto a +8: sobra bolsão de ar pra
  emergir antes de sair.

### Caminho de nado (conferido numericamente)

| Etapa | Vão livre |
|---|---|
| comporta | 6,0 × 8,0 |
| trecho alagado | 7,3 × 10,0 |
| colar da boca do túnel | 7,2 × 9,3 |
| caverna | 22 × 28 |
| fresta da boca | 9,0 de largura, topo 3 studs **acima** da linha d'água |
| saída externa | passa de onde a rocha artificial acaba, sem lábio de pedra |

O **colar da boca do túnel** (`buildFlooded`) tapa a folga entre a seção de
concreto e a rocha da caverna: sem ele, quem está na caverna enxerga o vazio
escavado em volta do túnel -- e é justamente lá que o terreno da praia
apareceria.

## Ganchos pra gameplay futura

Nada disso está implementado; a arquitetura é que está pronta.

| Attribute | Onde | Pra quê |
|---|---|---|
| `AbismoZona` | marcadores por área | Escotilha, Poco, NivelMenos1, Escada, NivelMenos2, Bombas, Tunel, Alagado, Caverna, Mar |
| `AbismoSala` | marcadores do Nível -2 | Atrio, Corredor, Laboratorio, Controle, Clinica |
| `AbismoAlagavel` + `NivelAguaCheio` | bombas, túnel, alagado | áreas que um sistema de inundação pode encher |
| `AbismoPortaPrincipal` | tampa da escotilha | bloquear a saída principal |
| `AbismoPorta` | folhas das 4 portas internas | trancar/arrombar |
| `AbismoComporta` | comporta estanque | disparar a inundação |
| `AbismoGradeMar` | grade da caverna | último obstáculo |
| `AbismoSaidaMaritima` | boca, no mar | ponto de fuga |
| `Porta` | comporta, grade e as 4 portas | `DoorSystem` já dá o prompt Abrir/Fechar |
| `PontoLoot` | espalhados | `ItemSpawner` / `LootCrateSystem` |

Cobre "presos dentro", "porta principal bloqueada", "fuga pelo túnel",
"instalação alagando" e "escapar mergulhando".

## Limitação conhecida

Nada disto foi visto no Studio -- a validação é por compilação, análise
estática e conferência numérica de volumes/colisão. O ponto que mais vale
conferir na prática é o nado da comporta até o mar aberto, e como cada asset
do Toolbox se comporta depois de escalado (se um deles vier com o pivô muito
fora do corpo, é `fitInto` que ajusta).
