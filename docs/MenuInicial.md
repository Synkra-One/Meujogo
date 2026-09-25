# Tela inicial e menu principal

O menu mantém o cenário 3D, agora com **Rafael Monteiro**. A interface usa
carvão, marfim e âmbar, botões arredondados, setas animadas e cliques discretos.
**ENTRAR** é a ação principal; **CRÉDITOS** fica no canto inferior direito.
**Acesso rápido** e **Sair** foram removidos, inclusive seus handlers.

## Fluxo

1. Carregamento próprio com barra e dicas (mínimo 0,9 s, máximo 3 s nessa etapa).
2. Logo e convite para começar; clique, tecla, toque ou controle continuam.
3. Botões entram em sequência: ENTRAR, PERSONAGENS, LOJA, INVENTÁRIO e CONFIGURAÇÕES.
4. ENTRAR cobre a troca de câmera com um fade e libera câmera, controles e HUD
   no lobby do aeroporto. **Não entra automaticamente na fila**.

Os submenus e os créditos continuam com o conteúdo provisório “EM BREVE”.
VOLTAR, Escape ou B fecham o painel. Um painel aberto bloqueia os botões
por trás e devolve o foco à origem ao fechar. Respawn não reabre o menu.

## Arquivos

| Arquivo | Responsabilidade |
| --- | --- |
| `src/ReplicatedFirst/MenuBoot.client.luau` | Carregamento, entrada no lobby e restauração dos controles |
| `src/ReplicatedFirst/Menu/MenuConfig.lua` | Textos, cores, sons e configuração da cena |
| `src/ReplicatedFirst/Menu/MenuTheme.lua` | Botões, painéis, animações e medidas responsivas |
| `src/ReplicatedFirst/Menu/MenuScreens.lua` | Telas, créditos no rodapé, foco e navegação |
| `src/ReplicatedFirst/Menu/MenuSounds.lua` | Áudio local e limite de frequência do hover |
| `src/ReplicatedFirst/Menu/MenuScene.lua` | Rafael, câmera, cenário e marcadores do editor |
| `src/server/Tools/MenuSceneGenerator.lua` | Gerador opcional de cenário editável |

O menu vive em `ReplicatedFirst`. Nenhum módulo de `ReplicatedStorage` deve
ser exigido no topo desses arquivos: o conteúdo ainda pode estar replicando.
A aparência do Rafael é resolvida quando `CharacterData` chega, sem bloquear
a tela inicial. O menu não cria remotes nem envia comandos de fila/papel.

## Rafael e o cenário existente

`Scene.CharacterId = "RafaelMonteiro"` resolve o perfil em `CharacterData`.
O modelo vem primeiro de `SelectionAssets/PreviewModels`, usando o nome
`PreviewModel` do perfil; depois tenta `SurvivorPreviewRigs` e os caminhos em
`Scene.MonsterSources`. Sem modelo próprio, usa a mesma aparência R6 da tela
de seleção: pele, camiseta azul, calça escura e rosto. Assets que chegam
depois durante a replicação atualizam a apresentação local.

O clone é limpo antes de entrar no Workspace: sem scripts, sons, colisão,
toque ou raycast. A respiração e o balanço são sutis. A apresentação não muda
o personagem selecionado nem o avatar real do jogador.

Se `Workspace.MenuSceneSet` existe, o menu preserva essa geometria e acompanha
seus marcadores ao vivo. Os nomes `MonsterMarker` e as opções `Monster*` foram
mantidos por compatibilidade com cenas já montadas:

| Marcador | Função |
| --- | --- |
| `CameraAnchor` | Posição da câmera |
| `CameraLookAt` | Alvo da câmera |
| `MonsterMarker` | Posição e direção do Rafael |

O boneco rosa e as bolinhas são **guias de edição**. Durante o jogo, ficam
ocultos apenas no cliente (`LocalTransparencyModifier`); não são apagados.
Mover/girar o boneco reposiciona Rafael. Apagar o marcador remove Rafael;
recriá-lo traz o personagem de volta. As demais peças continuam editáveis.

Na ausência de `MenuSceneSet`, o menu usa o cenário procedural com chuva,
névoa e cinzas. Ele fica longe do mapa, em `Scene.Origin`. Correção de cor e
desfoque pertencem à câmera; o `Lighting` global não é alterado.

## Editar a cena no Studio

Na Command Bar, **em modo de edição**, e salve o lugar depois:

```lua
local Menu = require(game.ServerScriptService.Server.Tools.MenuSceneGenerator)
Menu.Generate()
```

`Generate()` recusa quando já existe uma cena, protegendo as edições.
`Generate({ Confirm = true })` apaga e reconstrói deliberadamente.
`Menu.Clear()` remove a cena editável e devolve o cenário procedural.

Se uma cena antiga não aparecer durante o Play por causa de streaming:

```lua
local Menu = require(game.ServerScriptService.Server.Tools.MenuSceneGenerator)
Menu.FixStreaming()
```

Isso torna o modelo persistente sem apagar posições. `Menu.UpdateLighting()`
aplica as cores/luzes atuais sem mover a cena. A geometria editada no Studio
fica salva no lugar, não é sincronizada pelo Rojo.

## Personalização

Tudo em `MenuConfig.lua`:

- `Palette`, `Fonts`, `Motion`: cores, fontes e tempos.
- `MainButtons`: navegação da coluna; `Credits`: botão separado do rodapé.
- `Sounds`: volumes e velocidades diferentes para Hover, Click, Back, Start e Enter.
  São usados arquivos embutidos da Roblox; string vazia desliga o som.
- `Brand`: nome/logo, subtítulo e versão; `Background.Image`: fundo 2D opcional.
- `Scene`: personagem, câmera, respiração, iluminação e clima.

O canvas compensa `UIScale` para manter o rodapé nos cantos reais. Em retrato,
a coluna ocupa a largura disponível e a legenda do personagem é ocultada.
Em telas baixas, alturas e espaços diminuem para preservar o rodapé.

## Validação

```sh
python3 tests/run_menu.py ~/.rokit/bin/luau
rojo build -o /tmp/Meujogo-menu.rbxlx
```

Os testes cobrem sintaxe dos módulos, configuração, escala, separação do
rodapé, navegação, foco, troca de câmera, Rafael, chegada tardia de assets e
ocultação dos marcadores. Não simulam a renderização nem a reprodução de áudio do Roblox.

No Studio, conferir após sincronizar o Rojo:

1. Rafael aparece no lugar do guia rosa; cenário e câmera editados permanecem.
2. Hover, seleção com controle, clique e VOLTAR têm feedback visual/sonoro.
3. Só ENTRAR, PERSONAGENS, LOJA, INVENTÁRIO e CONFIGURAÇÕES ficam na coluna.
4. CRÉDITOS permanece embaixo à direita, inclusive ao girar o celular.
5. Painéis bloqueiam cliques por trás, fecham e restauram o foco.
6. ENTRAR libera o lobby normalmente; morrer não traz a tela inicial de volta.
