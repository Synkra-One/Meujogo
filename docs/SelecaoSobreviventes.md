# Seleção cinematográfica de sobreviventes

A tela usa uma floresta noturna feita com elementos nativos, um sobrevivente R6 de corpo inteiro em `ViewportFrame`, uma faixa horizontal de sete ícones e um painel de informações. Não há imagens externas novas, assets da Toolbox ou alteração do corpo utilizado na partida. Os placeholders são construídos localmente quando não existe um modelo importado.

## Análise do projeto e fluxo preservado

- `src/client/CharacterSelectController.client.luau` e `StarterGui/CharacterSelectUI.model.json`: preparação anterior à seleção (skin, perk, papel de teste e pronto). Essa preparação foi preservada.
- `src/client/SurvivorSelectionController.client.luau`: tela exclusiva da fase de seleção; substituiu a grade grande de cards.
- `src/server/WaitingRoomManager.lua`: sala → revelação dos papéis → seleção → início da rodada. A seleção usa o prazo absoluto do servidor, com duração de 30 segundos definida em `SurvivorSelectionConfig`.
- `src/server/CharacterStatsApplier.lua`: aceita `SelectCharacter("Select", id)`, `"Confirm"` e `"Sync"`. Valida participante, papel, fase, prazo, ID, disponibilidade e reserva. O cliente não fornece atributos. Escolhas tentativas podem coincidir; a primeira confirmação reserva o personagem.
- Ao expirar o prazo, o servidor confirma a escolha existente. Se não houver escolha ou houver conflito, encontra um sobrevivente livre. A rodada começa antecipadamente quando todos confirmam.
- `src/server/RoundManager.lua`, `LobbyManager.lua` e `CharacterPresentation.lua`: preparação, transporte e criação dos personagens da rodada. Não foram alterados por esta reformulação.
- `src/ReplicatedStorage/Modules/CharacterData.lua`: elenco, nomes, funções (`Apelido`), atributos, passivas, poderes e cooldowns; agora também concentra os campos visuais de cada sobrevivente.
- `docs/PoderesSobreviventes.md`: referência das descrições curtas Q/E. `AssetRegistry.SurvivorPowers` continua fornecendo nomes de exibição e ícones dos poderes para seleção e HUD.
- Rigs existentes: `rigR6.rbxmx` → `Workspace.R6 novo`; `src/StarterPlayer/StarterCharacter.rbxmx` → `ServerStorage.GameCharacter`; `src/Workspace/R6Monster.rbxmx` → referências do monstro. Nenhum desses modelos é modificado pela seleção.
- `default.project.json`: mantém os mapeamentos Rojo existentes e acrescenta `ReplicatedStorage.SelectionAssets`. Módulos de cliente continuam em `StarterPlayerScripts.Client`.
- Entrada existente: botões Roblox para mouse/toque/controle, Enter e ButtonX para confirmação, integração `CursorLivre` com o shift-lock. A nova tela adiciona setas e X de teclado, preserva Enter/ButtonX e restaura cursor/foco ao fechar.

## Arquivos desta implementação

Alterados/reformulados:

- `default.project.json` — somente o mapeamento adicional de `SelectionAssets` nesta tarefa.
- `src/ReplicatedStorage/Modules/CharacterData.lua` — metadados de apresentação; números e campos anteriores preservados.
- `src/ReplicatedStorage/Modules/SurvivorSelectionConfig.lua` — configurações globais, sons, disponibilidade e compatibilidade com retratos anteriores.
- `src/client/SurvivorSelectionController.client.luau` — layout adaptável, entrada, sincronização e confirmação.
- `src/client/SurvivorCard.lua` — ícones compactos, escala e estados.
- `src/client/SurvivorPortrait.lua` — modelos isolados e enquadramento por proporção e bounding box.
- `tests/survivor_selection.luau` — amplia os cenários do servidor: conflito real, bloqueio após confirmação, rejeição de monstro e escolha explícita no timeout.

Adicionados:

- `src/ReplicatedStorage/Modules/SurvivorSelectionState.lua` — regras puras de apresentação e cálculo da câmera.
- `src/client/SurvivorSelectionTheme.lua` — componentes visuais compartilhados.
- `src/client/SurvivorSelectionAssets.lua` — resolução de referências de assets.
- `src/client/SurvivorBackdrop.lua` — floresta, luz difusa, névoa e vinheta nativas; suporte a imagem futura.
- `src/client/SurvivorPreview.lua` — troca suave, movimento sutil e limpeza da prévia.
- `src/client/SurvivorDetails.lua` — descrição, Q/E, cooldowns, barras e passivas.
- `src/ReplicatedStorage/SelectionAssets/{PreviewModels,CharacterIcons,AbilityIcons,Backgrounds,Sounds,IdleAnimations}/init.meta.json` — seis pastas preservadas pelo Rojo.
- `tests/run_survivor_selection_ui.py` e `tests/survivor_selection_ui.luau` — cenários do controlador com serviços simulados.
- Este guia.

## Onde colocar os assets futuros

| Asset | Pasta no Explorer | Campo de configuração |
| --- | --- | --- |
| Modelo 3D | `ReplicatedStorage.SelectionAssets.PreviewModels` | `CharacterData.Characters[…].PreviewModel` |
| Ícone de personagem | `ReplicatedStorage.SelectionAssets.CharacterIcons` | `Icon`, ou o mesmo nome de `PreviewModel` quando `Icon = ""` |
| Ícone de poder | `ReplicatedStorage.SelectionAssets.AbilityIcons` | `PowerIcon1` / `PowerIcon2`; sem override, usa `AssetRegistry.SurvivorPowers[id].Icon` |
| Fundo individual | `ReplicatedStorage.SelectionAssets.Backgrounds` | `Background` no personagem |
| Fundo global | mesma pasta | `SurvivorSelectionConfig.Background` |
| Som | `ReplicatedStorage.SelectionAssets.Sounds` | `SurvivorSelectionConfig.Sounds.Hover/Select/Confirm/Countdown` |
| Idle | `ReplicatedStorage.SelectionAssets.IdleAnimations` | `IdleAnimation`, ou o mesmo nome de `PreviewModel` |

As pastas correspondem a `src/ReplicatedStorage/SelectionAssets/` no disco. Modelos podem ser salvos como `.rbxm` ou `.rbxmx`. Para persistir no repositório um asset adicionado no Studio, exporte-o para a pasta correspondente; a sincronização Rojo não é um salvamento automático de edições do Studio.

Referências de imagem aceitam `rbxassetid://…` diretamente, ou o nome de um `StringValue` (ID no `Value`), `Decal` (`Texture`) ou `ImageLabel` (`Image`). Sons aceitam ID ou nome de `Sound`; animações aceitam ID ou nome de `Animation`. Campo vazio mantém o placeholder/fallback e não baixa arte nova.

Exemplo de ícone persistido em `CharacterIcons/RafaelOficial.model.json`:

```json
{
  "className": "StringValue",
  "properties": { "Value": "rbxassetid://SEU_ID" }
}
```

Para trocar modelo e ícone com **uma referência**:

1. Coloque um `Model` chamado `RafaelOficial` em `PreviewModels`.
2. Coloque um ícone chamado `RafaelOficial` em `CharacterIcons`.
3. Em Rafael, altere `PreviewModel = "RafaelOficial"` e mantenha `Icon = ""`.
4. Inicie um novo Play: o mesmo nome resolve o modelo e o ícone automaticamente. Opcionalmente, uma `Animation` com esse nome em `IdleAnimations` também é encontrada.

É possível usar nomes/IDs independentes preenchendo `Icon` e `IdleAnimation` explicitamente. A antiga pasta `ReplicatedStorage.SurvivorPreviewRigs` continua funcionando como fallback de compatibilidade.

O modelo deve estar orientado para a frente do Roblox (−Z), ter peças visíveis e `Archivable = true`. Sua posição no arquivo não importa: a cópia é centralizada. Scripts e sons embutidos são removidos da cópia antes da exibição; as peças não colidem nem participam de raycasts. A animação opcional precisa ser compatível com o rig e autorizada para a experiência. O enquadramento deixa margem para movimento discreto; animações que estendem muito os membros devem ser verificadas no Studio.

## Como adicionar um sobrevivente

Adicione uma entrada em `CharacterData.Characters`, seguindo uma das sete existentes:

- `Id` único e estável, `Nome`, `Apelido`, `Description` e `ThemeColor`.
- Os sete `Stats`, cada um entre 0 e 100, somando exatamente 350. O módulo valida esse orçamento ao carregar.
- `PowerId1/2`, `PowerName1/2`, `PowerCooldown1/2` e `PowerDescription1/2`. Reutilize poderes existentes; um poder novo também precisa de implementação/validação em `SurvivorPowerSystem` e registro em `AssetRegistry.SurvivorPowers`.
- `PreviewModel`, `Icon`, `Background`, `IdleAnimation` e ícones dos poderes são referências opcionais de apresentação.
- `Availability = "Available"`, `"Locked"` ou `"Unavailable"`. Overrides globais continuam disponíveis em `SurvivorSelectionConfig.Availability`.

A faixa e a navegação são montadas a partir do elenco; nenhum nome precisa ser adicionado ao controlador. `Role` mantém seu significado mecânico original (por exemplo, `"Monstro"`); o título visual é `Apelido`.

## Como testar no Studio

1. Rode `rojo serve default.project.json` e conecte a experiência pelo fluxo Rojo já utilizado. Alternativamente, rode `rojo build default.project.json -o /private/tmp/Meujogo-survivor-selection.rbxlx` e abra o arquivo gerado.
2. Inicie Play, entre na sala de espera e marque Pronto. Em teste solo, use o modo solo já configurado no projeto e o papel Sobrevivente, quando a opção de desenvolvedor estiver disponível. A tela aparece depois da revelação do papel; o Monstro não escolhe um sobrevivente.
3. Passe o mouse pelos sete ícones: modelo, nome, descrição, poderes e barras devem mudar, sem marcar uma escolha. Clique em um ícone, passe o mouse em outro e confirme: o personagem confirmado deve ser o clicado.
4. Teste setas, Enter e X. No controle, use direcional/analógico esquerdo para foco, A para escolher e X para confirmar; o analógico direito rola os detalhes. Também é possível navegar até o botão e pressionar A.
   Depois de escolher um sobrevivente, o botão mostra `PRONTO`. Clique nele para confirmar sua escolha; com um único jogador, a partida começa nesse momento. Com vários jogadores, começa assim que todos estiverem `PRONTO`, sem esperar o restante do cronômetro.
5. No emulador de dispositivos, teste celular em retrato e paisagem, tablet e desktop. Toque para escolher; deslize a faixa horizontal quando necessário e role o painel de informações. Atributos e poderes permanecem no painel, inclusive em telas pequenas. Verifique também recortes de tela e barra superior.
6. Confira o corpo inteiro, iluminação e transição de cada placeholder. Se importar um rig muito largo/alto ou uma animação, verifique o enquadramento novamente.
7. Com múltiplos clientes, escolha o mesmo sobrevivente em dois clientes antes de confirmar. O primeiro reserva; o outro deve receber a indicação de conflito e poder escolher outro. Após confirmar, alterações ficam bloqueadas.
8. Deixe o tempo chegar a zero com uma escolha feita: o servidor deve preservá-la. Repita sem escolher: o servidor atribui um personagem livre. Confirme com todos antes do prazo e verifique o início antecipado e o transporte normal.
9. Encerre e reabra a rodada: não deve haver escolha residual, telas duplicadas, viewport antigo ou cursor preso. Teste saída de participante durante a seleção, seguindo a regra já existente de retorno à sala.

## Verificações automatizadas e limites

```sh
python3 tests/run_waiting_room.py
python3 tests/run_survivor_selection_ui.py
python3 tests/run_survivor_powers.py
rojo build default.project.json -o /private/tmp/Meujogo-survivor-selection.rbxlx
```

Os cenários de servidor, controlador e poderes passaram, e o projeto foi compilado pelo Rojo. Os testes do controlador exercitam hover, clique/toque via `Activated`, confirmação autoritativa, conflitos, bloqueio, reabertura, setas rápidas, limpeza e prazo. O cálculo de câmera foi verificado com 320 projeções de cantos de modelos em cinco proporções de viewport. Os módulos Luau alterados também passaram pela compilação de sintaxe.

Os serviços e componentes visuais são simulados nesses testes; eles não comprovam aparência, áudio, renderização 3D, navegação nativa por controle ou toque em dispositivo real. A validação visual no Studio continua pendente: o controle de aplicativos não estava disponível nesta sessão. As duas imagens citadas no pedido também não estavam presentes entre os anexos acessíveis; a composição segue a descrição textual.

Referência de implementação: a separação entre fundo e área interativa respeita as [áreas seguras de ScreenGui](https://create.roblox.com/docs/reference/engine/classes/ScreenGui), e a prévia usa [ViewportFrame](https://create.roblox.com/docs/reference/engine/classes/ViewportFrame).
