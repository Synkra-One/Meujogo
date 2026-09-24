# Casas grandes

Oito casas nas quatro clareiras preparadas (Acampamento, CabanasA, CabanasB e
VilaNativa), duas por clareira, em dois estilos, e a **fazenda** no Campo
(celeiro grande + casa velha de fazenda). Tudo é gerado por código em modo de
edição e salvo no lugar.

## Estilos (`src/server/Tools/Houses/`)

| Estilo | Planta | Cômodos |
| --- | --- | --- |
| **CampCabin** (a CampCabin_01) | 64 × 34, cabana de tábuas com troncos nos cantos | sala + cozinha, hall largo, 2 quartos; varanda coberta na frente e patamar nos fundos |
| **CasaDoCaseiro** | L de 48 × 26 + ala 18 × 18, tábuas pintadas (verde / vermelho / azul-cinza), chaminé de pedra | sala com lareira, hall, cozinha com jantar, corredor, banheiro, quarto; varanda de ponta a ponta |
| **Celeiro** (Campo) | 36 × 52 vermelho, telhado holandês de chapa com capuz e roldana de feno, portas duplas em X na frente e atrás | corredor, 3 baias com portão que abre, selaria com porta, escada pro palheiro, oficina; telheiro com trator, silo, curral |
| **CasaDaFazenda** (Campo) | 40 × 28 de **dois andares**, tábua creme descascando, zinco enferrujado, chaminé de tijolo, varanda em L com balanço | sala (lareira, piano, relógio de pêndulo), hall com escada, jantar (cristaleira), cozinha no puxado; em cima quarto do casal e quarto das crianças; quintal com cata-vento, poço e casinha com porta |

Comum aos dois:

- **O terreno do mapa não muda de altura.** A casa se adapta ao chão: o piso
  fica `Found` acima do ponto mais alto sob a construção e fundação, saia da
  varanda e degraus descem até o ponto mais baixo (`HouseKit.ExtraDepth`).
- **Sem grama no piso**: só o material do chão muda: terra (`Ground`, sem
  grama animada) sob a casa, em volta e no caminho até a trilha.
- **Duas saídas** por casa (frente e fundos). Porta de entrada, fundos,
  quartos e banheiro abrem pelo `DoorSystem`. Maçaneta e almofadas giram
  junto com a folha. `DobradicaDireita` escolhe o lado da dobradiça.
- Forro em todos os cômodos, luzes de teto (algumas apagadas) e arandelas na
  varanda, que servem de referência à noite.
- Usa os modelos de `Workspace["Modelos para as casas"]` quando existem: a
  cama "Bed horror game" e a luminária "ceiling ligh", assentadas pela caixa
  real do modelo (sem afundar no piso). Senão monta versões próprias. Se a
  cama de referência ficar com a cabeceira ao contrário, troque
  `Furniture.ReferenceBedHeadAtPlusZ`.
- Cada casa tem 1 SpawnPOI na frente e 2 ou 3 PontoLoot no piso; a
  CasaDoCaseiro tem também 1 SpawnArma.

## Gavetas (`server/DrawerSystem.lua`)

Cômodas, gaveteiros, criados-mudos, balcões, escrivaninhas, aparador,
guarda-roupas e gabinete de banheiro mantêm os móveis e suas gavetas visuais.
Cada casa tem **5 a 7 gavetas funcionais**, priorizando apenas a superior de
cada móvel; as demais ficam fechadas, decorativas e sem interação. Se houver
poucos móveis, outras gavetas completam o mínimo, até o limite existente.

| Tecla | Ação |
| --- | --- |
| E | Abrir / Fechar (a gaveta desliza, com a bandeja soldada na frente) |
| B | Guardar o item da mão (só com a gaveta aberta e vazia; recusa o que não cabe) |
| E no item | Pegar (o prompt normal do `DropItemSystem`) |

- A cada rodada (`RoundPrepared`) todas fecham, o que ficou guardado some e
  são sorteadas **1 a 3 gavetas com um item cada, por casa**, sem teto global.
  As gavetas funcionais e as que recebem loot são sorteadas novamente.
  O item só é sorteado
  quando alguém abre a gaveta pela primeira vez, com a Sorte de quem abriu
  (os mesmos pesos das caixas).
- Limites em `GameConfig.Drawers.FunctionalPerHouse` e `LootPerHouse`.
- Caixas também renovam o loot a cada partida: as geradas são reposicionadas,
  e as colocadas manualmente voltam a ficar fechadas e disponíveis.
- Item em gaveta fechada fica escondido: sem "Pegar", e fora do mapa de
  descobertas (`OcultoNaGaveta`).
- Gavetas largas (gaveteiro, cômoda) cabem o Pé de cabra e o Taco. O item
  é deitado com o lado maior na largura.
- O Monstro não usa gaveta (`GameConfig.Drawers.MonsterCanUse`).
- Contrato dos Attributes da frente: cabeçalho de `Tools/Houses/Furniture.lua`.

## Gerar (Studio, modo de edição, Command Bar)

```lua
require(game.ServerScriptService.Server.Tools.HouseGenerator).Generate()
```

Depois **salve (Ctrl+S)**. Para os PontoLoot novos receberem itens, rode também
`require(game.ServerScriptService.Server.Tools.ItemSpawner).Generate()`.
`IslandGenerator.Generate()` já chama o HouseGenerator no fim.

- **Lotes**: na primeira vez o gerador escolhe onde cada casa fica. Ela fica
  dentro do raio, longe da trilha, sem encostar em rocha, poste nem objeto
  solto, e as duas casas da clareira ficam de frente uma para a outra. Cada
  escolha vira uma Part invisível do tamanho da casa em
  `Workspace.Ilha.LotesCasas`, com os Attributes `Clareira`, `Estilo` e
  `Indice`. Para mudar uma casa, arraste ou gire o lote (ou troque o `Estilo`)
  e rode `Generate()` de novo. `Replan()` esquece os lotes e escolhe tudo de novo.
- **Clareira apertada**: se as duas casas não couberem do jeito normal, o
  gerador tenta em até três níveis, cada um só entrando em ação se o anterior
  não bastou:
    1. Padrão: casa perto do meio do raio, olhando pro centro.
    2. Relaxada: qualquer orientação e até 24 studs além da borda da
       clareira; as árvores no caminho (CabanasB tem rocha grande perto do
       Afloramento_6) vão para o backup em vez de bloquear.
    3. Último recurso: ignora a trilha (ela não é sólida, só textura de
       terreno -- a casa pode ficar em cima dela, só meio estranho
       visualmente). Só usada se nem a relaxada coube.
  Se mesmo assim não couber, ele avisa no Output com o nome do lote pra
  editar à mão (mover o `Lote_*`, ou trocar o `Estilo` por um menor).
- **Terreno**: só pinta terra batida (sem mexer na altura). Lotes feitos pela
  primeira versão do gerador, que nivelava e subia o chão, têm o terreno
  reconstruído a partir do `IslandLayout` na próxima vez que `Generate()`
  roda (Attribute `TerrenoOriginal` no lote marca que já está certo).
  `HouseGenerator.RestoreTerrain(cframeNoChao, retangulo)` refaz qualquer área.
- **Nada é apagado**: arbustos, troncos e itens soltos que estavam no lugar
  da casa, as árvores (só na segunda tentativa), a CampCabin_01 antiga solta
  no Campo e o celeiro simples do Campo (`Ilha.POIs.Campo`) vão para
  `ServerStorage.MapEditBackups/Casas_<data>`.

## Testes

```
python3 tests/run_houses.py     ~/.rokit/bin/luau   # geometria das duas casas
python3 tests/run_drawers.py    ~/.rokit/bin/luau   # gavetas de ponta a ponta
python3 tests/run_house_plan.py ~/.rokit/bin/luau   # lotes nas clareiras reais
```

`run_houses` verifica que:

- as portas giram de 0 a 100° sem bater em nada;
- as gavetas abrem sem entrar em parede ou móvel, e somem dentro do móvel quando fechadas;
- nenhum móvel atravessa parede;
- o telhado não entra em nenhum cômodo;
- as passagens estão livres;
- as caixas dos PontoLoot têm espaço;
- tudo cabe no `Footprint`.

Física, iluminação e voxels do terreno só dá para conferir no Studio.
