# Estação Abismo

Laboratório subterrâneo com entrada em uma pequena caverna rochosa na floresta.
Fica **do lado oposto da ilha em relação à montanha**: a caverna do Monstro e o
laboratório nunca dividem a mesma encosta. Uma porta industrial dá acesso à
escada de degraus e à recepção. O corredor central conecta todas as salas,
passa pelo salão de testes e termina em outra escada, com porta de saída para
um pátio seco junto à costa.

```text
FLORESTA → CAVERNA → PORTA → ESCADA DE ENTRADA (60 studs)
                                  ↓
            ÁREA TÉCNICA  ←  RECEPÇÃO
                                  ↓
             LABORATÓRIO  ←  CORREDOR  →  SALÃO DE TESTES
                 ARQUIVO  ←  CORREDOR        (Frog Generator)
              ENFERMARIA  ←  CORREDOR  →  CONTROLE
                                  ↓
                     ESCADA DE SAÍDA (36 studs) → PORTA → COSTA
```

## Planta

O corpo do laboratório tem 120 studs de corredor entre os dois lances, contra
92 studs de escada somados — antes era o contrário. Todas as medidas em studs,
no espaço local da estação (X lateral, +Z para a costa).

| Ambiente | Frente × fundo | Pé-direito | Porta |
|---|---|---|---|
| Vestíbulo (na caverna) | 20 × 8 | 14 | Entrada, 12 |
| Recepção | 48 × 32 | 16 | — (vão da escada) |
| Área Técnica | 42 × 32 | 16 | 10 |
| Corredor | 24 × 120 | 16 | — |
| Laboratório | 48 × 48 | 16 | 10 |
| **Salão de Testes** | **76 × 76** | **18** | 14 |
| Arquivo | 48 × 32 | 16 | 10 |
| Enfermaria | 48 × 28 | 16 | 10 |
| Controle | 48 × 36 | 16 | 10 |
| Saída Seca | 20 × 8 | 14 | Saída, 12 |

## Salão de testes e o Frog Generator

A maior ala do laboratório: 76 × 76 com 18 de pé-direito, é onde os cientistas
trabalhavam com os monstros. O centro fica vazio, com o ralo no meio do piso.

- **Frog Generator** — a cápsula de cultivo, de frente para a porta do salão.
  Base de aço, tanque de vidro com fluido verde e luz própria, o espécime
  suspenso dentro, anéis de pressão, quatro mangueiras descendo e o console
  de comando na frente. O `Model` chama-se `FrogGenerator` e carrega os
  Attributes `FrogGenerator = true` e `AbismoCapsula = "FrogGenerator"` —
  é por eles que o resto do jogo acha a cápsula, não pelo nome.
- **Seis celas de contenção** nas duas paredes longas, com grades, verga,
  comedouro e sangue seco. Uma de cada três aparece rompida, com as grades
  tortas para fora.
- **Quatro consoles de observação** junto à porta, fora da varredura da folha.
- **Duas mesas de necropsia** com correias, canaleta, foco cirúrgico e
  instrumental.
- **Ponte rolante** com trilhos, carro e guincho parado sobre a cápsula.
- Faixas de perigo em volta da cápsula e rastros de arrasto pelo piso.

## Aplicar no Studio

Sincronize o projeto pelo Rojo (plugin **Connected**). Na Command Bar, em
**modo de edição**, depois da geração do terreno e da vegetação, cole esta
**única linha**:

```lua
require(game.ServerScriptService.Server.Tools.AbyssStationRunner).Run()
```

O `Run()` carrega uma cópia nova de `Tools` (o `require` do Studio guarda o
gerador antigo em cache), usa a seed da ilha e chama `Build()`. O relatório
sai no Output **e** em `ServerStorage.DiagAbismo` (propriedade `Value`): se o
painel Output estiver filtrando mensagens, leia por lá. Um relatório com
`OK: estação construída` e `FrogGenerator no modelo: true` confirma o
resultado; em caso de erro ele traz a mensagem e o traceback.

Salve o lugar após conferir a construção. O gerador substitui
`Workspace.Ilha.EstacaoAbismo`; alterar seu código não modifica automaticamente
uma estação já salva. Ele não é executado no início de cada partida.

Execute o Abismo **por último**: gerar terreno ou reparar a água depois da
estação pode voltar a preenchê-la. `Build()` mantém a posição e a orientação
nas reconstruções **da mesma versão da planta**.

Uma estação salva com a planta antiga (`AbismoVersion` 3 ou a escotilha
original) não é remendada: o gerador fecha o poço/eixo antigo com rocha,
escolhe um sítio novo do lado oposto da montanha e constrói lá. A escavação
abandonada continua aberta embaixo da terra — para apagá-la de vez é preciso
regenerar o terreno.

`Clear()` remove somente o modelo. As plantas e rochas que invadiam a
construção ficam preservadas em `ServerStorage.AbismoVegetacaoPreservada`,
identificadas pelo atributo `AbismoPastaOriginal`.

## Escolha do local

`findSite()` varre os 72 ângulos da costa e mede cada corredor candidato:

1. **Separação da montanha** — pelo menos 120° entre a estação e o centro da
   montanha, e no mínimo 340 studs entre qualquer ponto da estação e a boca da
   caverna. Nos testes de seed isso dá 144–180° e 545–863 studs.
2. **Terreno livre** — nenhum POI, trilha, lago ou encosta de montanha sob o
   eixo nem sob as duas alas.
3. **Cotas** — chão de 14 a 32 na boca da caverna (para a escada de entrada
   caber em 60 studs), de 6 a 12,25 na saída, e pelo menos 18 sobre o teto das
   salas em todo o corpo.

Os critérios são afrouxados em duas etapas se a seed não oferecer nada que
sirva, sempre com `warn` dizendo o que cedeu. Só depois disso a construção
falha pedindo `Frame` explícito.

## Acabamento e acesso

- Painéis claros de laboratório, rodapés em azul petróleo, piso metálico
  contínuo, teto fechado, iluminação fria e sinalização de emergência.
- Mobiliário nativo, sem downloads do Toolbox. Os postos de trabalho encostam
  nas paredes, pulando os vãos declarados no plano e as quinas, e as salas
  grandes ganham duas ilhas centrais — o miolo e o eixo das portas continuam
  livres.
- Oito portas integradas ao `DoorSystem`. Visores e barras são soldados à folha
  móvel; as dobradiças ficam fora da espessura da parede.
- Escadas sólidas de 16 studs de largura, com espelhos de até 0,95 stud,
  pisadas de pelo menos 0,95 (1,4 a 1,6 numa entrada de cota normal),
  corrimãos e caixa fechada. Não existem `TrussPart`, escotilha ou trecho de
  nado.
- Saída independente pela costa, acessível pelo corredor principal.

O laboratório fica em Y=-16. Cada ambiente tem piso e teto de 2 studs e
paredes de 2 studs. As paredes compartilhadas possuem um único responsável; o
salão de testes, mais alto que o corredor, fecha sozinho apenas a faixa acima
da parede do vizinho. Somente os vãos declarados no plano ficam abertos. As
escadas têm 12 studs de altura livre nominal.

A escavação deixa 8 studs de folga além da estrutura nas laterais e embaixo, e
4 acima do teto — perto da praia o terreno é raso, e dois voxels acima do teto
encostariam na superfície. As partes superiores das escadas têm cobertura e
laterais rochosas, e os acessos possuem bases sólidas. Vegetação e rochas que
atravessariam esses volumes são retiradas da área construída.

## Arquivos e parâmetros

| Arquivo | Responsabilidade |
|---|---|
| `src/server/Tools/AbyssStationGenerator.lua` | Localização, construção, escavação, portas e limpeza da área |
| `src/server/Tools/AbyssStationPlan.lua` | Dimensões, salas, aberturas, escadas, portas e faixas do sítio |
| `src/server/Tools/AbyssLabFurnishings.lua` | Mobiliário das salas, salão de testes e Frog Generator |
| `src/server/Tools/AbyssStationRunner.lua` | Comando de uma linha para a Command Bar, com relatório em `DiagAbismo` |

`Build(seed?, options?)` retorna o modelo. Normalmente basta `Build()`.
Para uma implantação deliberadamente posicionada ou um teste:

```lua
Abismo.Build(1337, {
    Frame = CFrame.new(150, 0, -210), -- horizontal; +Z aponta para a costa
    EntryGround = 24,               -- altura do chão junto à entrada
    ExitGround = 9,                 -- altura do chão junto à saída
    Terrain = false,               -- apenas para inspecionar geometria sem cavar
})
```

`Terrain` é `true` por padrão. Cada lance tem vão fixo: um plano cuja escada
não caberia nele falha **antes** de apagar a estação anterior ou modificar o
terreno, dizendo quantos degraus precisaria e quantos studs existem.

Permanecem os contratos `EstacaoAbismo`, `Construcao="Abismo"`, `AbismoZona`,
`AbismoPortaPrincipal`, `AbismoSaidaMaritima`, e agora oito pontos `PontoLoot`
(um por sala, dois no salão de testes).

## Validação

```sh
python3 tests/run_abyss_station.py /caminho/para/luau
rojo build default.project.json -o /tmp/Meujogo-abismo.rbxlx
```

Os testes executam os módulos reais sobre um stub de Roblox: verificam salas
acessíveis, paredes/piso/teto, altura livre, degraus, giro das portas sem atingir
paredes ou móveis, mobiliário dentro da casca, soldas, escavação, reconstrução,
migração da escotilha antiga, retirada de vegetação invasora, seleção de local,
presença do Frog Generator dentro do salão e a proporção entre escadas e corpo.
Incluem implantação girada e alturas maiores.
Não substituem a conferência de renderização, voxels e caminhada com um Humanoid
no Studio. Confira entrada, todas as portas, salas e saída nos dois sentidos.
