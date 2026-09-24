# Náufragos — guia de entrada para quem vai desenvolver

Este documento explica o que é o jogo, como ele funciona, como o código está
organizado, como rodar tudo na sua máquina e o que ainda falta. Foi escrito
a partir do estado do repositório em **21/09/2026** (commit `aff4125`). Onde
algo é suposição ou não foi verificado, está dito.

> **Regra de ouro:** o código é a fonte da verdade. Os arquivos em `docs/`
> foram escritos junto com cada funcionalidade e alguns já estão defasados
> (por exemplo, um comentário no boot do servidor ainda fala em "fuga por
> barco", mas a fuga hoje é por helicóptero). Quando um doc e o código
> divergirem, confie no código e corrija o doc.

---

## 1. O que é o jogo

**Náufragos** é um jogo de terror multiplayer assimétrico para **Roblox**, no
estilo *Friday the 13th* / *Dead by Daylight*. De 2 a 10 jogadores caem numa
ilha à noite. Um deles é o **Monstro**; os outros são **Sobreviventes** e, a
partir de 3 jogadores, um deles é o **Espião** (um traidor disfarçado).

- **Sobreviventes** precisam achar 3 peças de um transmissor, montar a
  estação de rádio, pedir socorro e atravessar a ilha até um helicóptero de
  resgate — tudo isso enquanto o Monstro os caça.
- **Monstro** nasce sozinho numa caverna dentro da montanha, ouve os passos
  dos sobreviventes de longe, se teletransporta pelo mapa e mata.
- **Espião** parece um sobrevivente, mas sabota objetivos e tem uma habilidade
  letal rara. Os sobreviventes podem detectá-lo, amarrá-lo ou executá-lo.

O clima é de tensão: escuridão, medo que sobe quando o Monstro está perto,
lanterna com bateria, barulho que entrega a posição.

### Como uma partida termina

Definido em `src/server/RoundManager.lua` (o cabeçalho do arquivo explica tudo):

| Vencedor | Condição |
| --- | --- |
| **Sobreviventes** | o helicóptero decola com pelo menos um deles a bordo |
| **Monstro** | não resta nenhum Sobrevivente vivo (`GameConfig.Round.MonsterWinsAtSurvivorsAlive = 0`); o Espião não conta como Sobrevivente |
| **Espião** | o tempo acaba, ninguém escapou e ele ainda está vivo |
| **Ninguém (empate)** | o tempo acaba, ninguém escapou e o Espião já morreu — esse caso não foi especificado pelo dono do jogo; o código escolheu empate (fácil de trocar em `resolveTimeout()`) |

Uma partida dura **20 minutos**, em 4 fases (`GameConfig.Phases`):
**Queda** (30 s) → **Exploração** (6 min) → **Corrida** (12 min) →
**Desfecho** (90 s). O amanhecer chega nos últimos minutos (`GameConfig.DayNight`).

---

## 2. O ciclo completo do jogador

1. **Menu inicial** (`src/ReplicatedFirst/`) — tela de carregamento própria,
   "clique para começar", cena 3D escura com o monstro, botão **JOGAR**.
   Ver [MenuInicial.md](MenuInicial.md).
2. **Lobby** — um terminal de aeroporto abandonado, gerado por código.
   O jogador entra na fila pelo botão Jogar ou pelo prompt "Iniciar partida".
   Existe um estande de tiro/bancada com pistola de treino.
   Ver [LobbyAeroporto.md](LobbyAeroporto.md).
3. **Fila / preparação** (`WaitingRoomManager`) — estados
   `Lobby → Waiting → Selecting → Starting → Playing → Intermission/Returning`.
   Os jogadores escolhem skin/perk e marcam "Pronto".
4. **Sorteio de papéis** (`RoleAssignment`) — 1 Monstro, 1 Espião (se ≥ 3
   jogadores), o resto Sobrevivente. A tela de revelação é
   `client/RoleRevealController`.
5. **Seleção de sobrevivente** (30 s) — o jogador escolhe um dos 7
   personagens (exclusivo: dois jogadores não podem ter o mesmo). O Monstro
   recebe o Jason automaticamente. Ver [SelecaoSobreviventes.md](SelecaoSobreviventes.md).
6. **Partida** — todos são levados à ilha; as 4 fases correm.
7. **Resultado** — tela de resultados com XP ganho, nível da conta, estatísticas
   da partida; depois todos voltam ao lobby após ~10 s.

---

## 3. As mecânicas principais

### 3.1 Os sobreviventes (7 personagens)

Definidos em `src/ReplicatedStorage/Modules/CharacterData.lua`. Cada um tem
**7 atributos** (0–100) que somam **exatamente 350 pontos** — ninguém é
melhor no total, só distribui diferente (há um `assert` que impede o jogo de
carregar se a soma estiver errada):

Velocidade · Stamina · Compostura (vida/absorção de dano) · Furtividade
(barulho e medo) · Reparo (dificuldade dos minigames) · Força (dano causado) ·
Sorte (loot das caixas).

Cada personagem tem **2 poderes** (Q e E, com cooldown), implementados em
`server/SurvivorPowerSystem.lua`. Detalhes em
[PoderesSobreviventes.md](PoderesSobreviventes.md).

| Personagem | Papel | Poderes |
| --- | --- | --- |
| Rafael Monteiro — O Atlético | corredor | Rajada Final, Salto Longo |
| Diego Ferreira — O Engenheiro | reparo | Conserto Relâmpago, Armadilha Improvisada |
| Marina Albuquerque — A Caçadora | combate | Tiro Certeiro, Instinto de Caçadora |
| Kevin Nakamura — O Sorrateiro | furtivo | Manto de Sombras, Passo Fantasma |
| Sofia Ribeiro — A Médica | suporte | Adrenalina de Emergência, Escudo Protetor |
| Bruno Carvalho — O Forte | tanque | Investida Brutal, Postura Inabalável |
| Camila Duarte — A Sortuda | sorte | Golpe de Sorte, Intuição Sortuda |

### 3.2 O Monstro (Jason, "O Predador da Caverna")

Nasce no ninho da caverna (marcador `MonstroSpawn`), 20% maior que um jogador
(escala 1,2) e ~16% mais rápido. Habilidades:

| Tecla | Habilidade | Onde | Doc |
| --- | --- | --- | --- |
| Botão esquerdo | Golpe em cone (34 de dano, 3 golpes matam) | `MonsterCombat` | [Monstro.md](Monstro.md) |
| E | Grab — agarra e executa um sobrevivente | `GrabService` | [Grab.md](Grab.md) |
| F | Shadow Rush — vira fumaça e corre a 75 studs/s por 5 s | `ShadowRush` | [ShadowRush.md](ShadowRush.md) |
| Q | Teleporte — abre o mapa da ilha, clica, entra numa fenda e emerge no destino | `MonsterTeleport` | [TeleporteMonstro.md](TeleporteMonstro.md) |
| R | Apagão do Abismo — grito de escuridão: +35 de medo e lanternas bloqueadas por 12 s num raio de 150 | `AbyssBlackout` | [ApagaoDoAbismo.md](ApagaoDoAbismo.md) |

Passivos: **super audição** (recebe "pings" onde os sobreviventes fazem
barulho — [SuperAudicao.md](SuperAudicao.md)) e **fraqueza à luz** (fica lento
e fraco perto de tochas, lanternas e zonas seguras — `MonsterLightWeakness`).

### 3.3 O Espião

Aparece com 3+ jogadores. Detalhes no cabeçalho de cada arquivo:

- **Sabotagem** (`SabotageSystem`): cooldown 20–30 s; um sobrevivente precisa
  voltar e "Reparar".
- **Habilidade letal** (`LethalAbility`): alcance 8 studs, cooldown 180 s.
- **Confronto** (`ConfrontSystem`), as 3 formas de lidar com um suspeito:
  detectar (Cristal Ancestral) → amarrar (2 jogadores cooperando, 5 s,
  amarrado por 90 s) → executar (Lança Ancestral, item único nas Ruínas).

### 3.4 Sistemas que afetam todo mundo

- **Medo (Fear)** — barra 0–100 que sobe quando o Monstro está perto e desce
  longe dele; afeta stamina, tropeços e efeitos visuais/sonoros.
  [Fear.md](Fear.md), `server/FearSystem.lua`, regras puras em `FearRules.lua`.
- **Stamina e movimento** — sprint gasta fôlego e faz barulho. O movimento
  inteiro (andar, trotar, correr, agachar, rastejar, queda) vem de um pacote
  de terceiros adaptado, o *Ultimate R6 Movement System*. [MovementPack.md](MovementPack.md).
- **Ruído** (`NoiseService`) — estado de movimento × furtividade × distância
  decidem se o Monstro recebe um ping.
- **Lanterna** — tem bateria; **V** dá um "disparo concentrado" que atordoa o
  Monstro por 2 s. [Lanterna.md](Lanterna.md), [FlashBurst.md](FlashBurst.md).
- **Itens** (`ItemRegistry.lua`) — Antena, Bateria, Transmissor (peças do
  rádio), Lanterna, Tocha, Chocolate, Bandagem, Gasolina, Taco de Beisebol
  (item inicial), Chave inglesa, Pé de cabra, Sinalizador, Lança Ancestral.
  Espalhados pelo mapa por `Tools/ItemSpawner` e em caixas
  (`LootCrateSystem`, afetado pela Sorte).
- **Armas de fogo** — só a **Glock17** (Digital's OTS Patch2) está ativa; as
  outras 8 armas do pacote foram removidas e estão em `Sistema de armas/` e
  `WeaponAssets_backup/`. [PistolaOTS.md](PistolaOTS.md), [CombateParte1.md](CombateParte1.md).
- **Reparo de precisão** — minigame de timing (3 acertos seguidos) usado em
  instalar peça, ligar gerador, ativar painel e consertar sabotagem; errar faz
  barulho. [ReparoMinigame.md](ReparoMinigame.md).

### 3.5 O objetivo principal: rádio → resgate

Seis passos na estação de rádio (torre com gerador, abrigo e rack), depois a
extração. O passo a passo completo está em [Radio.md](Radio.md) e
[Extracao.md](Extracao.md):

```
3 peças espalhadas pelo mapa → instalar no rack (minigame)
→ abastecer o gerador (gasolina) → pegar fusível e encaixar
→ ligar o gerador (minigame; faz MUITO barulho) → ativar o painel (minigame)
→ enviar socorro (14 s canalizando)
→ contagem de 120 s: nasce zona de pouso na praia com fumaça vermelha
→ helicóptero pousa → embarcar → alguém escolhe PARTIR AGORA → vitória
```

Concluir o rádio **não ganha** a partida: até o helicóptero decolar o Monstro
ainda pode virar o jogo.

### 3.6 O mapa

Ilha de ~1400–1600 studs, gerada **proceduralmente por código** (seed fixa),
com floresta densa, trilhas, lago e vários pontos de interesse: Acampamento,
Cabanas, Lago, Campo (celeiro), Torre de vigia, Farol, Vila Nativa, Ruínas,
Caverna do Monstro, Estação de Rádio, **Estação Abismo** (laboratório
subterrâneo com o "Frog Generator", do lado oposto da ilha em relação à
montanha) e destroços de um avião caído. Ver [Mapa.md](Mapa.md),
[Caverna.md](Caverna.md), [EstacaoAbismo.md](EstacaoAbismo.md).

### 3.7 Progressão da conta

Cada partida rende XP (`MatchRewardsConfig` + `MatchRewardService`); o XP total
vira nível (`LevelSystem`, 1–100) e é salvo em DataStore por delta
(`DataStoreManager`), para nunca perder progresso mesmo com dois servidores.
[ProgressaoDaConta.md](ProgressaoDaConta.md).

---

## 4. Tecnologia e ferramentas

| Item | O que é |
| --- | --- |
| **Plataforma** | Roblox (Roblox Studio) |
| **Linguagem** | **Luau** (o Lua tipado do Roblox). A maioria dos arquivos usa `--!strict` |
| **Sincronização** | **Rojo 7.7.0** — os arquivos em `src/` viram instâncias no Studio (`default.project.json`) |
| **Gerenciador de ferramentas** | **Rokit** (`rokit.toml` instala o Rojo) |
| **Testes** | Scripts Luau/Python/Ruby rodando *fora* do Roblox, com serviços simulados (`tests/robloxstub.luau`) |
| **Idioma do projeto** | Português (comentários, docs, textos de UI). Identificadores misturam PT e EN |

Extensões usadas no repositório:

- `*.lua` — módulos (ModuleScript). `*.server.luau` / `*.client.luau` — Scripts /
  LocalScripts. `*.model.json` — instâncias simples (é assim que os RemoteEvents
  existem).
- `*.rbxmx` — modelos XML. O pacote de movimento inteiro (`src/MovementPack/`)
  e alguns rigs vivem assim; o código dentro deles está em XML e é editado com
  cuidado (ver [MovementPack.md](MovementPack.md)).

### Como rodar na sua máquina

```sh
# 1. instalar as ferramentas (uma vez)
rokit install            # instala o Rojo 7.7.0

# 2. abrir o mundo no Studio
#    ATENÇÃO: leia a seção 6 sobre o arquivo do lugar (.rbxlx) antes.
rojo build -o Meujogo.rbxlx     # gera um lugar só com o código
# abra Meujogo.rbxlx no Roblox Studio e conecte o plugin do Rojo:
rojo serve

# 3. testes (o Luau vem do Rokit)
python3 tests/run_menu.py ~/.rokit/bin/luau
ruby    tests/run_match_tests.rb ~/.rokit/bin/luau
```

---

## 5. Estrutura do repositório

```
default.project.json     mapeia src/ -> serviços do Roblox (o "mapa" do Rojo)
src/
  server/                ServerScriptService.Server — toda a lógica autoritativa
    init.server.luau     BOOT: liga cada sistema com safeInit(), na ordem certa
    Tools/               geradores do mundo (ilha, lobby, rádio, caverna...) — só em modo de edição
  client/                StarterPlayerScripts.Client — HUD, input, efeitos visuais
  ReplicatedStorage/
    Modules/             código compartilhado: GameConfig, CharacterData, ItemRegistry, Remotes...
    Remotes/             RemoteEvents (*.model.json), um arquivo por remote
    WeaponAssets/        armas do pacote OTS
    SelectionAssets/     pastas para arte da tela de seleção (ainda vazias)
  ReplicatedFirst/       menu inicial (roda antes do jogo carregar)
  MovementPack/          pacote de movimento de terceiros, fatiado em .rbxmx
  StarterGui/            HUDs
  ServerStorage/, Workspace/, StarterPlayer/   modelos (monstro, personagem, lanterna)
docs/                    ~30 guias, um por sistema
tests/                   testes standalone (Luau + runners Python/Ruby)
tools/                   plugins e scripts pontuais de Studio/Python (rig, Meshy, validações)
```

Pastas na raiz que **não** são código do jogo (materiais de trabalho):
`Arczis animations/`, `Sistema de armas/`, `WeaponAssets_backup/` (pacotes
`.rbxm` originais de terceiros), `ShiftUnlocked-main/` (biblioteca de
shift-lock, referência), `Imagens/`, `Itens_inventario/`, `models/` (GLB do
monstro Meshy), `backups/`, `recovered/` (um `.rbxl` recuperado do servidor).

### Os arquivos que você mais vai abrir

| Arquivo | Por quê |
| --- | --- |
| `Modules/GameConfig.lua` | **Todo o balanceamento** (~1200 linhas, só dados). Comece por aqui para entender os números |
| `server/init.server.luau` | A lista completa de sistemas e a ordem em que ligam |
| `server/RoundManager.lua` | Fases, vitória, fim de partida |
| `server/WaitingRoomManager.lua` | Fila, seleção, início da partida |
| `Modules/CharacterData.lua` | Os personagens e a regra dos 350 pontos |
| `Modules/Remotes.lua` | **Contrato de toda a comunicação cliente↔servidor** |
| `Modules/ItemRegistry.lua` + `ToolFactory.lua` | Itens do jogo |
| `Modules/AssetRegistry.lua` | IDs de sons/modelos (muitos ainda `rbxassetid://0`) |

---

## 6. Como o código é organizado (convenções que você precisa seguir)

1. **Servidor manda, cliente pede.** O cliente só envia intenção (ex.:
   `MonsterAttack:FireServer()`); alcance, cooldown, dano e morte são
   decididos no servidor. Nunca confie em dados vindos do cliente.
2. **Um módulo por sistema**, cada um com `Init()`. Em `init.server.luau`
   todo sistema é ligado via `safeInit(nome, módulo)`, que isola falhas: um
   sistema quebrado avisa no Output e os outros continuam. A **ordem** importa
   (comentada no arquivo).
3. **Tudo balanceável fica em `GameConfig.lua`**, não espalhado no código.
4. **Estado replicado por Attributes** (`Role`, `InRound`, `Eliminado`,
   `Fear`, `Amarrado`, `Sabotado`...) — qualquer script lê sem precisar de um
   remote novo.
5. **Lógica pura separada** (`FearRules`, `ShadowRushRules`, `CombatRules`,
   `FlashlightRules`...) para poder ser testada fora do Roblox.
6. **Remotes**: criar um remote novo = criar o arquivo `.model.json` em
   `src/ReplicatedStorage/Remotes/` **e** documentar o contrato em
   `Modules/Remotes.lua`. Se o arquivo não estiver sincronizado, o `Remotes.lua`
   dá erro e derruba quase tudo que depende dele.
7. **`ReplicatedFirst` roda antes de o resto replicar**: no menu, não dê
   `require` de módulos do jogo no topo do arquivo, só dentro de funções.
8. **Reaproveite antes de criar.** Os docs listam repetidamente "o que foi
   reaproveitado"; a base evita sistemas duplicados (um único dono para
   `WalkSpeed`, um único dono para `FieldOfView`, etc.).
9. **Padrão dos docs:** ao fechar uma funcionalidade, escreva/atualize o
   `docs/<Sistema>.md` com arquivos, números, como testar no Studio e limites
   conhecidos.

### O mundo NÃO é gerado no Play

Isto é a coisa mais importante para trabalhar em dupla. Os geradores em
`src/server/Tools/` (ilha, lobby, rádio, caverna, estação Abismo, cena do
menu, spawner de itens) usam `InsertService` para baixar modelos do Toolbox, e
isso só funciona em **modo de edição**. Por isso o fluxo é:

1. Em modo de edição, rodar na Command Bar cada gerador uma vez (o comando
   exato aparece no aviso `[Boot]` do Output se algo estiver faltando).
2. **Salvar o lugar (Ctrl+S).** O mapa passa a fazer parte do arquivo do lugar.
3. Daí em diante, todo Play só usa o que já está salvo.

Consequência direta: **o mundo (Ilha, Lobby, Estação Abismo, cena do menu)
vive no arquivo do lugar, não nos scripts.** O `Meujogo.rbxlx` está no
`.gitignore`, e o `rojo build` gera um lugar **sem mapa**. A única cópia de
lugar rastreada pelo Git é `recovered/server_roblox_2026-09-10_005240.rbxl`, um
snapshot de servidor de 10/09 (não verifiquei se ele contém a ilha, nem se está
atualizado em relação ao código). Outra forma de ver o mapa é entrar no lugar
publicado no Roblox / Team Create do dono. Ver seção 8 (primeiros passos).

---

## 7. Estado atual: o que existe e o que falta

### Pronto e funcionando (segundo os testes e os docs)

Loop completo de partida (fila → papéis → seleção → ilha → fases → resultado →
lobby); 7 sobreviventes com poderes; Monstro com golpe, grab, shadow rush,
teleporte, apagão e super audição; Espião com sabotagem, letal e confronto;
objetivo do rádio de 6 passos e extração por helicóptero; medo, stamina,
ruído, lanterna com disparo concentrado; loot, caixas, pistola; minigame de
reparo; menu inicial; lobby de aeroporto; mapa gerado com 10+ POIs; XP, nível
persistente e tela de resultados.

### O que falta para ficar completo

**A. Arte e áudio (quase tudo é placeholder)**
- **Sons:** músicas das 4 fases, morte, amarrado, arremesso de pedra, batida de
  coração e o loop do gerador estão em `rbxassetid://0`
  (`AssetRegistry.Sounds`). Também estão vazios os sons de entrada/saída/passe
  do Shadow Rush e os de batimento e respiração do Fear
  (`GameConfig.Fear.HeartbeatSoundId` / `BreathingSoundId`). O Apagão já tem
  som, mas suas animações (`CastAnimationId`, `VictimAnimationId`) estão vazias.
- **Ícones:** todos os ícones de itens (`ItemIcons.Map`) e de poderes estão
  vazios; a UI mostra letra/glifo no lugar.
- **Animações:** faltam `GrabAttempt` e `VictimGrab` do Grab, animação do
  Shadow Rush, e a maioria dos poderes usa a locomoção padrão. O golpe do
  Monstro usa uma animação pública genérica (`SwingAnimationId`).
- **Menu:** logo, música e imagem de fundo vazios. Os botões
  **Personagens, Loja, Inventário, Configurações e Créditos** abrem só um
  painel "EM BREVE".
- **Modelo do Monstro:** existe uma versão Meshy (`docs/MonstroMeshy.md`) e o
  R6 padrão; não verifiquei qual é a definitiva. Tela de seleção sem modelos
  3D próprios (`SelectionAssets/` vazias — usa R6 neutro).

**B. Conteúdo e sistemas**
- **Loja / cosméticos / inventário persistente** — o DataStore já prevê
  cosméticos, mas não há interface nem itens à venda.
- **Só 1 arma de fogo** e poucas armas corpo a corpo; só **1 Monstro**
  (Jason) — `MonsterCharacters` está pronto para receber mais.
- **Estado "Derrubado"** (sobrevivente caído, antes da morte) não existe.
- **Punição por executar um inocente** (`ConfrontSystem.PunicaoInocente`) é um
  gancho que ninguém escuta.
- **A Estação Abismo** está construída e tem o "Frog Generator", mas não achei
  um objetivo de gameplay ligado a ela — confirme com o dono do jogo qual é o
  papel dela na partida.
- **Documentação defasada** em alguns pontos (ex.: `CombateParte1.md` diz que a
  recarga da pistola está desligada, enquanto `GameConfig.Firearms` e o
  `AmmoSystem` implementam reserva e recarga).

**C. Balanceamento e qualidade — nunca validados com gente de verdade**
- Vários docs terminam com "exige playtest": curva de nível
  (`LevelSystem`: `BaseXP = 150`, `GrowthExponent = 1.35`, "não passou por
  playtest real"), medo, alcance dos pings, dificuldade do minigame, duração
  das fases, etc.
- Renderização, áudio, câmera e multiplayer só podem ser validados no Studio
  com **Server & Clients** (4+ jogadores). Os testes automáticos cobrem regras
  e servidor, não visual.

**D. Limpeza antes de publicar** — flags de desenvolvimento ainda ligadas em
`GameConfig.Testing`:
- `SoloStart = true` (permite iniciar sozinho), `DevRoleChooser = true` +
  `DevRoleUserIds` (painel para escolher o papel; **adicione o UserId do seu
  amigo aqui** para ele usar o "Acesso rápido" do menu),
- `GiveTestWeapons = { "Glock17" }` (todo mundo nasce armado),
  `ItemsNearSpawn = true`, `LobbyPistol = true`,
- as 3 peças do rádio nascem **ao lado do gerador** "para teste rápido"
  ([Radio.md](Radio.md)), quando o desenho do jogo é espalhá-las pelo mapa,
- `Fear.DebugMode`, `Noise.Debug.*` devem ficar `false` no jogo final.

**E. Publicação (não verificado)** — não há nada no repositório sobre ícone,
descrição, thumbnail, monetização, moderação de áudio ou publicação da
experiência. Assumo que ainda não foi feito; confirme.

### Estado dos testes (rodei todos em 21/09/2026)

**16 de 22** runners passam. Os 6 que falharam:

| Runner | Causa observada |
| --- | --- |
| `run_fear`, `run_match_stats`, `run_shadow_presentation` | o `luau-compile` do Rokit não reconhece `--null` (problema de versão/ambiente, não de código do jogo) |
| `run_airport_lobby`, `run_firearms` | o *harness* de teste não carrega módulos novos que o código passou a exigir (`AssetRegistry`, `FlashlightRules`) — teste desatualizado |
| `run_match_tests.rb` | termina com código de erro após vários `PASS`; não investiguei |

Nenhum desses falhou por causa de um bug de jogo confirmado, mas **também não
foram corrigidos**; é um bom primeiro trabalho.

---

## 8. Primeiros passos recomendados

1. **Combinar uma fonte única do mundo.** O mapa não é gerado a partir dos
   scripts no Play; ele está salvo no arquivo do lugar. Pergunte ao dono como
   ele mesmo abre o lugar (arquivo local, Team Create ou lugar publicado) e
   use o mesmo caminho. Sugestão (não implementada): **Team Create**, com o
   Rojo sincronizando só o código. Sem isso, o amigo pode ver uma ilha vazia,
   desatualizada (como o snapshot de `recovered/`) ou diferente da sua.
2. **Assets do Roblox.** Sons/modelos/animações usados hoje estão publicados
   na conta do dono. Áudio e animação precisam ser públicos ou pertencer à
   experiência para carregar em outras contas; se o jogo for de um **grupo**,
   suba os assets para o grupo.
3. **Acesso ao repositório**: `https://github.com/Synkra-One/Meujogo`
   (organização). Convide o amigo; a branch é `main` e o histórico é curto
   (8 commits, mensagens genéricas — vale combinar uma convenção e usar
   branches por funcionalidade).
4. **Peso do repositório.** O `.git` já tem ~90 MB, com `.rbxl` recuperado,
   GLB e imagens. Avalie mover binários grandes para fora do Git ou usar LFS.
5. **Ler, nesta ordem:** este arquivo → `GameConfig.lua` → `init.server.luau` →
   `RoundManager.lua` → `Radio.md` + `Extracao.md` → `Monstro.md` → o doc do
   sistema em que for mexer.
6. **Rodar o jogo com 2+ jogadores no Studio** (Test → Server & Clients) e
   jogar uma partida inteira uma vez, como Monstro e como Sobrevivente.
7. **Primeiras tarefas seguras:** consertar os 6 runners de teste; trocar os
   `rbxassetid://0` de som; ícones de itens; preencher os painéis "EM BREVE"
   do menu; revisar docs defasados.

### Dúvidas que só o dono do jogo pode responder

- Qual é a visão final: jogo público no Roblox? Grupo ou conta pessoal?
- Qual o papel da Estação Abismo na partida?
- O modelo Meshy do Monstro é o definitivo?
- Haverá mais Monstros/mapas/personagens, loja e monetização?
- Qual a meta de jogadores por servidor (hoje 2–10)?
