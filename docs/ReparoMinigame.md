# Reparo de precisão

Os pontos reparáveis (instalar peça do transmissor, ligar o gerador, ativar o painel, consertar fio sabotado) não são mais "segure E por alguns segundos". Agora abrem um minigame de timing. A regra de cada objetivo **não mudou**: o minigame só decide *quando* o handler antigo é chamado.

| Arquivo | Papel |
| --- | --- |
| `src/ReplicatedStorage/Modules/RepairMinigameConfig.lua` | Números, tema e a matemática do marcador. Compartilhado. |
| `src/server/RepairMinigameSystem.lua` | Sessões, sequência, notas, punição e ruído. Autoritativo. |
| `src/client/RepairMinigameController.client.luau` | Painel, animações e entrada. Não decide nada. |
| `src/ReplicatedStorage/Remotes/RepairMinigame.model.json` | O único remote novo. Contrato em `Modules/Remotes.lua`. |

## Como conclui: 3 acertos SEGUIDOS

**Não existe progresso passivo.** Segurar a tecla sem fazer nada nunca conclui o reparo. Um marcador luminoso varre a barra; o jogador aperta quando ele cruza a área verde ou azul. Só quando acerta **3 vezes seguidas** (`Streak.Required`) o objetivo é concluído. Qualquer outra coisa **zera a sequência**:

| Resultado | Sequência | Extra |
| --- | --- | --- |
| Azul ou verde | `+1` | Brilho e som positivos. |
| Amarelo | zera (`Streak.YellowBreaks`) | Sem barulho, sem travar. Quase, mas não é acerto. |
| Vermelho | zera | **Ruído para o Monstro** e trava o próximo teste. |
| Teste ignorado | zera | O mesmo que o vermelho. Ficar parado gera um ruído a cada teste que expira. |

Os testes continuam aparecendo sem limite até fechar a sequência ou o jogador desistir. O intervalo entre eles, a velocidade do marcador, a posição das áreas e o estilo visual são sorteados a cada teste.

A barra do painel mostra a **sequência** (`0/3`, `1/3`, `2/3`); ela esvazia inteira no erro.

## Dificuldade = atributo Reparo

A regra (3 seguidas) é igual para todos. Quem tem Reparo enfrenta um teste muito mais fácil; quem não tem, um muito difícil. `RepairMinigameConfig.Tuning(player)` lê `StatScaling.RepairMultiplier` — o mesmo multiplicador usado pela sintonia — e move quatro alavancas (`RepairMinigameConfig.TuningRange`):

| Alavanca | Reparo baixo | Reparo alto |
| --- | --- | --- |
| Largura da área verde | 0,27× | 0,85× |
| Segundos por travessia do marcador | 0,8× (**mais rápido**) | 1,2× (**mais lento**) |
| Oscilação de velocidade do marcador | ±13% de deslocamento (imprevisível) | ±2% (quase constante) |
| Tranco depois de errar | 1,7× | 0,6× |

O número que o jogador sente é a **janela**: quanto tempo o marcador fica dentro do verde. Com os valores atuais:

| Personagem | Reparo | Janela | Acerto por toque* | 3 seguidos* |
| --- | --- | --- | --- | --- |
| Marina, Bruno | 10 | ~28 ms | ~27% | ~2% |
| Rafael, Sofia, Camila | 20 | ~44 ms | ~42% | ~7% |
| Kevin | 68 | ~93 ms | ~76% | ~43% |
| Diego | 96 | ~128 ms | ~89% | ~70% |

\* Estimativa por modelo, não medição: assume que o jogador tem ~40 ms de erro de timing contra um marcador previsível. Um jogador muito bom (~25 ms) acerta mais; a oscilação de velocidade do marcador de Reparo baixo piora esses números para todos. Cada erro faz barulho e trava o próximo teste, então errar muito custa caro.

O marcador de quem tem Reparo baixo **acelera, freia e recua um instante** ao longo da travessia (`wobbleAmp`, com frequência e fase sorteadas por teste), então não dá para decorar o ritmo. O de quem tem Reparo alto anda quase em linha reta.

**Estes números vêm de conta, não de playtest.** Se ainda estiver fácil demais, o botão principal é `TuningRange.GreenScale.Min` (diminua) e `PeriodScale.Min` (diminua = marcador mais rápido); `WobbleAmp.Min` aumenta a imprevisibilidade. O teste `tests/repair_minigame.luau` trava a janela do Rafael em ≤ 55 ms e a do Diego em ≥ 100 ms, então mexer nesses valores sem querer falha o teste.

**Conserto Relâmpago** dá `1` acerto de graça (`Streak.PowerBoostSteps`) e adianta o próximo teste. É fixo para todos — o poder do Diego não multiplica a vantagem que o atributo dele já dá. **Nunca completa sozinho**: se a sequência já está a um acerto de fechar, o poder é recusado e o cooldown não é gasto. Fora de um reparo, continua funcionando no chamado de socorro (ordem: reparo em andamento → rádio).

## Ruído

**Só o erro faz barulho.** Começar, continuar ou terminar um reparo não entrega ninguém.

O erro chama `NoiseService:EmitNoise` com a posição **do objetivo** (não a do jogador) e alcance `240..70` studs escalado pela Furtividade do personagem (faixa invertida: Furtividade alta encolhe o alcance). Valem as regras que já existiam: alcance máximo, chance de o som se perder com a distância e o embaralhamento da posição. Nada aqui fura `docs/SuperAudicao.md`.

## Pontos ligados hoje

| Tarefa | Onde |
| --- | --- |
| `RadioInstalar` | `RadioInstallSystem`, "Instalar peça" (uma sequência por peça) |
| `RadioPartida` | `RadioSiteSystem`, "Ligar gerador" |
| `RadioPainel` | `RadioSiteSystem`, "Ativar painel" |
| `SabotagemFio` | `SabotageSystem`, prompt "Reparar" de cada ponto sabotado |

**Abastecer** o gerador continua sendo "segurar E" (`HoldAbastecer`), fora do minigame. **Desligar** o gerador continua sendo um botão instantâneo. As duas etapas do fusível e o pedido de socorro **não** mudaram.

Cada tarefa tem `Enabled` (desligado, o ponto resolve na hora, com as mesmas validações) e, opcionalmente, `Required` para exigir mais ou menos de 3 acertos naquele ponto específico, em `RepairMinigameConfig.Tasks`.

## Som 3D do choque do gerador

**Qualquer erro** de minigame de reparo (nota vermelha ou teste ignorado) toca um choque **em 3D na posição do gerador** — instalar peça, ligar gerador, painel ou fio cortado. **Quem errou e o Monstro ouvem**; os outros sobreviventes não. O choque sempre vem do **gerador**, não de quem errou: se o erro acontece longe dele (além de `RollOffMaxDistance`), o som fica mudo pela distância.

Como funciona:

- O `RadioSiteSystem` registra a Part do gerador (atributo `MotorGerador`) em `GeneratorErrorSound.SetGenerator`. Em mapa antigo sem ela, o painel de partida faz o papel.
- A cada erro, o `RepairMinigameSystem` chama `GeneratorErrorSound.Play`. O servidor (`src/server/GeneratorErrorSound.lua`) só valida e avisa os destinatários: **quem errou** e o **Monstro**, se estiver vivo, na partida e dentro do alcance. Um `Sound` tocado no servidor dentro do Workspace seria ouvido por **todos**, então quem toca são os clientes.
- O cliente (`src/client/GeneratorErrorSoundController.client.luau`) cria o `Sound` **como filho da Part do gerador**, localmente em cada destinatário. Ele não replica, e não passa por `PlayerGui`, `SoundService` nem pela câmera.
- Por estar dentro de uma Part do Workspace, o Roblox calcula sozinho a direção e o volume a partir da câmera de quem ouve: gerador atrás soa atrás, à esquerda soa à esquerda, e o volume cai com a distância (`RollOffMode = InverseTapered`).
- O cooldown é **por gerador**: erros seguidos dentro da janela não empilham o som. O cliente repete a guarda e nunca toca o som por cima de si mesmo.
- É **adicional** ao ruído de posição do `NoiseService` (o ping da super audição, sujeito à Furtividade): aquele continua igual.

**Onde editar:**

| O quê | Onde |
| --- | --- |
| ID do som (`113653339826980`) | `AssetRegistry.Sounds.RadioSite.ErroGerador` |
| Volume | `GameConfig.RadioSite.ErroGerador.Volume` |
| Distância máxima (padrão 100 studs) | `GameConfig.RadioSite.ErroGerador.RollOffMaxDistance` |
| Distância de volume máximo | `GameConfig.RadioSite.ErroGerador.RollOffMinDistance` |
| Tamanho do emissor | `GameConfig.RadioSite.ErroGerador.EmitterSize` |
| Cooldown (padrão 3s, use 2 a 4) | `GameConfig.RadioSite.ErroGerador.Cooldown` |
| Ligar/desligar | `GameConfig.RadioSite.ErroGerador.Enabled` |
| Tirar **uma tarefa** do choque | `RepairMinigameConfig.Tasks.<id>.GeneratorShock = false` |

**"Errei e não tocou" — o que conferir:**

1. Ligue `GameConfig.RadioSite.ErroGerador.Debug = true`. O Output (servidor e cliente) mostra cada envio e o motivo de **não** ter tocado: cooldown, sem gerador registrado, gerador longe demais.
2. O cliente avisa com `warn` se o áudio **não carregou**. Áudio privado ou de outro dono falha em silêncio no jogo: ele precisa ser público ou pertencer ao dono da experiência.
3. Se você errou a mais de `RollOffMaxDistance` (100 studs) do gerador, o som existe mas fica mudo. Aumente esse valor se o rack ou o painel forem longe dele.
4. O remote novo (`GeneratorErrorSound`) precisa ser sincronizado pelo Rojo.

## Pose de interação

O prompt do minigame tem `HoldDuration = 0`, então nenhum `PromptButtonHoldBegan` dispara e a pose de "interagindo" (`FearPresentation`) não ligaria. O servidor marca o personagem com o atributo `Reparando` durante a sessão e `FearPresentation` o lê para manter a pose até o fim.

## Controles

| Plataforma | Segurar | Acertar o teste | Cancelar |
| --- | --- | --- | --- |
| Teclado | a tecla do prompt (**F** durante a partida, **E** fora dela) | a tecla do prompt ou **Espaço** | soltar a tecla |
| Controle | **ButtonX** | ButtonX ou ButtonA | soltar |
| Celular | implícito (basta ficar perto) | botão grande "BATER" | o **✕** ao lado |

Durante o reparo o **Espaço** e o **ButtonA** são afundados (`Sink`) para não pular. A tecla do prompt continua passando, então os poderes seguem acessíveis. A tecla mostrada é lida do próprio `ProximityPrompt`, então acompanha o remapeamento local E → F do HUD de poderes.

## Cancelamento

Soltar a tecla, sair do alcance, perder a linha de visão, **tomar dano**, ser atordoado/agarrado/amarrado, morrer, o `canStart` do objetivo passar a recusar, ou o cliente parar de confirmar que ainda está segurando (1,6s).

**A sequência é da sessão e se perde ao cancelar** — "3 seguidas" só faz sentido dentro de uma tentativa contínua. Dois sobreviventes no mesmo ponto têm uma sequência cada um; o acerto ou o erro de um não afeta o outro. O que já foi *concluído* (uma peça instalada, o fio consertado) permanece, claro.

## Autoridade

O cliente manda exatamente três coisas: `Hold` (confirma que ainda segura), `Release` e `Hit(testId, elapsed)`. **Nunca sequência, nota, alvo ou ruído.**

- Os parâmetros de cada teste (incluindo o tamanho da área verde, que depende do Reparo) são sorteados só no servidor.
- Um token por sessão descarta mensagem atrasada de um reparo anterior.
- Papel, vida, partida, alcance, linha de visão e o `canStart` do objetivo são revalidados **a cada tique**.
- `elapsed` é o instante em que o jogador apertou, no relógio do servidor. Só é aceito se bater com a hora de chegada dentro de `Scoring.MaxInputLag` (0,22s de atraso de rede) e não estiver no futuro (`FutureSlack`, 0,05s); fora disso vale a chegada. **Limite conhecido:** a nota depende de um instante que o cliente informa, então um cliente alterado ainda pode calcular o instante certo e enviá-lo dentro dessa tolerância. Reduzir `MaxInputLag` estreita esse espaço, mas penaliza quem tem ping alto.

## Verificação

```
python3 tests/run_repair_minigame.py /caminho/luau
```

Cobre, com os módulos reais e serviços determinísticos (o marcador oscila, então os testes esperam o marcador entrar na nota em vez de calcular o instante): autoridade da abertura; **ficar parado 90s não conclui (Rafael nem Diego)** e cada teste ignorado faz barulho; 3 acertos seguidos concluem; erro, amarelo e teste expirado zeram a sequência; ruído (posição, autor, intensidade, alcance); o tranco antes do próximo teste; instante mentido ou no futuro; cancelamento por soltar/afastar/dano/morte/stun/objetivo; o poder (1 acerto, nunca o último, igual para todos); sequências independentes em dupla; a diferença de dificuldade Rafael × Diego (com as janelas travadas); e limpeza.

Os testes **não** simulam física, entrada nem renderização, e **não** medem se a dificuldade está no ponto certo para um humano. No Studio, em multiplayer, ainda falta: jogar com o Rafael e com o Diego e sentir a diferença; dano e stun durante o reparo; a sequência completa da estação; dois jogadores no mesmo ponto; desktop, celular e controle; e confirmar que o Monstro recebe o ruído **só** quando alguém erra.

Os sons usam fallbacks nativos do Roblox (`SOUNDS`, no topo do controller). Troque pelos ids da experiência quando tiver os definitivos.
