# R — Apagão do Abismo (Monstro)

Grito de escuridão do Monstro. A área existe por **um instante**: no disparo o
servidor fotografa quem está dentro do raio, aplica um pico único de Fear e
bloqueia a lanterna dessas vítimas pelos 12 s seguintes — **saindo da área ou
não**. Quem entra depois da ativação não é afetado.

A habilidade **não** dá velocidade ao Monstro, **não** causa dano e **não**
teleporta ninguém.

## O que foi reaproveitado (nada disso é novo)

| Precisava de | Sistema existente usado |
| --- | --- |
| Valor atual / máximo de Fear | `FearSystem` (tabela privada do servidor) + `GameConfig.Fear.MaxFear = 100` |
| Aumentar Fear | `FearSystem.AddFear(player, pontos, "AbyssBlackout")` — já faz o clamp no teto |
| Diminuir Fear | Recuperação passiva de `FearRules.Step` (3,5/s depois de 4 s longe). O Apagão não mexe nela |
| Compostura | `StatScaling.FearGainMultiplier` (0 → 1,5x, 100 → 0,55x), o mesmo fator que o Fear por segundo usa |
| Apresentação de medo | `FearPresentationRules.AssetId` para validar áudio; vinheta/blur no mesmo padrão do `FearPresentation` |
| Lanterna | `FlashlightConfig.BlockingFlags` — a lista de Attributes que **já** desligava a lanterna em `GrabLocked`, `ShadowRushBusy`, `TeleportBusy`, `PowerStunned` e `Amarrado` |

`BlockingFlags` era uma lista literal **duplicada** em `FlashlightSystem.canUse`
(servidor) e `FlashlightController.blockedReason` (cliente). Ela foi movida para
`FlashlightConfig` e os dois lados passaram a ler a mesma tabela: agora um poder
novo só precisa ligar um Attribute para a lanterna morrer nas duas pontas, sem
risco de servidor e cliente divergirem.

## Números (todos em `GameConfig.Monster.AbyssBlackout`)

| Parâmetro | Valor |
| --- | --- |
| Raio | **150 studs** (lido só no instante da ativação) |
| Duração | **12 s** fixos |
| Cooldown | **75 s** (o `Init()` recusa qualquer valor fora de 60–90) |
| Fear aplicado | **35 pontos** = 35% do teto de 100, **uma única vez** |
| Influência da Compostura | `ComposureInfluence = 0.5` |
| Passo do expirador | 0,2 s (só expira sessões; nenhum Fear é somado ali) |
| Tecla | `R` / `ButtonR1` (E = Grab, F = Shadow Rush, Q = mapa, R2 = golpe já estavam ocupadas) |

### Compostura: quem tem o atributo alto sofre um pouco menos

`AbyssBlackoutRules.FearAmount` mistura o multiplicador existente com 1, em vez
de usá-lo cru — senão Compostura alta viraria quase imunidade a um pico deste
tamanho:

```
efetivo = 1 + (FearGainMultiplier - 1) * ComposureInfluence
```

| Compostura | Multiplicador do Fear | Pontos do Apagão |
| --- | --- | --- |
| 0 | 1,50 | **≈ 43,8** |
| 50 | ≈ 1,00 | **≈ 35,0** |
| 100 | 0,55 | **≈ 27,1** |

Exemplo pedido: Sobrevivente de Compostura média com Fear 20/100 é atingido e
vai para **≈ 55/100**. Sai da área: continua bloqueado até os 12 s acabarem. No
fim do efeito a lanterna volta e o **Fear permanece** — só a recuperação normal
do `FearSystem` o reduz, como em qualquer outra fonte.

## Como os jogadores são registrados

Toda a leitura de posição acontece em **um laço só**, dentro de `cast()`:

1. Valida o Monstro (rodada ativa, papel, vivo, não amarrado, sem
   `TeleportBusy` / `GrabLocked` / `PowerStunned` / `ShadowRushBusy`, cooldown).
2. Percorre `Players:GetPlayers()` uma vez e guarda quem é Sobrevivente vivo,
   `InRound`, não eliminado **e** dentro de `Rules.InRadius(origem, posição, 150)`.
3. Para cada um: cria a sessão, liga o bloqueio e aplica o Fear.

Depois disso nenhuma posição é lida de novo. O `Heartbeat` da habilidade só
**expira** sessões pelo relógio (`Workspace:GetServerTimeNow() >= endsAt`) — ele
não tem acesso a distância, então sair da área não pode cancelar nada e entrar
na área não pode pegar ninguém.

## Como a lanterna é bloqueada e restaurada

Bloqueio (servidor, em `affect()`):
- `character:SetAttribute("AbyssBlackout", true)` — está em `BlockingFlags`,
  então `FlashlightSystem.canUse` recusa ligar e o `step()` apaga a Tool ligada;
  no cliente, `blockedReason()` recusa o toggle e o feixe some.
- `character:SetAttribute("AbyssBlackoutUntil", endsAt)` — só informação.
- `FlashlightSystem.ForceOff(character)` — corte no **mesmo frame**, em vez de
  esperar o próximo passo de 0,1 s do sistema de lanterna.

A Tool **continua no inventário**, com a mesma bateria: nada é removido, nada é
criado. Nenhuma segunda lanterna existe.

Restauração: os três Attributes são apagados e o cliente recebe `"End"`. A
lanterna fica **disponível de novo**, desligada — religar continua sendo um
pedido do dono, exatamente como o resto do sistema já funciona
(`Recharge` também nunca acende nada sozinho).

Limpeza garantida em: fim dos 12 s, `Humanoid.Died`, `CharacterRemoving`
(respawn/troca de personagem), `PlayerRemoving`, eliminação e
`RoundPrepared`/`RoundEnded`.

## Rede

RemoteEvent **AbyssBlackout** (`src/ReplicatedStorage/Remotes/AbyssBlackout.model.json`):

- **C → S:** `"Use"` e nada mais. Nenhum alvo, raio, duração ou cooldown vem do
  cliente. Limitado a um pedido por 0,1 s por jogador, com `pcall` em volta.
- **S → C:** `"Cast"` (todos, para VFX de mundo), `"Hit", duração, endsAt` (só
  quem foi registrado), `"End"`, `"Result", atingidos` e `"Rejected", motivo`
  (só o Monstro).

Cooldown replica em `Player.AbyssBlackoutReadyAt` (tempo de servidor), igual ao
Shadow Rush.

### Proteção contra duplicação

- `initialized` em `Init()`: chamar duas vezes não cria uma segunda conexão de
  `Heartbeat`, de remote ou de `PlayerRemoving`.
- Limitador de entrada de 0,1 s **mais** `ActivationLockout` de 0,4 s: duplo
  clique no mesmo instante produz uma ativação só.
- Uma sessão por vítima; reativar sobre alguém já afetado encerra a anterior
  antes de abrir a nova (sem conexões órfãs).

## Feedback

Na tela da vítima (`client/AbyssBlackoutController`): pulso vermelho-escuro
subindo em 0,12 s, caindo para uma escuridão sustentada, com blur e alívio nos
últimos segundos — o envelope é `AbyssBlackoutRules.Presentation`, o **mesmo
módulo** que o servidor carrega, e volta a zero no fim (nada permanente). O
estrondo grave usa `HitSoundId` com `PlaybackSpeed` 0,42. Um rótulo mostra
"Lanterna apagada pelo Abismo · Xs"; para o Monstro, o cooldown e quantos foram
atingidos.

Rede de segurança: se o `"End"` se perder, o cliente também escuta o Attribute
`AbyssBlackout` sumir e derruba o visual junto.

## Pronto para animação

Nenhum asset é obrigatório — campos vazios simplesmente não tocam nada.

- `CastAnimationId` / `VictimAnimationId` / `AnimationFadeTime`
- `CastSoundId`, `CastSoundVolume`, `SoundMaxDistance` (áudio 3D no Monstro).
  O ID atual é `113309977574893` e toca 1 segundo depois do evento `Cast`.
- `CastDuration` (0,45 s) mantém o Attribute `AbyssBlackoutCasting` ligado no
  Monstro: é a janela reservada para a animação de conjuração. Ela é **só
  apresentação** — o registro das vítimas continua no instante 0 da ativação.
- `AbyssBlackoutCastAt` (tempo de servidor) permite sincronizar a animação em
  quem chega depois ou por streaming, como o Shadow Rush faz com `PhaseAt`.

## Teste

```bash
python3 tests/run_abyss_blackout.py ~/.rokit/bin/luau
```

Roda os módulos **reais** (`GameConfig`, `StatScaling`, `FearRules`,
`FearSystem`, `AbyssBlackoutRules`, `AbyssBlackout`) contra dublês
determinísticos dos serviços da Roblox e cobre os 15 pontos de validação:
registro no instante, saída imediata da área, entrada tardia, Fear uma única vez
(e nunca por frame), expiração, retorno da lanterna, Fear preservado, cooldown,
morte, respawn, saída do jogador, ativação duplicada e Output sem avisos.
O runner ainda checa estaticamente que servidor e cliente leem a mesma
`BlockingFlags` e que a habilidade não escreve velocidade, dano nem CFrame.

Não substitui um playtest com dois Sobreviventes no Studio.
