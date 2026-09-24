# Detecção de batimentos do monstro

Configuração: `src/ReplicatedStorage/Modules/HeartbeatConfig.lua`.
Inicialização: `HeartbeatDetection`, depois de `FearSystem` e `NoiseService`.

O servidor lê exclusivamente `FearSystem.GetFear`; não há uma segunda barra,
atributo ou simulação de medo. Reutiliza `NoiseService.GetActiveRoot`,
`StatScaling.NoiseState` (velocidade horizontal real) e o atributo existente de
Furtividade via `StatScaling.Of/Lerp`. Não usa flags locais de agachamento/corrida.
Parado, inclusive agachado parado, usa multiplicador neutro de movimento;
agachamento em movimento é reconhecido pela mesma faixa acústica dos passos.
`PowerFearHidden` suspende a detecção, preservando o poder já existente.

Um snapshot completo a cada 0,2 s vai por `HeartbeatDetected:FireClient` aos
monstros vivos, em rodada, fora da seleção, e cada sobrevivente recebe somente
o próprio batimento em um canal local separado. Outros sobreviventes nunca
recebem o snapshot. Cada monstro tem seu próprio alcance e raycast.
Sobreviventes mortos, eliminados, fora da rodada, em seleção ou com papel
diferente são descartados. Não existe `OnServerEvent` neste canal.
Os pings antigos de passos e pânico continuam com seu contrato original.

Medo precisa ser **maior que 25** e distância **menor que 96 studs** por padrão.
Medo normalizado, distância, furtividade, velocidade real e fração de vida perdida
determinam a intensidade. Um raycast entre raízes, ignorando os dois personagens,
água e partes sem colisão, aplica atenuação por obstáculo sólido. A presença de
parede reduz a intensidade; não bloqueia nem remove o pulso através da parede.
Múltiplas paredes usam a mesma atenuação binária, sem simulação de espessura.

No cliente do monstro há um único registro por sobrevivente: emissor 3D com Attachment/Sound,
clone 3D do coração preso localmente ao peito e Highlight vermelho. O coração
fica 0,28 studs à esquerda e 0,52 studs à frente do torso, com valores editáveis
em `HeartChestOffset`. O Highlight do coração e o da aura usam
`DepthMode = AlwaysOnTop`, então continuam legíveis atrás de paredes. Eles são
criados localmente, nunca no Workspace do servidor. O template inerte em
ReplicatedStorage não representa nenhum jogador e não produz efeitos.

O som usa `rbxassetid://9043365842`. Som e animação compartilham a mesma fase e
BPM, de 62 a 156. Um ciclo é reproduzido de cada vez, sem sons sobrepostos por
alvo. A reprodução não espera `IsLoaded`: o Roblox agenda o áudio enquanto o
asset carrega, impedindo que o primeiro batimento seja perdido. `MinVolume` dá
presença sonora a um pulso já detectado e desce suavemente até zero no fade.
O Volume já inclui distância validada pelo servidor; o rolloff local fica além
do alcance para manter a direção pelo listener da câmera sem aplicar a mesma
perda de volume duas vezes. Não altera o listener global do jogo.
`AudioStartTime`, `AudioCycleDuration` e `AudioReferenceBPM` definem o trecho
lub-dub do asset. **Audicionar no Studio e ajustar esses três campos se necessário**;
não foi possível medir o conteúdo do áudio no runner local. Falha/permissão de
áudio não bloqueia a apresentação visual, nem inicia downloads em cada pulso.

O coração cresce de 0,38 a 0,68 studs no peito; a opacidade e a aura seguem uma
curva que sempre volta a zero entre pulsos. A aura é mais lenta e menos intensa
que o coração para não transformar o alvo em um marcador permanente. Redução do
medo suaviza volume/intensidade/BPM; ausência no snapshot ou saída do alcance
inicia fade de 0,65 s. O emissor congela na última posição autorizada durante
esse fade. Ausência de snapshots por 1,2 s
também inicia fade. Morte, respawn, troca de papel, saída e fim de rodada limpam
os efeitos. Um render loop atende todos os alvos e é desconectado quando vazio.
Não há controles de teclado/touch: o comportamento é passivo em PC e mobile.

O cliente do próprio sobrevivente cria somente um `Sound` local no peito, usando
a mesma intensidade, BPM e fade calculados pelo servidor. Ele não cria coração,
aura ou Highlight; portanto o sobrevivente ouve a própria reação, enquanto os
demais sobreviventes continuam sem áudio e sem marcador.

## Modelo de coração

O servidor tenta carregar **1994009448** uma vez com InsertService, sem bloquear
a inicialização. Copia somente partes e malhas/texturas inertes; scripts, sons,
constraints e emissores do catálogo não são publicados. Se não puder carregar,
o cliente usa um coração procedural 3D feito de duas cúpulas e uma ponta.

Para usar o asset manualmente, insira-o pelo Studio, coloque o Model/Part em
**ServerStorage.HeartbeatHeart** e reinicie o teste. Este modelo tem prioridade
sobre o download. Para persistir com Rojo, exporte como
`src/ServerStorage/HeartbeatHeart.rbxmx`. A geometria deve estar orientada para
ser vista de frente no eixo +Z. O tamanho é enquadrado automaticamente.
Se o download terminar depois da criação de um fallback, o template será usado
na próxima criação do efeito.

## Verificação

Executar `python3 tests/run_heartbeat.py`, `python3 tests/run_noise.py` e
`python3 tests/run_fear.py`. O primeiro executa os módulos reais com doubles de
serviços Roblox: valida autoridade, filtros, destinatários, raycasts, fatores,
sanitização do modelo, duplicação, fades, sincronização de fase, limpeza e
cadência em 20/60 Hz. Não simula renderização, espacialização acústica, permissões
de assets ou rede/streaming reais. O build Rojo também deve passar.

No Studio, abrir Server & Clients com um monstro e pelo menos dois sobreviventes.
Para fixar medo durante um teste, usar **somente a Command Bar do servidor**:

```lua
local fear = require(game.ServerScriptService.Server.FearSystem)
local p = game.Players:FindFirstChild("Player2") -- sobrevivente ativo do teste
fear.ReduceFear(p, 100)
fear.AddFear(p, 60, "HeartbeatStudioTest")
```

O FearSystem continua atualizando normalmente; repetir para comparar valores.

| Cenário no Studio | Resultado esperado |
| --- | --- |
| Medo 10, 26, 60, 100 a 12 studs | Ausente, quase invisível, pulsos curtos, pulsos mais fortes e rápidos |
| Parede sólida entre ambos | Som atenuado; coração e aura continuam visíveis em pulsos |
| Alvo à esquerda/direita e câmera girando | Origem sonora acompanha a posição, com fones estéreo |
| Distância 12, 80, 96 e 110 studs | Atenuação crescente; fade ao atingir/sair do limite |
| Correr vs. agachar em movimento | Corrida intensifica; agachamento atenua, com mesma furtividade |
| Mais furtividade ou vida baixa | Furtividade reduz; ferimento aumenta |
| Dois sobreviventes assustados | Um som/coração/aura por alvo, sem clones extras ao atualizar |
| Câmeras dos outros sobreviventes/espião/espectador | Nenhum novo som, coração ou aura desta detecção |
| Sair e entrar no alcance durante fade | Reutiliza o registro sem duplicar |
| Morrer, respawn, trocar papel, sair, encerrar rodada | Sem sons ou marcadores remanescentes |
| Perder streaming do alvo | Limpa o efeito; retoma somente com personagem e snapshot válidos |
| Device Emulator + dispositivo mobile real | Mesma cadência, sem dependência de input; verificar custo e mix de áudio |

Referências oficiais usadas para a apresentação:
[Highlight](https://create.roblox.com/docs/reference/engine/classes/Highlight),
[Sound](https://create.roblox.com/docs/reference/engine/classes/Sound) e
[InsertService](https://create.roblox.com/docs/reference/engine/classes/InsertService).
