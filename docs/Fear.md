# Fear — partes 1, 2 e 3

Somente sobreviventes vivos com `InRound = true`, numa rodada ativa e após fechar a seleção de personagem, acumulam Fear. Monstro, Espião, lobby e eliminados ficam em zero. A morte, remoção/troca do personagem e início/fim de rodada zeram o valor e o tempo de recuperação. Eliminação continua válida após respawn pelo sistema existente.

## Arquivos e integração

- `src/server/FearSystem.lua`: estado privado, atributo replicado `Player.Fear`, API de servidor, lifecycle e debug. Uma conexão Heartbeat para todos; `Init()` repetido não duplica conexões. As conexões do corpo são desconectadas na morte/remoção e as do jogador na saída. Observadores de respawn permanecem enquanto o jogador estiver conectado.
- `src/server/FearRules.lua`: curvas de ganho/recuperação/stamina/chances e estados, sem serviços ou conexões.
- `src/ReplicatedStorage/Modules/GameConfig.lua`: a mesma seção `GameConfig.Fear` com todo o balanceamento.
- `src/server/StaminaSystem.lua`: aplica a penalidade de regeneração pela API do Fear. Continua dono da stamina, com máximo e gasto intactos.
- `src/MovementPack/StarterCharacterScripts/Crouching.rbxmx`: respeita o limite temporário do tropeço no cálculo de velocidade e bloqueia sprint enquanto durar.
- `src/ReplicatedStorage/Modules/StatScaling.lua`: duas funções de resistência/recuperação que leem `Stat_Compostura` por `StatScaling.Of`, na escala existente 0–100. Nenhum atributo de Compostura foi criado ou alterado.
- `src/server/init.server.luau`: inicia FearSystem pelo `safeInit` existente.
- `tests/fear.luau` e `tests/run_fear.py`: testes determinísticos dos módulos reais com serviços Roblox simulados.

## Balanceamento

Valores iniciais em `GameConfig.Fear`: teto 100, zona de perigo de 160 studs, ganho base máximo 3,5/s até 20 studs, recuperação base 3,5/s após 4 segundos seguros, atualização a cada 0,2s. A distância é 3D entre HumanoidRootParts. Usa o monstro vivo mais próximo, sem somar vários monstros. Paredes bloqueiam o bônus de visão; o ganho base por proximidade permanece.

**O Fear é uma barra que sobe com o tempo, nunca um estouro.** Ver o monstro não enche a barra: encher exige ficar perto por vários segundos. `MaxFearDistance` é a fronteira dos dois regimes -- dentro dela a barra sobe, fora dela (passado o atraso) ela desce.

A curva é `t = clamp((160 - distância) / (160 - 20), 0, 1)`, `x = t ^ ProximityCurveExponent`, ganho base `3,5 * x² * (3 - 2x)`. O expoente inicial é 1,4. A curva não tem degraus e sua inclinação chega suavemente a zero nos limites.

| Distância | base/s | com visão | perseguido | 0 → 100 perseguido |
| --- | ---: | ---: | ---: | ---: |
| 160+ | 0 | 0 | 0 | nunca (recupera) |
| 120 | 0,278 | 0,376 | 0,526 | ~190s |
| 100 | 0,780 | 1,053 | 1,474 | ~68s |
| 80 | 1,524 | 2,057 | 2,880 | ~35s |
| 60 | 2,389 | 3,226 | 4,516 | ~22s |
| 40 | 3,156 | 4,260 | 5,964 | ~17s |
| 20 ou menos | 3,500 | 4,725 | 6,615 | ~15s |

Referências de ritmo com Compostura média: parado a 20 studs com linha de visão, 0 → 100 leva **~21s**; sendo perseguido colado, **~15s**; no pior caso possível (Compostura 0 + visão + perseguição, limitado por `MaxFearGainPerSecond`), **~12,5s**. Longe da zona de perigo, 100 → 0 leva **~29s**. Descer é de propósito mais lento que subir sob perseguição -- correr em círculos não apaga a tensão.

**Histórico:** o alcance era 300 studs com ganho base de 10/s e expoente 2. Isso somava duas queixas: colado no monstro a barra enchia em ~5s (parecia ir direto ao máximo), e como *quase a ilha inteira* contava como zona de perigo, era possível acumular medo lentamente sem nunca recuperar.

`ComposureGain` varia de 1,5 a 0,55, com `ComposureGainExponent = 0.93` (Compostura 50 ≈ 1x). `ComposureRecovery` varia de 0,65 a 1,35, com expoente 1 (Compostura 50 = 1x). A normalização e o fallback neutro usam a mesma escala dos demais atributos. A Parte 2 não reaplica Compostura sobre stamina/chances; os efeitos dependem somente do Fear já calculado.

Em 160 studs ou mais, conta o atraso de recuperação. Reentrar em menos de 160 reinicia os 4 segundos, mesmo com ganho muito pequeno. Sem monstro vivo, também recupera após o atraso. Somente a fração do tick posterior ao atraso recupera, usando o tempo real decorrido.

## Teste no Studio

Pare o Play, aguarde a sincronização do Rojo e inicie outra sessão. Ative `GameConfig.Fear.DebugMode = true` no arquivo ou use a Command Bar **do servidor durante o teste**:

```lua
require(game.ReplicatedStorage.Modules.GameConfig).Fear.DebugMode = true
```

O Output do servidor mostra `[Fear]` a cada 2 segundos (`DebugPrintInterval`), com jogador, Fear, Compostura, distância, ganho/s e estado/taxa de recuperação. No Explorer do servidor, `Players > jogador > Attributes > Fear` também mostra o valor. Não existe HUD de Fear nesta parte.

Use uma sessão local **Server & Clients com 4 jogadores** para comparar dois sobreviventes. O sorteio atual reserva um Monstro e um Espião: com só 2 jogadores não sobra sobrevivente; no Play solo de sobrevivente não existe monstro para gerar proximidade.

Como o lobby atual restringe quem pode abrir a sala, este comando de teste usa a API existente para colocar os quatro jogadores na sala e define os papéis de teste. Execute no servidor, com todos carregados e antes de iniciar a partida. As alterações desta sessão desaparecem ao parar o teste:

```lua
assert(game:GetService("RunService"):IsStudio(), "Somente Studio")
local config = require(game.ReplicatedStorage.Modules.GameConfig)
local room = require(game.ServerScriptService.Server.WaitingRoomManager)
local players = game.Players:GetPlayers()
assert(#players == 4, "Inicie o teste local com 4 jogadores")
table.sort(players, function(a, b) return a.Name < b.Name end)
config.Testing.SoloStart = true
config.Testing.ForceRole = nil
config.Testing.DevRoleChooser = true
config.Fear.DebugMode = true
for index, player in players do
    room.Join(player, true)
    player:SetAttribute("DevForceRole", if index == 1 then config.Roles.Monster
        elseif index == 2 then config.Roles.Spy else config.Roles.Survivor)
end
```

1. Clique **Pronto** nas quatro janelas. O primeiro jogador será Monstro, o segundo Espião e os outros dois Sobreviventes.
2. Após o sorteio, nos dois sobreviventes escolha **Camila Duarte** (Compostura 10) e **Sofia Ribeiro** (96). Feche também a seleção do Espião.
3. Aproxime o monstro, sem atacar: teste aproximadamente 160, 100, 60 e 20 studs. Confirme as distâncias no Output. À mesma distância, Camila deve acumular mais rápido que Sofia.
4. Afaste o monstro além de 160 studs. Fear para de subir e só cai após 4 segundos; Sofia recupera mais rápido. Retorne ao alcance antes dos 4 segundos para confirmar que o atraso reinicia.
5. Reinicie/mate o personagem e confira Fear zero. Eliminados não voltam a ganhar Fear após respawn. Ao terminar a rodada, todos voltam a zero.

Para comparar à distância exata sem dirigir o monstro, pode ancorar temporariamente a raiz dele e reposicioná-lo pela Command Bar do servidor. Mude `distance` e execute novamente (os sobreviventes devem estar próximos entre si e longe de obstáculos):

```lua
local config = require(game.ReplicatedStorage.Modules.GameConfig)
local monster, survivor
for _, player in game.Players:GetPlayers() do
    if player:GetAttribute("Role") == config.Roles.Monster then monster = player end
    if player:GetAttribute("Role") == config.Roles.Survivor then survivor = player end
end
assert(monster and survivor and monster.Character and survivor.Character, "Inicie a partida primeiro")
local distance = 40 -- altere para 20, 50, 100, 200 ou 350
local root = monster.Character.HumanoidRootPart
root.Anchored = true
root.CFrame = survivor.Character.HumanoidRootPart.CFrame + Vector3.new(distance, 0, 0)
```

Desmarque `Anchored` no HumanoidRootPart do Monstro pelo Explorer do servidor quando terminar, ou pare a sessão de teste.

## API preparada para próximas partes

Somente scripts do servidor:

```lua
local Fear = require(game.ServerScriptService.Server.FearSystem)
local current = Fear.GetFear(player)
Fear.AddFear(player, 10, "DeadBody") -- exemplo futuro; cadáveres NÃO foram implementados
Fear.ReduceFear(player, 5)
```

`AddFear` recebe pontos finais, já ponderados pela fonte. Não aplica Compostura duas vezes. O argumento `source` está reservado para futuras fontes; ainda não altera o cálculo. Uma adição positiva reinicia o atraso de recuperação, inclusive no teto. Valores negativos, infinitos e NaN são ignorados. A API valida elegibilidade e limita o resultado; editar o Attribute Fear não altera a tabela interna do servidor.

## Verificação automatizada

```sh
python3 tests/run_fear.py /caminho/para/luau
rojo build -o /tmp/meujogo-fear-part2.rbxlx
```

Cobertura: continuidade/monotonicidade, resistência existente, ganho e recuperação, atraso e retorno da ameaça, tick parcial, limites, autoridade, papéis/lobby/seleção/eliminação, monstro mais próximo, ausência de monstro vivo, morte/respawn/saída, reset da rodada, inicialização idempotente e frequência de debug. Os testes simulam serviços e não substituem a execução multiplayer no Studio.

## Parte 2 — regras de gameplay

Todos os campos abaixo foram adicionados à configuração existente, sem outro serviço de Fear:

| Regra | Valores iniciais |
| --- | --- |
| LOS | Raycast a cada 0,4s, multiplicador 1,35 |
| Chase | Até 80 studs; ambos a pelo menos 2 studs/s; confirmação de 0,6s; multiplicador 1,4 |
| Ganho final | `base × Compostura × LOS × Chase`, limitado a 8 Fear/s |
| Estados (valor real, inclusive frações) | Calm <25; Nervous ≥25; Scared ≥50; Panicked ≥75; ExtremePanic ≥90 |
| Regeneração de stamina | 100% até Fear 25; ~90,4% em 50; ~72,8% em 75; 50% em 100 |
| Tropeço | Fear ≥75; teste a cada 3s correndo no chão; chance 3–12%; cooldown 8s |
| Efeito do tropeço | Limite a 55% da velocidade de andar por 0,65s (resolução do loop 0,2s) |
| Pânico involuntário | Fear ≥75; teste a cada 5s; chance 2–8%; cooldown 12s; alcance futuro 100 studs |

LOS vai da cabeça do sobrevivente à cabeça do monstro (raiz como fallback). Exclui os dois corpos e acessórios, ignora água e Parts não colidíveis; paredes, troncos, pedras e terreno sólido bloqueiam. Não consulta câmera. A troca do alvo força uma nova consulta. O filtro usa [`RespectCanCollide`](https://create.roblox.com/docs/reference/engine/datatypes/RaycastParams/RespectCanCollide), no grupo de colisão padrão.

Chase exige velocidades horizontais reais de ambos, monstro movendo-se em direção à vítima (`ChaseTowardDot = 0.35`) e vítima não avançando contra ele (`ChaseAwayDot = 0`). Exige LOS inicialmente (`ChaseRequiresLineOfSight = true`). Movimento incompatível encerra Chase; LOS pode levar até 0,4s para refletir um obstáculo novo. Não há Chase com raiz ancorada.

A curva de stamina é `1 - (1 - mínimo) × clamp((Fear - início) / (MaxFear - início), 0, 1)^expoente`, com início 25, mínimo 0,5 e expoente 1,5. `StaminaSystem` consulta `GetStaminaRegenMultiplier` diretamente no servidor, sem ler uma alegação do cliente. O limiar de corrida existente (velocidade > andar ×1,35) passou a `GameConfig.Characters.SprintSpeedRatio` para ser compartilhado com o tropeço.

Tropeço não ocorre parado, andando devagar, no ar, nadando, sentado, ancorado ou amarrado. A decisão/RNG vem do servidor. Durante o efeito o servidor assume temporariamente a [propriedade da simulação física](https://create.roblox.com/docs/physics/network-ownership), limita velocidade horizontal e publica `FearTripping`/`FearTripSpeedCap` no personagem. O script de movimento respeita esses sinais sem disputar os atributos da stamina. Ao terminar, restaura o modo de ownership anterior e remove o limite. Morte, troca/remoção do corpo, saída e fim de rodada também liberam o efeito.

Os temporizadores dos dois eventos são independentes. Depois de cada cooldown começa uma nova janela de verificação; intervalos perdidos não viram vários sorteios de uma vez. A Parte 2 não cria heartbeat novo nem loops por efeito. `StaminaSystem.Init()` também ganhou proteção contra inicialização repetida.

## Parte 2 — API e hooks

```lua
local Fear = require(game.ServerScriptService.Server.FearSystem)
print(Fear.GetFearState(player))
print(Fear.GetStaminaRegenMultiplier(player))

-- BindableEvents somente no servidor; conecte uma vez ao iniciar o consumidor.
Fear.FearStateChanged.Event:Connect(function(player, newState, previousState) end)
Fear.TripTriggered.Event:Connect(function(player, position, duration) end)
Fear.PanicSoundTriggered.Event:Connect(function(player, position, radius) end)
```

`FearState`, `FearLineOfSight` e `FearChase` são resultados replicados no Player para inspeção/futura apresentação. A fonte da verdade continua sendo a tabela privada. Não há RemoteEvent recebendo pedidos de tropeço, estado, visão ou grito.

Na Parte 3, o placeholder singular `PanicSoundId` foi substituído por `PanicSounds = { "", "", "" }`, na mesma configuração. O SoundManager agora consome o hook para tocar áudio 3D quando houver um ID preenchido. Com a lista vazia, o evento continua funcionando sem áudio ou criação de objetos.

## Parte 2 — testes práticos no Studio

Use a preparação multiplayer descrita acima. Ative `DebugMode`; o Output agora inclui FearState, LOS, Chase, multiplicador de regen e cooldowns além dos campos da Parte 1.

1. **LOS:** deixe sobrevivente e monstro parados, separados por ~40 studs. Sem obstáculo, `LineOfSight: true`. Coloque uma Part ancorada e `CanCollide = true` atravessando a linha entre as cabeças (ou use uma parede do mapa). Em até 0,4s deve mudar para false, e o ganho/s cair. Teste tronco, pedra e terreno; partes decorativas sem colisão não bloqueiam.
2. **Chase:** desancore o monstro caso tenha usado o teste anterior. Dentro de 80 studs, conduza-o atrás de um sobrevivente que está fugindo, ambos em movimento e com linha livre. Após 0,6s, `Chase: true`; pare um deles, faça o monstro ir para o lado oposto ou use uma parede para desfazer. Estar parado ao lado nunca basta. Duas pessoas controlando os clientes facilitam este teste.
3. **Stamina:** em um sobrevivente ativo, esgote parte da stamina correndo. Compare a recuperação com Fear 0 e Fear 100 mantendo o mesmo personagem/perk. Use a API na Command Bar do servidor para definir o Fear, não edite o Attribute diretamente. Em 100, a taxa deve ser metade; o máximo continua 100. Os primeiros segundos ainda respeitam o atraso normal da stamina.

```lua
local Fear = require(game.ServerScriptService.Server.FearSystem)
local player = game.Players:FindFirstChild("Player3") -- sobrevivente no roteiro com 4 clientes
assert(player and player:GetAttribute("Role") == "Sobrevivente")
Fear.ReduceFear(player, 100)
Fear.AddFear(player, 100, "StudioTest") -- use 0 para comparação calma
```

Para isolar a medição, temporariamente no servidor da sessão de teste deixe `GameConfig.Fear.MaxProximityFearPerSecond = 0` e `BaseFearRecoveryPerSecond = 0`. Assim o Fear não muda durante a comparação. Pare a sessão ao concluir para recuperar os valores normais.

4. **Tropeço e Panic Sound:** para não depender das probabilidades raras, rode este comando no servidor uma vez. Ele coloca Fear 100 no sobrevivente, força sucesso das verificações e imprime os hooks. Não muda os intervalos/cooldowns e não adiciona efeitos visuais. As conexões anteriores deste mesmo comando são desligadas antes de conectar novamente:

```lua
assert(game:GetService("RunService"):IsStudio())
local cfg = require(game.ReplicatedStorage.Modules.GameConfig).Fear
local Fear = require(game.ServerScriptService.Server.FearSystem)
local player = game.Players:FindFirstChild("Player3")
assert(player and player:GetAttribute("Role") == "Sobrevivente")
cfg.DebugMode = true
cfg.TripChanceMin, cfg.TripChanceMax = 1, 1
cfg.PanicSoundChanceMin, cfg.PanicSoundChanceMax = 1, 1
cfg.BaseFearRecoveryPerSecond = 0
Fear.AddFear(player, 100, "StudioTest")
if _G.FearDebugHooks then
    for _, connection in _G.FearDebugHooks do connection:Disconnect() end
end
_G.FearDebugHooks = {
    Fear.TripTriggered.Event:Connect(function(p, position, duration)
        print("TRIP", p.Name, position, duration)
    end),
    Fear.PanicSoundTriggered.Event:Connect(function(p, position, radius)
        print("PANIC SOUND HOOK (sem áudio)", p.Name, position, radius)
    end),
}
```

Corra no chão por pelo menos 3s: deve haver uma perda curta de ritmo com `TRIP` no Output. Continuar correndo não pode provocar outro dentro do cooldown. Pare de correr: nenhum novo tropeço. Parado ou correndo com Fear alto, o hook de pânico aparece após sua janela de 5s e respeita o cooldown de 12s. Sem preencher `PanicSounds`, não se espera ouvir áudio. Mate/remova o personagem durante um tropeço ou encerre a rodada e confira que os atributos de tropeço são removidos e Fear volta a zero. Pare a sessão para restaurar todas as probabilidades normais.

Os testes automatizados adicionais cobrem estados fracionários, cache/filtro LOS, condições direcionais de Chase, teto combinado, integração com o StaminaSystem real, intervalo de RNG, cooldowns, hooks e tomada/liberação da simulação física. A fonte Luau embutida no XML de movimento também é compilada.

Validação desta etapa: suite Fear (Partes 1/2), compilação Luau incluindo Crouching, análise de FearRules, build Rojo e diff-check passaram. A suite adicional `run_firearms.py` passou nas verificações de tiro e falhou na expectativa de reserva após reload: o teste adiciona 8 balas supondo reserva inicial zero, enquanto `GameConfig.Firearms.StartingReserve.Pistola` já é 34. Essa configuração e os arquivos da Glock não foram alterados nesta etapa; a falha permanece registrada, fora do escopo do Fear.

## Parte 3 — apresentação e assets

O servidor continua dono do Fear e de seus efeitos de gameplay. O cliente só suaviza a apresentação do atributo numérico replicado, sem calcular proximidade, resistência, perseguição ou chances de tropeço/grito novamente.

Arquivos criados nesta etapa:

- `src/ReplicatedStorage/Modules/FearPresentationRules.lua`: valida formatos de IDs e contém apenas curvas/suavização visuais e de áudio.
- `src/client/FearPresentation.lua`: apresentação local, vinheta, blur, heartbeat, respiração e ciclo de vida.
- `src/client/FearAnimationPlayer.lua`: tracks opcionais R6 e proteção das ações existentes.
- `src/ReplicatedStorage/Remotes/FearPresentation.model.json`: evento exclusivamente servidor → cliente para apresentar Trip.
- `tests/fear_presentation.luau` e `tests/run_fear_presentation.py`: regressões da apresentação com serviços simulados.

Arquivos modificados: `GameConfig.lua`, `Remotes.lua`, `SoundManager.lua`, `AmbientSoundController.client.luau` e este guia. A lógica das Partes 1/2 não foi reescrita. O antigo AmbientSoundController, que tocava um batimento por tempo fora de zona segura, agora inicia a apresentação de Fear; não existem dois batimentos concorrentes.

Edite **GameConfig.Fear antes de iniciar o Play**:

| Campo | Uso / padrão |
| --- | --- |
| `HeartbeatSoundId` | ID de batimento em loop; vazio inicialmente |
| `BreathingSoundId` | ID de respiração em loop; vazio inicialmente |
| `PanicSounds` | Lista de IDs para gritos 3D; três entradas vazias |
| `FearAnimations.FearIdle/FearWalk/FearRun` | Animações R6 de locomoção com medo; vazias |
| `FearAnimations.LookAround` | Animação ocasional de olhar para os lados; vazia |
| `FearAnimations.Trip` | Animação curta de tropeço; vazia |

Aceita `"rbxassetid://SEU_ID_NUMERICO"` ou apenas a string numérica real do seu asset. Não use o texto deste exemplo como ID. Zero, strings vazias e formatos inválidos são ignorados; nenhum asset foi inventado ou substituído por um ID aleatório. O asset deve estar publicado e autorizado para esta experiência. Falhas de carregamento de animação são guardadas, sem criar objetos novos a cada tick; uma mudança do ID ou respawn permite nova tentativa.

Heartbeat começa em Fear 30, até volume 0,45 e PlaybackSpeed 0,9–1,25. Respiração começa em 45, até volume 0,35 e velocidade 0,95–1,15. Sons locais são criados uma vez e reutilizados. O debug mostra volume efetivo zero enquanto o respectivo ID estiver vazio.

A vinheta começa em 50 e chega a opacidade 0,22 por borda. Quatro gradientes deixam o centro livre; a GUI não recebe input e fica abaixo da HUD. É separada da vinheta de dano/agachamento. O blur começa em 75 e chega a 4, em um BlurEffect local próprio associado à câmera; outros efeitos e presets de Lighting não são modificados. Transições usam interpolação exponencial e curvas contínuas a 20Hz, sem criar Tweens por atualização e sem degraus de FearState.

### Pânico: tela escura e HUD sumindo

Acima de certos limiares o jogador perde a leitura calma da tela. Tudo é **apresentação local**: fôlego, itens, mapa e Fear continuam iguais no servidor, e os limiares vivem em `GameConfig.Fear`.

| Efeito | Começa | Completo | Onde |
| --- | ---: | ---: | --- |
| Escurecimento animado da tela | 68 | 100 | `FearPresentation` (camada `FearDarken`) |
| Minimapa + barra de fôlego apagam | 70 | 86 | `SurvivalMinimapHUD` (o `CanvasGroup` inteiro) |
| Mapa grande (M) trava e fecha | 86 | — | `SurvivorMapController` |
| Barra de itens desliza pra fora | 78 | 92 | `HotbarController` |

O escurecimento é um `Frame` de tela cheia com `ZIndex = 0`, **por baixo** da vinheta, que respira devagar (`DarkenPulseSpeed = 1.15` ciclos/s, oscilando 22% da opacidade) para não virar um filtro estático. `DarkenMaxOpacity` é 0,42 e o código impõe um teto duro de 0,6: a tela escurece, nunca apaga.

Os quatro consumidores usam a **mesma função pura** `FearPresentationRules.HudFade(fear, config)` e leem o Fear do Attribute replicado pelo servidor -- nenhum deles calcula medo. `SurvivalMinimapHUD:Update` recebe o valor como último argumento e aplica `math.max` sobre a transparência ociosa que já existia: o medo só pode esconder mais, nunca revelar. O inventário é o último a sair (78 contra 70): você perde a leitura da tela antes de perder a barra de itens.

Nada disso desabilita controle: as teclas 1/2/3, G e o fôlego continuam funcionando com o HUD invisível. Só o mapa grande é realmente bloqueado, porque abrir um mapa em pânico anularia o efeito inteiro. Quando o Fear cai, tudo volta sozinho.

**FOV permanece desativado.** Movimento, agachamento, sprint e mira já compartilham um tween em Crouching. Não foi acrescentado outro escritor de FieldOfView. `EnableFearFOV = false`, `FearFOVStart` e `FearFOVMaxOffset` ficam reservados; ativar a flag avisa no Output e mantém offset zero até existir integração com um compositor de câmera. Nenhum camera shake foi acrescentado.

## Parte 3 — animações e compatibilidade

As animações normais do Animate usam Movement. Os tracks de Fear usam Action e cedem imediatamente a tracks externos Action/Action2/Action3/Action4. A comparação trata Core corretamente como prioridade mínima, apesar de seu valor numérico 1000; ver a [ordem oficial de AnimationPriority](https://create.roblox.com/docs/reference/engine/enums/AnimationPriority).

Por segurança, nenhuma animação de Fear toca com Tool equipada, mirando, durante ações importantes, prompt segurado, sentado, pulando, caindo, nadando, agachado, rastejando, amarrado ou com o corpo ancorado. Equipar Tool ou iniciar um track de ação interrompe somente nossos tracks; tracks da Glock e do pick não são parados. O bloqueio conservador com qualquer Tool protege também holster/idle da arma e bandagem.

FearIdle/Walk/Run começam em Fear 75, conforme velocidade horizontal. Calm e Nervous mantêm o Animate normal. LookAround pode ocorrer a partir de 60, parado ou andando: verificação a cada 6s, chance 6%, cooldown 20s, duração máxima 3s. Trata-se de apresentação, não de outra fonte de Fear. Sem ID, nem a verificação aleatória de LookAround é feita.

Trip recebe o hook já existente do servidor via RemoteEvent, com referência ao personagem e duração. Eventos de personagens antigos são descartados. A animação só toca se configurada e sem ação prioritária; terminar ou omitir o track não cancela o tropeço físico do servidor.

PanicSound é reproduzido pelo **SoundManager existente**: escolha aleatória entre IDs com formato válido, Sound com RollOff e alcance recebido do hook, origem fixa na posição do grito. Uma voz por jogador é reutilizada, com limite de duração de 6s. A voz é removida ao morrer, remover/trocar corpo, mudar papel, sair da rodada/servidor ou terminar a partida. Não há novo cálculo de chance/cooldown nem RemoteEvent de solicitação vindo do cliente.

## Parte 3 — teste no Studio

1. Pare o Play, preencha os assets desejados em `GameConfig.Fear`, ative `DebugMode = true`, aguarde Rojo sincronizar e inicie novamente. Módulos carregados no servidor e no cliente possuem tabelas separadas: alterar a tabela no Command Bar do servidor não configura o áudio local. Para mudanças de configuração compartilhadas, edite o arquivo e reinicie o teste.
2. Entre como sobrevivente, inicie a partida e escolha o personagem. O roteiro multiplayer acima continua válido; para testar só vinheta/blur/áudio local, pode usar a partida solo de sobrevivente e definir Fear pela API do servidor.
3. Na Command Bar **do servidor**, execute o bloco abaixo mudando `level` para 0, 30, 50, 75, 90 e 100. Ele congela apenas a evolução de Fear durante o teste, sem ancorar o jogador ou alterar movimento:

```lua
assert(game:GetService("RunService"):IsStudio())
local config = require(game.ReplicatedStorage.Modules.GameConfig)
local Fear = require(game.ServerScriptService.Server.FearSystem)
local player
for _, candidate in game.Players:GetPlayers() do
    if candidate:GetAttribute("Role") == config.Roles.Survivor
        and candidate:GetAttribute("InRound") == true then
        player = candidate
        break
    end
end
assert(player and player:GetAttribute("CharacterSelectOpen") ~= true, "Escolha seu sobrevivente na partida")
config.Fear.MaxProximityFearPerSecond = 0
config.Fear.BaseFearRecoveryPerSecond = 0
local level = 100
Fear.ReduceFear(player, 100)
Fear.AddFear(player, level, "StudioPresentationTest")
```

4. Confira transições suaves, centro da tela legível, blur leve e FOV preservado. Com IDs vazios haverá apenas vinheta/blur; silêncio e animações normais são o comportamento esperado. No Output do **cliente**, `[FearPresentation]` mostra volume/velocidade do heartbeat, respiração, vinheta, blur, offset zero e animação atual a cada 2s.
5. Com IDs R6 configurados, guarde todas as Tools e fique parado/ande/corra. Equipe Glock, mire, atire e recarregue: os tracks de Fear devem parar. Teste também E segurado/pick, bandagem, agachar, rastejar e pular. Para observar LookAround rapidamente, configure temporariamente sua chance como 1 antes do Play.
6. Use as chances temporárias de 100% do roteiro da Parte 2 para provocar tropeço/grito. Trip deve continuar reduzindo o ritmo mesmo com `FearAnimations.Trip` vazio. Com `PanicSounds` preenchido, outro cliente próximo (inclusive Monstro) deve ouvir a origem espacial; longe do alcance, não. Teste com dois clientes para áudio 3D real.
7. Morra, reapareça, encerre a rodada e troque o papel pelo fluxo de teste: nenhum efeito local deve permanecer no lobby. Reinicie o Play ao terminar para restaurar as taxas/chances normais.

Validação automatizada da Parte 3:

```sh
python3 tests/run_fear.py /caminho/para/luau
python3 tests/run_fear_presentation.py /caminho/para/luau
rojo build -o /tmp/meujogo-fear-part3.rbxlx
```

As suites exercitam módulos reais com serviços/asset loading simulados: continuidade, placeholders, reutilização, prioridades, bloqueio de prompts, Trip, pool espacial e cleanup. Não reproduzem renderização, latência, permissões de assets nem as animações reais no Studio. Os códigos da Glock, do pick e da locomotion original não foram modificados nesta etapa; a compatibilidade foi verificada nos contratos/prioridades e precisa do teste 3D após preencher os IDs.
