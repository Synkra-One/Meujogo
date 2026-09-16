# Shadow Rush

Mobilidade do monstro: **F**, **L1** ou botão touch **Sombra**. Pressionar novamente inicia a materialização. O teclado mantém WASD e a direção relativa à câmera; controle e touch usam o `ControlModule` existente. Soltar o movimento freia, e curvas/reversões têm inércia.

## Sequência e balanceamento

Todos os valores ficam em `src/ReplicatedStorage/Modules/GameConfig.lua`, tabela `GameConfig.Monster.ShadowRush`.

| Parâmetro | Inicial | Efeito |
| --- | --- | --- |
| ShadowRushEnterDuration | 0.45 s | Dissolução, sem movimento/ataque |
| ShadowRushDuration | 5 s | Janela máxima de deslocamento |
| ShadowRushMaxSpeed | 75 studs/s | Velocidade horizontal permitida pelo servidor |
| ShadowRushAcceleration | 0.25 s | Limite de aceleração |
| ShadowRushTurnResponse | 0.16 s | Suavização da direção; maior = mais inércia |
| ShadowRushExitDeceleration | 0.2 s | Frenagem até zero |
| ShadowRushMaterializeDuration | 0.45 s | Corpo reaparece progressivamente |
| ShadowRushRecovery | 0.8 s | Imóvel/sem atacar após materializar |
| ShadowRushCooldown | 25 s | Contado a partir da ativação aceita |
| ShadowPassDistance | 12 studs | Distância ao trecho percorrido pela sombra |
| ShadowPassFear | 8 | Pontos finais de Fear |
| ShadowPassCooldown | 6 s | Por sobrevivente, por ativação; padrão permite uma vez |
| FOVOffset | 24° | 70 → 94° proporcional à velocidade (sprint normal usa 90°) |

Estados: `Idle → EnteringShadow → ShadowRush → Materializing → Recovery → Idle`. O cancelamento normal pelo botão passa pela materialização/Recovery; `ShadowRush.Cancel(player)` é uma interrupção externa imediata com restauração. Morte, fim de round, respawn, saída, mudança de papel, amarração, erro e timeout usam a mesma limpeza. Luz/tocha impede a entrada e força materialização se enfraquecer o monstro durante o rush.

## Integração

- O padrão segue `MonsterTeleport`: módulo de servidor com `Init()`, configuração central, RemoteEvent registrado em `Remotes`, Attributes replicados e bloqueios consultados pelos sistemas existentes.
- `ShadowRushBusy` bloqueia ataque, teleporte, armas/itens e alterações de movimento do pacote, incluindo shift-lock e watchdog. As animações normais param durante a habilidade.
- O servidor ancora temporariamente o root e calcula os deslocamentos. Nenhuma posição ou velocidade do cliente é aceita. A intenção horizontal é validada, limitada e vinculada ao token da ativação; sem input recente, a habilidade freia.
- Colisão usa `Blockcast` do volume vertical do personagem em subpassos de até 1.25 studs, raycast de chão e `GetPartsInPart` no destino. Água, inclinações acima do limite, precipícios e limites de `IslandLayout.CONFIG.AreaHalf` bloqueiam o avanço. O volume continua de pé durante a sombra para conservar espaço de materialização.
- A sobreposição é verificada separadamente porque o sweep não detecta peças já sobrepostas no início, conforme a [referência de WorldRoot do Roblox](https://create.roblox.com/docs/reference/engine/classes/WorldRoot).
- A geometria original do mapa continua sendo respeitada. Colisores incorretos das árvores são um problema separado: esta habilidade não os apaga nem os atravessa.
- O gasto de sprint é suspenso durante a habilidade. A regeneração continua pelas regras de stamina existentes; não há uma segunda barra.
- Shadow Pass chama **`FearSystem.AddFear(survivor, ShadowPassFear, "ShadowRush")`**. O teto e a validade do Fear continuam no módulo original. Há teste de distância ao segmento percorrido, linha de visão e cooldown individual. O Espião permanece fora do Fear, conforme a API existente. Não há dano de contato ou dano direto da habilidade.
- O cliente só apresenta corpo/VFX/input. `Crouching` continua sendo o dono do FOV e compõe o atributo local `ShadowRushFOV`; não há outro loop sobrescrevendo `Camera.FieldOfView`, blur ou camera shake contínuo.

## Visual, animações e áudio

`ShadowRushVFX.lua` cria uma silhueta baixa de três formas escuras deformadas, fumaça de curta duração, trail escuro, seis pontos de dissolução no corpo e emissão convergente ao materializar. O comprimento visual, trail e emissão respondem à velocidade real publicada pelo servidor. A base segue o chão por raycast. A paleta é quase preta, sem luz emissiva ou explosão colorida.

Os efeitos observam Attributes também para clientes que chegam tarde ou recebem o personagem por streaming. O `handle.Destroy()` restaura exatamente as transparências e emissores originais, desconecta listeners e destrói Parts, Attachments, partículas, trails, sounds e tracks próprios. O loop cliente e o HUD são únicos, não criados a cada ativação.

Na mesma tabela de configuração, preencher com IDs autorizados do projeto:

```lua
ShadowRushEnterAnimationId = "", -- animação R6 de dissolução
ShadowRushExitAnimationId = "",  -- animação R6 de materialização
ShadowRushEnterSoundId = "",    -- espacial, início
ShadowRushLoopSoundId = "",     -- espacial, loop durante deslocamento
ShadowRushExitSoundId = "",     -- espacial, retorno
ShadowPassSoundId = "",         -- somente o sobrevivente próximo
```

Formato: `"rbxassetid://SEU_ID"` ou o ID numérico dentro de uma string. Nenhum ID de animação/som foi inventado. **Com campos vazios não há áudio**; para testar o counterplay sonoro, é necessário colocar os sons. `SoundVolume` e `SoundMaxDistance` controlam volume/alcance. A única textura usada nos emissores é a fumaça nativa do Roblox.

## Arquivos

Criados:

- `src/server/ShadowRush.lua` — autoridade, movimento, colisão, estados, Fear e limpeza.
- `src/client/ShadowRushController.client.luau` — input, HUD, FOV via atributo e observadores.
- `src/ReplicatedStorage/Modules/ShadowRushRules.lua` — validação e matemática de movimento/proximidade.
- `src/ReplicatedStorage/Modules/ShadowRushVFX.lua` — apresentação e restauração visual.
- `src/ReplicatedStorage/Remotes/ShadowRush.model.json` — canal de pedidos/feedback.
- `tests/run_shadow_rush.py`, `tests/shadow_rush.luau` — testes com os módulos reais e serviços simulados.
- `docs/ShadowRush.md` — este documento.

Modificados:

- `src/ReplicatedStorage/Modules/GameConfig.lua`, `Remotes.lua`.
- `src/server/init.server.luau`, `MonsterCombat.lua`, `MonsterTeleport.lua`, `StaminaSystem.lua`, `MonsterLightWeakness.lua`, `OTSFirearmService.lua`, `UtilityItemSystem.lua`, `WeaponSystem.lua`.
- `src/client/MonsterController.client.luau`, `MonsterTeleportController.client.luau`, `MovementWatchdog.client.luau`.
- `src/MovementPack/StarterCharacterScripts/Crouching.rbxmx`, `CustomShiftLock.rbxmx`, `Animate.rbxmx`.

## Validação automatizada

```sh
python3 tests/run_shadow_rush.py /caminho/para/luau
python3 tests/run_fear.py /caminho/para/luau
python3 tests/run_fear_presentation.py /caminho/para/luau
```

Resultados locais: compilação Luau (incluindo os três scripts XML de movimento), testes de Shadow Rush, Fear e apresentação passaram. A suíte de armas falha em `Reload consumes only existing reserve, exactly once`; a mesma falha foi reproduzida removendo apenas os novos bloqueios de ShadowRush do código carregado no teste, sem alterar os arquivos do projeto.

Os testes de Shadow Rush exercitam os módulos reais com serviços/colisões simulados: autoridade, input inválido, token, cooldown, ataques bloqueados, integração com Fear real, múltiplos jogadores, stamina, parede fina, rampa, precipício, água, overlap, borda, lag, input perdido, cancelamento nas fases, morte, fim de round, respawn, mudança de papel, amarração, fraqueza, erro, duração e 25 ciclos de VFX sem conexões/objetos vivos acumulados. Também verificam a transparência ao cancelar no meio da entrada.

**Pendente de Studio:** multiplayer real, colisão com as meshes/voxel terrain da ilha, sensação de controle/latência e revisão visual renderizada. O acesso automatizado ao Studio retornou `cgWindowNotFound`; testes simulados e `rojo build` não comprovam esses itens.

## Roteiro de playtest

1. Sincronize pelo Rojo, pare o Play anterior e abra uma sessão de servidor com pelo menos dois clientes. Inicie um round pelo fluxo normal: um Monstro e um Sobrevivente.
2. Use F com o Monstro. Observe a entrada de 0.45 s, controle com WASD, curvas, parada ao soltar direção, frenagem e reaparecimento. No outro cliente, verifique corpo dissolvido, sombra rente ao terreno, ausência de corpo correndo e materialização gradual.
3. Tente atacar, usar arma/item e abrir Q durante entrada, rush, materialização e Recovery. Só libere o ataque depois de `ShadowRushBusy` desaparecer. Repita F na entrada e no meio do rush.
4. Passe a menos de 12 studs do Sobrevivente. Verifique `Player.Fear` no servidor: impulso de 8, sem perda de HP; a proximidade normal do Fear pode somar ganho adicional. Repita na mesma ativação: sem spam. Separe os jogadores por uma parede: sem Shadow Pass.
5. Teste de frente e em diagonal contra paredes finas, troncos, portas fechadas, rochas, rampas, desníveis, praia/água e borda. A sombra deve frear e permitir desviar; não deve atravessar nem saltar o obstáculo.
6. Durante cada fase, teste morte, reset do personagem e fim de round. Para interrupção técnica, na **Command Bar do servidor**: `require(game.ServerScriptService.Server.ShadowRush).Cancel(game.Players:FindFirstChild("NOME_DO_MONSTRO"))`. Confira aparência, movimento, colisões, FOV, ataque e estado Idle; a eliminação continua dona do bloqueio de personagens eliminados.
7. Teste com latência de rede e perda de input. O servidor deve frear após 0.35 s sem direção recente. Como o movimento é autoritativo, o steering sofre a latência real da conexão; calibre após esse teste.
8. Repita ativações e respawns. No servidor, `ShadowRushQuery` existe somente durante uma sessão. Em cada cliente, `Workspace.ShadowRushVFX` fica vazio após terminar; nenhum loop sonoro/track de habilidade deve continuar. HUD e conexão global de apresentação são únicos.
9. Com os IDs de som preenchidos, verifique som espacial dos três momentos e impacto privado do Shadow Pass. Ajuste fumaça/trail pelo `ParticleRate`/`TrailLifetime` e avalie no dia e à noite, inclusive perto de árvores e paredes.
