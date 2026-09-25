# Caverna do Monstro — o covil dentro da montanha

A montanha tem `Radius 150` e `Peak 95` (`IslandLayout.CONFIG.Mountain`), mas
a caverna antiga era uma bola de terreno de raio 17 num canto dela: pequena,
lisa e vazia. Agora o interior ocupa o miolo da montanha, é **escuro** e tem
**três níveis** ligados por rampa, escada e ponte.

| Arquivo | Papel |
|---|---|
| `Tools/CaveInterior.lua` | Escava o terreno, monta o interior e cria volumes invisíveis de escuridão. |
| `Tools/IslandGenerator.lua` | `GenerateCave()` acha a montanha, monta o `Frame`, chama `CaveInterior.Build`, cria o marcador `MonstroSpawn` e as rochas da boca. |
| `client/CaveDarknessController.client.luau` | Escurece a visão de quem entra na caverna e dá visão local ao Monstro. |

## Espaço local

Tudo em `CaveInterior` é descrito em coordenadas polares em volta do centro da
montanha:

- `theta = 90°` aponta pra **boca** (o lado do centro da ilha), `270°` é o fundo.
- `r` = distância do eixo, `y` = altura acima do chão do salão.

O `Frame` que o gerador passa tem `Center` (centro da montanha com Y = 0),
`Dir`/`Side`, `FloorY` (chão do salão), `MouthY` (chão da boca), `MouthDist` e
`SurfaceY(x, z)`.

## Planta

```
   Nível 2 (y=33)  [ LAJE DO FUNDO + NINHO ]  theta 195–295, r 14–48
                     ^ escadaria de pedra (theta 350→295)
   Nível 1 (y=17)  [ GALERIA quase em anel ]  theta 280→200, r 34–48
                     ^ rampa colada na parede (theta 200→280)
                     = ponte de tábuas cruzando o salão (theta 60↔170)
   Nível 0 (y=0)   [ SALÃO r 40 ] + POÇO rochoso (r 13, 6 fundo)
                     -> Câmara mineral (theta 178)   -> Depósito (theta 352)
                     <- túnel em S, descendo 9 studs desde a boca
```

- **Túnel**: 13×13, quebrado em três trechos — da boca **não dá pra ver o
  salão**. Desce `Tunnel.Drop` (9) studs quase todos no primeiro cotovelo,
  então o covil fica abaixo do nível da ilha lá fora e o teto fecha cedo: a
  encosta só fica aberta nos ~24 studs da fenda de entrada (a montanha não
  sobe rápido o bastante pra cobrir um vão de 13 antes disso).
- **Salão**: cilindro de raio 40 até 40 de altura e abóbada elipsoidal até 56.
  A parede é recortada por 16 bolsões verticais, então não parece um cano.
- **Poço**: no meio, 6 studs abaixo do chão, com rochas e fungos opacos. Tem
  rampa tosca pra sair — quem cai não fica preso.
- **Ninho**: no nível de cima, no fundo. É onde nasce o Monstro (marcador
  `MonstroSpawn`).

Acessos: rampa (chão → galeria), escada de treliça do lado da entrada (atalho
chão → galeria), escadaria de pedra (galeria → laje) e a ponte cruzando o
salão por cima do poço. A galeria fecha o circuito com o topo da rampa.

## Clima

O cenário não cria `PointLight`, `SpotLight`, `Fire` ou material `Neon`.
Fungos são opacos e só aparecem ao serem iluminados. A abertura antiga do
teto é fechada ao regenerar o terreno.

`Workspace/Ilha/Caverna/DarknessZones` contém volumes invisíveis sem colisão.
O cliente consulta a posição da câmera e aplica uma transição curta de
escuridão aos sobreviventes. A lanterna continua usando seus `SpotLight` e
`PointLight` locais, portanto o feixe revela o caminho. O Monstro recebe
uma luz local próxima à câmera enquanto estiver na caverna; ela não é
replicada nem requer ferramenta. A névoa permanece como decoração sem luz.

## Câmaras laterais

- **Câmara mineral** (`theta 178`, r 54) — prateleiras de rocha, minerais,
  cristais e fungos.
- **Depósito** (`theta 352`, r 52) — lonas penduradas, correntes vazias,
  jaulas e tonéis.

## Regerar

Modo de edição, Command Bar, e **salvar** depois:

```lua
local Gen = require(game.ServerScriptService.Server.Tools.IslandGenerator)
Gen.GenerateCave()   -- só a caverna (não mexe no resto do mapa)
```

Dá pra rodar quantas vezes quiser: antes de escavar, `CaveInterior.Carve`
**devolve rocha maciça ao miolo da montanha** (`resealMountain`), apagando
qualquer caverna anterior — inclusive a antiga, que era um túnel reto com uma
bola de raio 17 no fim. O teto de cada anel de preenchimento fica 2 studs
abaixo do relevo calculado (`Frame.PlanY`, não raycast — um raycast cairia
dentro do buraco velho), então a montanha vista de fora não muda.

`GenerateCave` apaga e refaz `Workspace/Ilha/Caverna`, que fica organizada em
`Tunel`, `Nivel0_Salao`, `Nivel0_Poco`, `Nivel1_Galeria`, `Nivel2_Ninho`,
`Camaras`, `Ambiente` e `DarknessZones`. É preciso regenerar para retirar as
luzes já salvas no lugar e adicionar os novos volumes.

Pra mexer só no cenário sem reescavar o terreno, dá pra chamar
`CaveInterior.Dress(pasta, frame, seed)` direto.

## Ajustes

`CaveInterior.CONFIG` tem as medidas (túnel, salão, níveis, poço,
câmaras, ninho) e `CaveInterior.LAYOUT` tem os ângulos de cada trecho de laje.
Se aumentar `Hall.Height` ou `Hall.Radius`, confira a espessura de rocha que
sobra: a montanha só tem `Peak 95` no eixo e cai rápido pras bordas.
