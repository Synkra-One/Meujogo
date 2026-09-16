# Super audição do monstro

O servidor emite memórias curtas de ruídos de sobreviventes. Somente monstros
vivos, com `InRound = true`, durante uma rodada ativa e dentro do alcance
recebem `NoiseDetected(position, intensity)`. Espião, lobby e eliminados não
produzem indicadores. Não são enviados Player, nome, personagem ou alvo.

## Auditoria e reaproveitamento

A estrutura ativa foi conferida pelo `default.project.json`, junto das buscas
por ruído, sons, footsteps, sprint, stamina, crouch e transições de Humanoid
nos scripts Lua/Luau e nos Sources XML do pacote de movimento. Os `.rbxm`
originais e backups não são novos controladores a importar para o jogo.

| Sistema existente | Uso nesta implementação |
| --- | --- |
| `server/StaminaSystem.lua`, `SprintIntent`, `StatScaling.WalkSpeed` | O loop existente de 10 Hz publica `MovementSampled`; a audição reaproveita a velocidade e a base de caminhada já calculadas. Nenhum novo Heartbeat. |
| `StarterCharacterScripts/Crouching.rbxmx` | Continua dono de movimento, FOV, crouch/crawl e sprint. Seus atributos locais não são usados como autoridade no servidor. |
| `Footsteps.rbxmx`, `RbxCharacterSounds.rbxmx`, `FootstepModule.rbxmx` | Já reproduzem passos, salto e pouso no cliente. Continuam responsáveis pelo áudio; nenhum segundo sistema de passos foi criado. |
| `client/FallEffects.client.luau`, `FallDamageEvent`, `DamageSystem` | Já tratam apresentação e dano de queda. A audição observa `Humanoid.StateChanged` e a amostra existente no servidor; não depende da altura enviada pelo cliente para dano. |
| `WeaponSystem.NoiseMade` | Gancho existente agora informa também jogador/intensidade no arremesso da pedra; `NoiseService` o consome. A posição continua sendo o primeiro argumento, preservando o contrato anterior. |
| `RadioSiteSystem` | Emite o mesmo gancho sem jogador. Continua como fonte ambiental, sem ping de sobrevivente: o requisito exige atribuição a um sobrevivente real. |
| `FearSystem.PanicSoundTriggered` | Reutilizado, preservando seu raio e usando `PanicIntensity`. |
| `RoundManager`, atributos `Role`, `InRound`, `Eliminado` e Health | Reutilizados para elegibilidade, término, troca de papel e respawn. |
| `SoundManager` | Continua responsável por áudio posicional e de pânico. O indicador não depende do carregamento dos assets de áudio. |

Não havia consumidor de `NoiseMade` para super audição nem visualizador
equivalente. Os novos arquivos seguem o mapeamento atual: módulo em
`ServerScriptService.Server`, LocalScript em `StarterPlayerScripts.Client` e
RemoteEvent real no diretório já sincronizado pelo Rojo.

## Como um passo vira (ou não vira) um ping

Não é "entrou no raio = aparece ping". São quatro camadas, nesta ordem:

1. **Estado de movimento.** A velocidade horizontal **real**, dividida pela
   base de caminhada do personagem, cai em uma faixa de
   `GameConfig.Characters.MovementBands`. É medição física, não Attribute do
   cliente.
2. **Furtividade.** O atributo do personagem decide, *dentro daquele estado*,
   o **alcance** e o **intervalo** entre ruídos.
3. **Silêncio.** Se o alcance que a Furtividade produziu ficar abaixo de
   `MinAudibleRadius`, o ruído **não é gerado**. Ninguém ouve, nem um Monstro
   colado.
4. **Distância.** Mesmo dentro do alcance o ping pode se perder, e a posição
   chega cada vez mais embaralhada conforme o Monstro está mais longe.

### Estados de movimento

| Estado | Tecla | Velocidade | Proporção | Faixa |
| --- | --- | --- | --- | --- |
| Rastejando | `Z` | 3 | 0,25 | `Crouch` |
| Agachado | `C` | 6 | 0,50 | `Crouch` (≤ `MovementBands.Crouch` = 0,58) |
| **Andar** | *nada* — é o padrão | 12 | 1,00 | `Walk` (≤ `MovementBands.Walk` = 1,15) |
| **Trotar** | `Control` — segurar | 15 | 1,25 | `Jog` (≤ `SprintSpeedRatio` = 1,35) |
| **Correr** | `Shift` — segurar | 23 | 1,92 | `Sprint` |

As velocidades são as do `Crouching` (ver `docs/MovementPack.md`); o que o
servidor guarda são as **proporções**, então valem igual para quem tem
`SpeedMul` alto ou baixo. Exemplo real: Rafael trotando (`Control`) faz
~21 studs/s, o que já passa do limiar de **corrida** de Diego (12,1 × 1,35 =
16,3) — e ainda assim é trote, porque cada personagem é medido pela própria
base. Analógico meio inclinado cai numa faixa mais baixa e fica mais
silencioso; isso é proposital. Se mudar as velocidades do pacote, revise
`MovementBands`.

### Furtividade

Cada estado tem, em `GameConfig.Noise.States`, um par de faixas **invertidas**
(`Min` = o que vale com Furtividade 0, `Max` = com Furtividade 100). Quanto
maior a Furtividade, **menor o alcance** e **maior o intervalo**:

| Estado | Intensidade | Alcance (Furt. 0 → 100) | Intervalo (Furt. 0 → 100) |
| --- | --- | --- | --- |
| Agachado/rastejando | 1 | 26 → 0 studs | 2,6 → 5,0 s |
| Andar | 1 | 120 → 2 studs | 1,6 → 4,0 s |
| Trotar | 2 | 280 → 25 studs | 1,0 → 2,6 s |
| Correr | 3 | 560 → 120 studs | 0,7 → 1,8 s |

O que isso produz, com os personagens atuais:

| Personagem | Furtividade | Andar | Trotar | Correr |
| --- | --- | --- | --- | --- |
| Rafael Monteiro | 10 | 108 studs | 254 studs | 516 studs |
| Bruno Carvalho | 20 | 96 studs | 229 studs | 472 studs |
| Sofia Ribeiro / Camila Duarte | 57 | 53 studs | 135 studs | 309 studs |
| Diego Ferreira | 77 | 29 studs | 84 studs | 221 studs |
| Marina Albuquerque / Kevin Nakamura | 95 | **mudo** | 38 studs | 142 studs |

Ou seja: Marina e Kevin andam em silêncio de verdade e quase não denunciam
trotando, mas **correr sempre entrega alguém**; Rafael é ouvido de mais de
meio mapa correndo e faz barulho até andando. O atributo muda o resultado —
não é número de vitrine.

Um só cooldown vale para todos os estados de solo, e o intervalo consultado é
o do estado **atual**: trocar de ritmo no meio do passo não rende um ping de
graça, mas quem acelera para a corrida volta a fazer barulho na cadência da
corrida sem esperar a da caminhada terminar.

### Distância

`GameConfig.Noise.DistanceFalloff` desconta por distância, por ouvinte. Com
`t` = distância ÷ alcance:

- até `ClearFraction` (35%) do alcance, o Monstro ouve **sempre**, na posição
  certa;
- daí para a borda a chance cai até `EdgeChance` (22%), acelerando por
  `Exponent` (1,6);
- a posição chega deslocada de `NearSpread` (2 studs) até `EdgeSpread`
  (34 studs), só no plano do chão.

Isso se combina com a Furtividade sem nenhuma regra extra: Furtividade alta
encolhe o raio, então o mesmo Monstro passa a estar numa fração maior dele e
recebe pings **mais raros e mais imprecisos**. O círculo marca a região do
barulho, não o jogador.

### Ações (não dependem de Furtividade)

| Ação | Intensidade | Raio | Intervalo |
| --- | --- | --- | --- |
| Salto | 2 | 50 studs | mínimo 0,5 s |
| Aterrissagem de queda | 3 | 70 studs | mínimo 0,5 s |
| Pedra | 4 | 100 studs | mínimo 0,35 s |
| Pânico | 3 | raio do evento de medo | mínimo 0,35 s |

`MinimumIntensity = 1` é o piso; o limiar é inclusivo.
`MaxNoiseRadius = 700` limita todos os raios e precisa caber o alcance de
corrida da tabela acima.

Isso é classificação acústica por velocidade, sem criar um segundo estado
autoritativo de postura. Movimento acelerado por poderes também é barulhento.

Não basta falsificar `SprintIntent = false` para silenciar velocidade de
corrida. Stamina infinita também mantém o ruído. A física observada continua
sujeita ao modelo de network ownership do Roblox; este recurso não substitui
validação geral de teleporte/speed exploit.

O cooldown pertence a cada sobrevivente e não é zerado ao soltar/reapertar
sprint. Ele anda quando o **ruído acontece**, não quando alguém escuta — se
dependesse da entrega, a amostra de 10 Hz repetiria até o sorteio por
distância passar e o desconto não valeria nada. Não há pings agendados para o
futuro: a cada amostra elegível, a velocidade atual é verificada. Ao parar ou
reduzir a velocidade, a próxima amostra (até aproximadamente 0,1 s) já não
emite ping de corrida — parar de fazer barulho para os pings naturalmente.
Ondas de sons anteriores terminam sua animação normalmente.

Saltos e pousos usam transições do Humanoid, com a amostra da stamina como
complemento para estados breves/omitidos. Há pico de altura, tempo mínimo no
ar, queda mínima de 4 studs, proteção de spawn e exclusão de natação/assento/
escalada. A altura do RemoteEvent de dano de queda não alimenta a audição.

## Novas fontes de ruído

Em um módulo do **servidor**, após validar a ação:

```lua
local NoiseService = require(game.ServerScriptService.Server.NoiseService)

NoiseService:EmitNoise(player, impactPosition, 5)
-- Opcional: alcance específico em studs, ainda limitado por MaxNoiseRadius.
NoiseService:EmitNoise(player, impactPosition, 5, 120)
```

Sem raio explícito, vale `intensity * RadiusPerIntensity`. O retorno indica
se algum monstro recebeu o evento. Ações genéricas compartilham o limite de
0,35 s por sobrevivente, separado de passos/salto/pouso. A posição pode ser a
de um impacto distante, como uma pedra, e não precisa ser a raiz do jogador.
Não existe listener `NoiseDetected.OnServerEvent`.

## Por que nada aparecia nos testes

A cadeia estava certa ponta a ponta (RemoteEvent no lugar, `NoiseService` no
boot, hooks ligados, papéis corretos). O que faltava era conseguir **ver** e
**diagnosticar**:

1. **Teste solo entrega um papel só.** `GameConfig.Testing.SoloStart = true` e
   `RoleAssignment` dão exatamente um papel para o único jogador. Como Monstro
   não existe sobrevivente para fazer barulho; como Sobrevivente não existe
   Monstro para receber. Com um cliente, o sistema fica **corretamente** mudo —
   e parece quebrado. Resolvido por `GameConfig.Noise.Debug.SelfHear`.
2. **O `.rbxlx` de verificação não é o jogo.** `rojo build -o ...` gera um
   arquivo novo, sem a ilha salva e sem mundo gerado. Abrir esse arquivo no
   Studio dá a impressão de que o mapa sumiu, e a partida nem chega a ficar
   ativa — `RoundManager.IsRoundActive()` falso descarta todo ping. Use o build
   só para checar que compila; teste sempre no lugar original com `rojo serve`.
3. **Todo descarte era silencioso.** Sem partida, fora de alcance, intensidade
   baixa, sem Monstro vivo: tudo devolvia `false` sem dizer nada. Resolvido por
   `GameConfig.Noise.Debug.Verbose` e `NoiseService.Diagnose()`.
4. **O anel era fino demais para o cenário.** Um contorno de 2,5 px quase
   branco (`Color` 195/230/238) sobre céu, areia e névoa some. Agora cada onda
   tem um contorno escuro atrás do claro.
5. **A onda sumia inteira ao encostar na borda.** O booleano de
   `WorldToViewportPoint` vira `false` assim que o PONTO sai da tela, mesmo com
   metade do anel ainda visível. Agora a visibilidade usa `ViewportSize` mais
   `EdgeMarginPixels`.
6. **A ilha é gigante e o Monstro nasce sozinho, longe de todo mundo.** O
   raio de costa é `560`-`820` studs (`IslandLayout.CONFIG.CoastRadiusMin/Max`)
   e o Monstro sempre nasce numa caverna na base da montanha
   (`IslandGenerator.GenerateCave`, marcador `MonstroSpawn`), enquanto os
   Sobreviventes nascem espalhados pelos POIs do mapa inteiro. Num teste com 2
   jogadores "soltos", a distância real passa fácil de 500+ studs — muito além
   dos raios de então (25 studs andando, 80 correndo). Os alcances atuais já
   são dimensionados para essa ilha (até 560 studs correndo, ver a tabela de
   Furtividade acima), mas o Monstro continua nascendo longe. Resolvido por
   `GameConfig.Noise.Debug.IgnoreRadius` e pelo relatório de
   `NoiseService.Diagnose()`, que agora imprime, por sobrevivente, a
   Furtividade dele e o alcance, a cadência e a chance de cada estado.

## Diagnóstico

`GameConfig.Noise.Debug` — os três nascem `false` e devem ficar assim no jogo:

| Campo | Efeito |
| --- | --- |
| `SelfHear` | **Só no Studio** (`RunService:IsStudio()`). O próprio sobrevivente que fez o barulho também recebe o ping, então dá para validar servidor + remote + render correndo sozinho. Servidor e cliente checam a MESMA condição: em jogo publicado o eco não existe nem é aceito. |
| `IgnoreRadius` | **Só no Studio.** Ignora a distância: todo Monstro ativo recebe o ping não importa onde esteja no mapa. Existe porque o Monstro nasce isolado na caverna, longe de qualquer Sobrevivente — em teste normal a distância real (500+ studs) estoura qualquer raio configurado (25 a 80 studs), e por isso mesmo com tudo certo nada chegava. |
| `Verbose` | Loga cada ping entregue e cada descarte com o motivo (inclui a distância real e o alcance, e avisa quando `IgnoreRadius` entregou algo que estava fora do raio). A formatação só acontece com a flag ligada — o caminho de descarte é quente (10 Hz por jogador). |

Na Command Bar, durante um Play, para ver todos os filtros de uma vez:

```lua
require(game.ServerScriptService.Server.NoiseService).Diagnose()
```

Imprime `Enabled`, se a rodada está ativa, o estado das três flags e, por
jogador, `Role`, `InRound`, `Eliminado` e se ele conta como ativo. Se houver
Monstro e Sobrevivente ativos ao mesmo tempo, imprime também a **distância
real** entre cada par e, por sobrevivente, a **Furtividade** dele e — para
cada um dos quatro estados — o alcance, a cadência e a chance de o ruído
chegar daquela distância (`mudo` quando a Furtividade zerou o alcance, `fora`
quando a distância passou dele). É o jeito mais rápido de confirmar se "não
aparece nada" é distância, é Furtividade ou é outra coisa:

```
  distância Monstro2 <-> Sobrevivente1: 50 studs | Furtividade 57
    Crouch fora/11 a cada 4.0s
    Walk 66%/53 a cada 3.0s
    Jog 100%/135 a cada 1.9s
    Sprint 100%/309 a cada 1.3s
```

## Apresentação

`NoiseVisualizer` mantém a coordenada recebida e a projeta no `ScreenGui` do
Monstro com `Camera:WorldToViewportPoint`. Cada onda é um contêiner `Frame`
posicionado pela projeção, com um `UIScale` que cresce de 0,3 a 1,8 com
`TweenService` e três camadas dentro: `Halo` (preenchimento quase transparente),
um anel de contorno **escuro** e, por cima, o anel claro. O escuro é mais grosso
(`StrokeThickness + ShadowThickness`) e fica em ZIndex menor — é ele que faz o
efeito ler em céu, areia e névoa. A segunda onda começa 0,12 s depois e tudo é
destruído em 1,02 s. O limite local é de 24 pings simultâneos, removendo o mais
antigo se necessário.

A visibilidade não usa mais o booleano de `WorldToViewportPoint`: ela compara o
ponto com `Camera.ViewportSize` mais `EdgeMarginPixels` (120 px), para a onda não
desaparecer de uma vez quando o centro passa pouquinho da borda. Passando da
margem ela some de vez — não vira seta nem indicador de borda.

Por ser uma sobreposição 2D projetada, o efeito ignora oclusão e aparece sobre
paredes, árvores e pedras. O ponto continua sendo uma coordenada fixa do mundo:
acompanha o movimento da câmera durante seu curto tempo de vida, mas nunca segue
um personagem. Fora da tela ou atrás da câmera ele fica oculto, sem criar seta.
Não há nome, distância, outline ou acesso à posição posterior do sobrevivente.
Morte, remoção do personagem,
mudança de papel, eliminação e fim da rodada limpam os efeitos; callbacks da
segunda onda não recriam pings já removidos.

## Verificação

```sh
python3 tests/run_noise.py /caminho/para/luau
rojo build -o /tmp/meujogo-noise-check.rbxlx   # só checa que compila
```

> O `.rbxlx` acima é descartável. **Não abra ele no Studio**: é um lugar novo,
> sem a ilha salva. Teste sempre no arquivo original com `rojo serve`.

O teste executa os módulos reais de stamina, audição e visualização com
serviços simulados. Cobre filtros, limites de alcance, cadência, sprint sem
intenção, stamina infinita, velocidade por personagem, caminhada,
saltos/quedas, hooks, valores inválidos, cooldown individual, respawn, troca
de rodada, animações, teto de efeitos e limpeza. Compilação Luau e build
Rojo também foram executados.

Os testes antigos de medo e ciclo de partida não ficaram verdes: o primeiro
falha por ausência de `Enum.KeyCode` no simulador (reproduzido em HEAD antes
desta alteração); o segundo falha ao carregar dependências do `RoundManager`
ausentes no seu runner. Não foram alterados nesta tarefa.

### No Studio

**Sozinho (checagem rápida da cadeia):** ligue `GameConfig.Noise.Debug.SelfHear`
e `Verbose`, dê Play no lugar original, entre na partida e corra. As ondas
aparecem no seu próprio rastro e o Output mostra cada ping. **Desligue as duas
antes de publicar.**

**Com dois clientes:** o Monstro nasce sozinho numa caverna na montanha, longe
de qualquer Sobrevivente (a ilha tem 560-820 studs de raio) — ande até perto
um do outro ANTES de testar, ou ligue `GameConfig.Noise.Debug.IgnoreRadius`
(só Studio) pra não depender de estar perto. Se nada aparecer, rode
`require(game.ServerScriptService.Server.NoiseService).Diagnose()` na Command
Bar: ele imprime a distância real entre Monstro e Sobrevivente e diz se ela
cabe no raio configurado. **Desligue `IgnoreRadius` (e `SelfHear`/`Verbose`)
antes de publicar** — nenhum dos três deve ficar ligado no jogo real.

Na sala dev escolha Monstro e Sobrevivente, inicie a partida e teste sprint
dentro/fora de 80 studs, parar, agachar, pular e cair de uma plataforma;
caminhada dentro e fora de 25 studs. Confirme que somente o Monstro vê as
ondas, que elas ficam no lugar do som e
desaparecem depois de morte/fim da rodada. Lembre que a onda só é desenhada se
o ponto estiver na direção em que o Monstro olha — é 2D projetado, não bússola.

Atalho útil: o sprint da audição usa o MESMO critério do gasto de fôlego
(`GameConfig.Characters.SprintSpeedRatio`). Se a barra de stamina cai enquanto
você corre, a classificação de corrida está funcionando — o problema, se
houver, está do alcance para frente.
