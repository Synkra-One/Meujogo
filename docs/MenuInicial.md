# Tela inicial e menu principal

Tela de abertura no estilo *Friday the 13th* / *The Last of Us*: carregamento
rápido, "clique para começar" sobre uma cena 3D escura, e um menu com a coluna
de botões à esquerda deixando o monstro livre à direita.

Tudo é **local**. Nenhum RemoteEvent novo foi criado: o botão JOGAR usa os
mesmos remotes que a sala de espera já usava.

## Onde fica cada coisa

| Arquivo | Responsabilidade |
| --- | --- |
| `src/ReplicatedFirst/MenuBoot.client.luau` | LocalScript do fluxo (carregar → clicar → menu → jogar) |
| `src/ReplicatedFirst/Menu/MenuConfig.lua` | **Configuração central**: textos, cores, tempos, IDs, cena |
| `src/ReplicatedFirst/Menu/MenuTheme.lua` | Aparência e tweens (botões, painéis, vinheta, escala) |
| `src/ReplicatedFirst/Menu/MenuSounds.lua` | Áudio 2D do menu |
| `src/ReplicatedFirst/Menu/MenuScene.lua` | A cena 3D — **isolada** do resto |
| `src/ReplicatedFirst/Menu/MenuScreens.lua` | As telas e a navegação |
| `src/server/Tools/MenuSceneGenerator.lua` | Gerador opcional: cria a cena como peças reais editáveis no Explorer |

Fica em `ReplicatedFirst` porque é o único lugar que roda **antes** de o jogo
terminar de carregar: dá para tirar a tela azul padrão da Roblox
(`RemoveDefaultLoadingScreen`) e pôr a nossa no lugar.

> **Cuidado ao editar `MenuBoot`:** em `ReplicatedFirst` o `ReplicatedStorage`
> ainda não replicou. Nenhum módulo do jogo pode ser exigido no topo do arquivo
> — só dentro das funções, quando o jogador realmente clica. O
> `tests/run_menu.py` verifica isso.

## O que foi reaproveitado

| Em vez de criar | Usa o que já existe |
| --- | --- |
| Sistema de entrada na partida | `Remotes.WaitingRoom` + `WaitingRoomManager.Join` (o mesmo do pilar *IniciarPartida*) |
| Escolha de personagem | `Remotes.SelectCharacter` |
| Escolha de papel para teste | `GameConfig.Testing.DevRoleChooser` / `DevRoleUserIds`, validado por UserId no servidor |
| Travar movimento | `ControlModule:Disable()`, o mesmo caminho do `RoleRevealController` |
| Mensagens de recusa | `Remotes.LobbyMessage` → `LobbyMessageController` |

A **única** mudança no servidor foi aceitar a ação `"Join"` no remote que já
existia, para o botão JOGAR não obrigar o jogador a atravessar o lobby a pé.
Toda a validação (partida em andamento, vagas, duplicidade) continua dentro de
`WaitingRoomManager.Join`.

## Fluxo

1. **Carregamento** — no máximo **3 s** (`Loading.MaxSeconds`), saindo antes se
   o jogo já carregou e o mínimo de 0,9 s passou. Barra de progresso e dicas
   girando.
2. **Clique para começar** — logo + texto pulsando sobre a cena desfocada.
   Qualquer tecla, clique, toque ou botão de controle serve (movimento de
   mouse e roda são ignorados de propósito).
3. **Menu principal** — os botões entram escalonados, um de cada vez.
4. **JOGAR** — véu preto cobre a troca de câmera, o menu sai, a câmera e os
   controles voltam ao jogador, e o pedido de entrada na sala é enviado.

Os outros botões abrem painéis "EM BREVE" já navegáveis, todos com **VOLTAR**
(ou `Esc` / `B` no controle). Nenhum clique é aceito durante uma transição.

O menu **não volta ao morrer ou renascer** (`Flow.ReopenOnRespawn = false`) e o
`ScreenGui` tem `ResetOnSpawn = false`.

## Acesso rápido (só para você)

O botão **ACESSO RÁPIDO** aparece no topo do menu apenas para os UserIds em
`GameConfig.Testing.DevRoleUserIds`. Ele faz, de uma vez:

1. entra na sala (`"Join"`);
2. escolhe o primeiro personagem livre (`SelectCharacter`) — pula a tela de seleção;
3. define o papel escolhido (`"DevRole"`: Sobrevivente / Monstro / Espião / Aleatório);
4. marca **Pronto** (`"Ready"`), o que dispara a contagem.

Os passos são espaçados em 0,2 s porque o servidor recusa pedidos a menos de
0,15 s um do outro. **Segurança:** esconder o botão é só cosmético — quem valida
o UserId é o servidor. Se alguém forjar o pedido, entra na sala como qualquer
outro jogador e o papel forçado é ignorado.

Para liberar para outra conta, acrescente o UserId em
`GameConfig.Testing.DevRoleUserIds`.

## Como trocar cada coisa

Tudo em `src/ReplicatedFirst/Menu/MenuConfig.lua`. **Campo vazio = desligado**,
em silêncio, sem erro — nenhum ID foi inventado.

| O quê | Campo |
| --- | --- |
| **Logo** | `Brand.LogoImage = "rbxassetid://SEU_ID"` (vazio usa o título em texto) |
| **Nome do jogo** | `Brand.Title` / `Brand.Subtitle` |
| **Imagem de fundo** | `Background.Image` (vazio deixa a cena 3D aparecer) |
| **Música** | `Sounds.Music` + `MusicVolume` |
| **Sons dos botões** | `Sounds.Hover / Click / Back / Start` |
| **Modelo do monstro** | `Scene.MonsterSources` — ponha o caminho do seu modelo no topo da lista |
| **Animação do monstro** | `Scene.MonsterAnimationId` (vazio usa a respiração procedural) |
| **Câmera** | `Scene.CameraOffset`, `CameraLookAt`, `CameraFieldOfView`, `CameraDrift*` |
| **Cenário** | `Scene.SetSize`, `FloorColor`, `PropCount`, e a função `buildSet` em `MenuScene.lua` |
| **Clima** | `Scene.Fog / Rain / Embers` |
| **Cores** | `Palette` |
| **Tempos** | `Motion` |

### A cena 3D — editando no Explorer

Por padrão a cena é 100% desenhada por código, sem nada no Explorer. Se você
quiser **arrastar** paredes, luzes e a posição do monstro visualmente, rode o
gerador uma vez, **em modo de edição (sem Play)**, pela Command Bar:

```lua
local Menu = require(game.ServerScriptService.Server.Tools.MenuSceneGenerator)
Menu.Generate()
```

**Depois da primeira vez, `Menu.Generate()` sozinho não apaga mais nada** —
se `Workspace.MenuSceneSet` já existir, ele recusa e avisa no Output, pra
proteger as posições que você editou. Só apaga e recomeça do zero se você
confirmar explicitamente:

```lua
Menu.Generate({ Confirm = true })
```

Isso cria `Workspace.MenuSceneSet`, **tudo direto dentro dela, sem
subpastas** (paredes, chão, luzes, chuva, névoa, silhuetas de fundo — cada
peça é filha direta da pasta, pra você achar qualquer coisa de primeira no
Explorer). Três peças magenta funcionam como marcadores:

| Marcador | O que ele controla |
| --- | --- |
| `CameraAnchor` | onde a câmera do menu fica (bolinha; só a posição importa) |
| `CameraLookAt` | pra onde ela olha (bolinha; só a posição importa) |
| `MonsterMarker` | um **boneco** (torso, cabeça, braços, pernas, com uma seta apontando a frente) marcando onde o monstro fica em pé — selecione ele igual selecionaria qualquer NPC do mapa |

Mova qualquer um deles com a ferramenta Move do Studio, e **gire o
`MonsterMarker`** com Rotate (eixo Y) pra mudar pra onde ele olha — a seta
na frente do boneco mostra o rosto antes mesmo de girar. É o mesmo fluxo de
editar qualquer outra parte do mapa. **Salve o lugar (Ctrl+S)** depois — essa
geometria não é sincronizada pelo Rojo, fica salva direto no `.rbxlx`, igual
ao gerador da sala de espera (`AirportLobbyGenerator`).

**Isso atualiza em tempo real, com o Play já rodando** — não precisa parar e
recomeçar:

- Mover `CameraAnchor`/`CameraLookAt` reposiciona a câmera na hora.
- Mover/girar `MonsterMarker` reposiciona o monstro na hora.
- **Apagar `MonsterMarker` remove o monstro da cena na hora**; recriá-lo (ou
  desfazer com `Ctrl+Z`) traz ele de volta.
- Mover/pintar/apagar qualquer outra peça (parede, luz, prop) já é
  instantâneo por conta do próprio motor da Roblox — nenhum script observa
  isso, é conteúdo real do Workspace.

Por causa disso, `Workspace.MenuSceneSet` deixou de ser algo que cada jogador
clona pra si: agora é a MESMA geometria compartilhada (por isso o gerador
marca ela como `Persistent` — ver a seção de streaming abaixo). Os três
marcadores magenta também **não somem mais** durante o jogo — eles continuam
lá, sempre, pra você poder editar de novo a qualquer momento. Na prática
ninguém chega perto da cena durante uma partida de verdade (ela fica a
milhares de studs de tudo), mas ela deixou de ser estritamente "invisível
pros outros jogadores" como era antes.

`Menu.Generate()` **apaga e refaz do zero**: rode só uma vez e depois edite à
mão. Rodar de novo é só pra "resetar" tudo. `Menu.Clear()` remove a cena
inteira e volta pro código puro (o fallback nunca deixa de existir).

**Se mover `CameraAnchor`/`MonsterMarker` "não faz efeito" no Play:** o
projeto usa `Workspace.StreamingEnabled = true`, e a cena fica de propósito
muito longe de tudo — fora do raio de streaming, o cliente simplesmente não
recebe essa pasta durante o Play, e o script cai de volta nos números antigos
sem avisar. Rode uma vez:

```lua
local Menu = require(game.ServerScriptService.Server.Tools.MenuSceneGenerator)
Menu.FixStreaming()
```

Isso conserta o problema **sem apagar** nenhuma posição que você já ajustou.
Quem gerar a cena de agora em diante com `Generate()` já não precisa disso —
a correção já vem de fábrica.

Como o modelo do monstro é procurado (primeiro que existir vence):

```lua
MonsterSources = {
    "ReplicatedStorage/MenuMonster",  -- ponha o SEU aqui
    "Workspace/R6 Monster",           -- o que já existe no projeto
}
```

Se nenhum existir, entra uma silhueta provisória feita de `Part`s — a cena
nunca fica vazia e nenhum ID precisou ser inventado.

Duas garantias importantes do `MenuScene.lua`:

- **É tudo local.** As `Part`s são criadas no cliente, numa pasta só, a
  `(0, 6000, -9000)` — longe da ilha (|x|,|z| ≤ 960) e do lobby (z = −1500).
  Nada colide, nada aparece em raycast, ninguém mais vê.
- **Não mexe no `Lighting` global.** Escurecer o Lighting deixaria o *gameplay*
  deste cliente escuro também. Em vez disso a cena é montada dentro de uma
  caixa fechada e escura, iluminada só pelas luzes dela; a correção de cor e o
  desfoque ficam presos à **câmera** e somem com ela.

O modelo do menu não é controlável: âncorado, sem colisão, com
`EvaluateStateMachine = false` e sem scripts (eles são removidos do clone).

A cena **reassume a câmera todo frame** enquanto está ativa — o respawn no
lobby devolveria a câmera ao personagem e o menu "cairia" no lobby. Pelo mesmo
motivo os controles são desligados de novo a cada `CharacterAdded`.

## Como testar no Studio

```sh
rojo serve                     # ou: rojo build -o Meujogo.rbxlx
python3 tests/run_menu.py ~/.rokit/bin/luau
```

No Studio, conecte o plugin do Rojo e dê **Play**. Confira:

1. A tela de carregamento é a nossa (preta, com o nome do jogo), não a azul da
   Roblox, e some em no máximo 3 s.
2. A cena escura aparece com o monstro respirando ao fundo, chuva e névoa.
3. "CLIQUE OU PRESSIONE QUALQUER TECLA" pulsa; mexer o mouse **não** dispara.
4. Ao clicar, o desfoque abre e os botões entram um a um.
5. Passar o mouse acende o botão (barra, borda, texto e deslocamento).
6. Um submenu qualquer abre o painel "EM BREVE" com VOLTAR; `Esc` também fecha.
7. Clicar rápido duas vezes **não** abre dois painéis.
8. **JOGAR** escurece, devolve a câmera e você aparece no lobby, andando
   normalmente, já dentro da sala de espera.
9. Morrer/renascer **não** traz o menu de volta.
10. `Alt+F4`… quer dizer, **SAIR** pede confirmação e desconecta.

Para testar o responsivo: no Studio use *Device* (celular/tablet) na barra de
testes e gire para retrato — a coluna alarga e desce.

O Output não deve ter nenhum aviso do menu.

## Limites conhecidos

- **SAIR** desconecta o jogador (`Player:Kick`). A Roblox não tem API para
  fechar o aplicativo. Para esconder o botão: `Config.ShowQuitButton = false`.
- Os testes automatizados cobrem configuração, IDs de asset e a escala
  responsiva. Renderização, câmera, áudio e a cena 3D exigem playtest.
