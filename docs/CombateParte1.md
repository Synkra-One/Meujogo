# Combate — Parte 1

Implementação sobre a arquitetura existente de Náufragos. Sincronize o projeto
com Rojo e reinicie a sessão de Play para carregar o novo LocalScript e remote.
Equipe pela hotbar existente e pressione o botão esquerdo do mouse. Não há
prompt, tecla E, ClickDetector nem animação nova para atacar.

## Configuração

`ReplicatedStorage.Modules.GameConfig.Weapons.Definitions` é a fonte das regras.
Distâncias em studs; tempos em segundos.

| Arma | ID existente | Dano | Alcance | Cooldown | Efeito |
|---|---|---:|---:|---:|---|
| Chave inglesa | `PedraAfiada` | 8 | 6 | 1 | Recuo de força 12 |
| Pé de cabra | `LancaDeBambu` | 15 | 7 | 1,5 | Atordoamento de 0,4 s |
| Sinalizador | `Sinalizador` | 0 | 35 | 2 | Sinal visual temporário |
| Pistola | `Glock17` | 25 | 300 | 0,4 | 12 balas por Tool |

Os IDs antigos foram mantidos para preservar crafting, drops e pickups. A faca
improvisada legada continua cadastrada com dano zero e recuo; não foi criado outro
inventário. O sinalizador usa `ItemRegistry` e `ToolFactory`, com `Zones = {}` e
sem raridade: não muda a distribuição do mapa nem o loot das caixas.

A pistola normal usa `Ammo` da configuração para inicializar o
`Settings.Config.Ammo` já existente. O marcador `CombatAmmoInitialized` impede
reposição ao equipar, largar ou pegar a mesma arma. Munição vazia impede disparo.
A reserva antiga continua sendo de `AmmoSystem`, mas não alimenta esta pistola:
recarga está desligada nesta etapa. A HUD exibe reserva zero para ela.

As armas normais usam dano fixo nesta etapa, inclusive tiros na cabeça. O sinalizador
não aplica dano, revela, repele, atordoa ou consome poderes. Seus campos
`RevealMonster`/`RepelMonster` são reservados e ainda não ativam essas funções.

## Responsabilidades e APIs

- `CombatRules`: identifica uma Tool cadastrada e valida papel, rodada e estados
  impeditivos. Usado por cliente e servidor; a validação decisiva é a do servidor.
- `WeaponSystem.Equip(player, tool)`: equipa uma Tool já pertencente ao jogador;
  não cria nem entrega itens. A hotbar continua usando `Humanoid:EquipTool`.
- `WeaponSystem.ValidateAttack` / `Attack`: corpo a corpo e sinalizador. O
  servidor identifica a arma pela Tool equipada, sem aceitar dano, alvo ou nome
  arbitrário enviados pelo cliente.
- `WeaponSystem.IsReady` / `UseCooldown`: cooldown por jogador, compartilhado
  com a pistola normal. Errar consome o intervalo; trocar de arma não o reinicia.
- `OTSFirearmService`: preserva o único caminho de disparo da pistola. Valida a
  Tool equipada, munição, intervalo e coordenadas finitas. Calcula o raycast e
  desconta uma bala no servidor. A mira com botão direito é opcional na partida.
- `DamageSystem.Apply` / `Execute` / `Heal`: continuam sendo a porta de dano,
  execução e cura. `FixedDamage = true` é uma opção somente para chamadas do
  servidor: mantém o dano configurado sem multiplicadores de atributos/poderes.
  As proteções existentes, como ForceField, imunidade e esquiva, permanecem.
- `SurvivorPowerStatus.Stun`: reutilizado pelo pé de cabra; mantém expiração,
  imunidades e restauração de movimento, sem outro sistema de atordoamento.
- `WeaponSystem.SignalFired`: BindableEvent `(player, position)` para uma próxima
  etapa conectar o comportamento do sinalizador, sem acrescentar remotes.
- `WeaponSystem.NoiseMade`: contrato legado preservado para fontes ambientais e
  `NoiseService`; a chave inglesa deixou de ser o arremesso de pedra.

`WeaponController` conecta a ativação das Tools não OTS. A pistola permanece no
`OTSController`. Foi necessário apenas um novo remote: `WeaponAttack`, cliente →
servidor, com a Tool equipada como único argumento. `FirearmShoot` e os eventos
de feedback OTS são reutilizados. Vida/estado não recebem pedidos de alteração
vindos do cliente.

O ataque usa a ativação padrão de Tools, também usada pela lanterna do projeto.
A mesma entrada pode ser acionada por controle ou por um futuro botão de celular
via `Tool:Activate()`. A pistola já mantém os botões de toque OTS existentes.
Referências: [Tool](https://create.roblox.com/docs/reference/engine/classes/Tool)
e [ContextActionService](https://create.roblox.com/docs/reference/engine/classes/ContextActionService).

## Alvos e obstáculos

Sobreviventes e o Espião com aparência humana mantêm acesso às armas. Na partida,
as quatro armas só podem ferir o Monstro: não há dano próprio ou fogo amigo.
O golpe básico existente do Monstro também foi limitado a uma vítima, com
obstrução por paredes e validação de participação na rodada. Sua animação de
golpe respeita o mesmo botão de configuração que desliga reações nesta etapa.
O corpo a corpo dos humanos busca um único Monstro vivo, na rodada, mais próximo dentro do
cone frontal, com raycast entre os personagens para bloquear paredes. Não usa
Touched como confirmação de acerto. A pistola usa o primeiro impacto do raycast,
incluindo uma verificação do trecho entre a cabeça e o cano para impedir que uma
arma atravessando uma parede dispare do outro lado. Objetos de cenário consultáveis
pelo raycast bloqueiam o ataque; elementos configurados com `CanQuery = false`
não são obstáculos para raycasts do Roblox.

## Vida e estados do Monstro

O Humanoid já alimenta HUD, cura, dano de queda e eliminação. Foi mantido como
armazenamento de vida, com regras e escrita no servidor, sem uma segunda barra
lógica concorrente. Os humanos conservam a vida baseada em Compostura (faixa
existente 75–130; `Health.Max = 100` é a referência do projeto).

`StatScaling.MaxHealth` retorna `GameConfig.Health.MonsterMax = 1000` para o
Monstro; assim tanto `DamageSystem` quanto `CharacterStatsApplier` concordam,
inclusive após escolha de personagem e respawn. Mudança de papel reinicializa
vida e limpa os atributos temporários do combate, sem alterar quem sorteia papéis.

`DamageSystem.GetMonsterState(target)` retorna `Normal`, `Enfraquecido` ou
`Vulneravel`, e nil para humanos. `SetMonsterState(target, state)` aceita somente
os valores de `GameConfig.Monster.CombatStates`, exclusivamente no servidor.
Todos os estados recebem dano normalmente nesta etapa e continuam protegidos
contra morte definitiva. O debuff de luz existente (`MonsterLightWeakness`) é
independente: laboratório, Emissor e R-7 não foram conectados ou implementados.

`Apply` limita o dano antes de chamar `TakeDamage`, deixando no mínimo
`Health.MonsterMinimum = 1`. `Execute` também respeita esse limite e retorna
false. Na primeira tentativa letal por personagem/vida de rodada, publica
`MonsterTemporarilyDefeated = true` e uma mensagem de derrota temporária no Output.
Não dispara Humanoid.Died, Dead, Elimination ou PlayerKilled para essa derrota.
Não há regeneração passiva do Monstro nesta etapa; a dos humanos permanece.

## Feedback e compatibilidade

Dano confirmado cria um Highlight vermelho por 0,18 s, oculto por paredes,
além da atualização normal da vida. Disparos reutilizam sons, traçantes,
impactos e hitmarker do OTS. Tools corpo a corpo podem reutilizar um Sound
`Handle.AttackSound`, caso exista; nenhum ID de áudio novo foi inventado.
O sinalizador marca visualmente o ponto alcançado por 0,25 s.

As reações de dano antigas ficam desativadas por
`Health.CombatAnimationsEnabled = false`. A pistola normal não carrega trilhas
de arma nem aplica recoil. Assets antigos e animações de sistemas fora desta
etapa continuam disponíveis. A pistola marcada `LobbyTestWeapon` conserva o
comportamento OTS anterior, incluindo recarga, animações e alvos de treino;
mapa, bancada do lobby e atribuição de papéis não foram editados.

## Validação

```sh
python3 tests/run_firearms.py
python3 tests/run_match_stats.py
rojo build -o /tmp/naufragos-combat-part1.rbxlx
```

A suíte de armas executa os módulos reais de vida, stats, regras, armas e OTS
com serviços simulados. Cobre valores de dano, entrada inválida, posse, estados
impeditivos, cone, alcance, paredes, um único alvo, troca durante cooldown,
sinalizador, munição, ausência de recarga, proteção do Monstro e reinicialização
de vida/papel. Inclui regressões da pistola/bancada do lobby. Relatórios/XP:
31 cenários existentes passaram.

As suítes antigas `run_waiting_room.py`, `run_shadow_rush.py` e
`run_survivor_powers.py` não completaram: seus simuladores não fornecem,
respectivamente, `Enum.KeyCode`, `CFrame.Angles` e o módulo `RadioSiteSystem`
necessários pelo código atual. Esses simuladores não foram alterados nesta tarefa.

Ainda é necessário validar em Play com dois clientes no Studio: física real,
ativação por mouse/controle/toque, permissões de áudio e aparência dos efeitos.
O build Rojo e os testes simulados não substituem essa verificação.

Para testar sem modificar spawns, durante Play execute na Command Bar **do
servidor**, com o Sobrevivente já na rodada (substitua o nome):

```lua
local player = game.Players:FindFirstChild("NomeDoSobrevivente")
assert(player and player:GetAttribute("InRound") == true)
local factory = require(game.ReplicatedStorage.Modules.ToolFactory)
for _, id in { "PedraAfiada", "LancaDeBambu", "Sinalizador" } do
    local tool = factory.Create(id)
    if tool then tool.Parent = player.Backpack end
end
local pistol = game.ReplicatedStorage.WeaponAssets.Tools.Glock17:Clone()
pistol.Parent = player.Backpack
```

Equipe um item por vez na hotbar. Teste de frente, por trás, longe e separados
por uma parede; clique rapidamente e troque de arma. Confirme no servidor 1000 HP
iniciais, dano de 8/15/25, 12 tiros por pistola e 1 HP na derrota temporária.
