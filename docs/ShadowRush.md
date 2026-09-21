# F — Desaparecer / Shadow Rush

F, L1 ou botão touch **Desaparecer** inicia a habilidade existente. Um segundo toque pede materialização. Esta revisão altera a apresentação; `server/ShadowRush.lua`, `ShadowRushRules.lua`, remotes e balanceamento permanecem intactos.

## Arquitetura verificada antes da alteração

- `ShadowRush.Init()` valida início/interrupção, cooldown, chão inicial, fraqueza e bloqueios. O servidor publica `ShadowRushState`, `ShadowRushPhaseAt`, `ShadowRushBusy`, `ShadowRushToken`, velocidades de referência e `ShadowRushExitHidden`.
- O RemoteEvent **ShadowRush** já recebe `Start`/`Stop` e devolve `Pass`/`Rejected`. Não existe novo remote de VFX. Foram removidos do cliente os pedidos antigos `Move`, que o servidor atual já ignorava.
- O movimento atual usa o **Humanoid e controle nativo**, com velocidade validada pelo servidor. O servidor verifica deslocamento, orçamento de distância, paredes e limites; não ancora o personagem nem calcula o steering. `Crouching` compõe a velocidade prevista usando `Rules.Speed`.
- `CharacterPresentation` cria o Animator no servidor. O `Animate` existente continua sendo o dono da animação local; durante `EnteringShadow` e `ShadowRush` ele interrompe idle/walk/run para a forma flutuar. `Crouching` para sprint/jog durante o poder.
- `Crouching` continua sendo o único dono de `Camera.FieldOfView`: recebe o atributo local `ShadowRushFOV`. Agora o cliente mede a velocidade horizontal real; o antigo `ShadowRushSpeed` não era mais publicado.

| Configuração mecânica preservada | Valor |
| --- | --- |
| Entrada | 0,16 s |
| Estado ativo | 5 s |
| Velocidade máxima | 75 studs/s |
| Aceleração | 0,28 s |
| Materialização/desaceleração | 0,24 s |
| Recovery | 0,12 s |
| Cooldown | 25 s |
| Shadow Pass | 8 Fear a até 12 studs; cooldown individual de 6 s |

Estados: `Idle → EnteringShadow → ShadowRush → Materializing → Recovery → Idle`. Colisão, gravidade, dano, stamina, luz, Fear, cooldown e bloqueios de combate continuam nas implementações anteriores.

## Visual nos clientes

`ShadowRushVFX` mantém um handle reversível por personagem recebido por streaming. O controlador usa os atributos existentes, inclusive para observadores que entram no alcance depois do início.

- **Entrada:** arcos interrompidos de energia laranja-avermelhada expandem do corpo até aproximadamente 7 studs; fumaça escura, pequenos resíduos e um PointLight sem sombras acompanham a ruptura. A cauda de 0,32 s é somente visual e não aumenta a entrada mecânica de 0,16 s.
- **Forma de fumaça:** durante a locomoção o rig material fica praticamente invisível e dá lugar a um volume humanoide de fumaça preta em três camadas. A massa central, a pluma superior e a cauda rasteira usam densidades, tamanhos, elevação e arrasto diferentes. A aceleração reage à velocidade horizontal, então a fumaça se comprime e deixa resíduos no sentido oposto ao movimento. Um Highlight muito discreto mantém apenas a leitura sobrenatural da forma. A `HumanoidRootPart`, hitboxes e partes físicas não mudam.
- **Rastro:** partículas não ficam presas ao corpo; permanecem no ponto de emissão e se dissipam em 0,2–0,45 s. Trails duram 0,22 s, somente no detalhe próximo e em movimento.
- **Retorno:** os arcos e fios se contraem, a emissão de ruptura aponta para dentro e `Rules.Hidden` restaura a aparência no tempo original. Um cancelamento externo de personagem vivo permite fade visual de 0,24 s, sem prolongar bloqueios de gameplay. Morte, remoção do root, streaming-out e destruição do script fazem limpeza imediata.
- Transparência, cor, CastShadow, emissores/luzes originais, nomes e volumes são restaurados. Descendentes recebidos/removidos durante a habilidade também são tratados. O fim normal não repete o som/onda de saída.

Somente o cliente do monstro cria `ColorCorrectionEffect`, `BloomEffect` e `BlurEffect` sob a **CurrentCamera**. A visão reduz saturação, escurece levemente, aumenta contraste e usa matiz fria com a energia quente no mundo. Vinheta suave, blur máximo de 1,4 e até +8° de FOV preservam a legibilidade. O shake angular de ativação dura 0,22 s e tem amplitude máxima de 0,48°. O offset anterior é removido antes da câmera normal; a apresentação é aplicada depois dela. Nenhum `Lighting` compartilhado ou efeito de outro sistema é modificado.

## Animação e áudio — configuração

Em `GameConfig.Monster.ShadowRush`:

```lua
ShadowRushAnimationId = "", -- a fumaça animada apresenta a locomoção sem deformar o rig
ShadowRushEnterSoundId = "", -- Sound espacial de ativação
ShadowRushLoopSoundId = "rbxassetid://9120699200", -- Sound durante a locomoção sombria
ShadowRushExitSoundId = "",  -- Sound espacial de retorno
ShadowPassSoundId = "",     -- feedback já existente ao sobrevivente
SoundVolume = 0.65,
SoundMaxDistance = 90,
EnterSoundPlaybackSpeed = 0.72,
```

**O ID fornecido, `9120699200`, aparece no Studio como Sound:** “Whoosh By Reverse Thick Airy Swoosh In 5 (SFX)”, duração de 6,731 s. Ele fica em `ShadowRushLoopSoundId` e toca somente durante a fase `ShadowRush`, quando o monstro está se locomovendo na forma sombria. Ao iniciar `Materializing` ou encerrar o efeito, o loop é parado e limpo pelo cliente.

Ele não foi mantido em `AnimationId`, pois esse tipo de asset não serve como animação. A locomoção não usa uma track corporal: o `Animate` interrompe idle/walk/run, enquanto as três camadas de fumaça produzem movimento contínuo sem passos e sem deformar as juntas R6.

Com AnimationId preenchido, o `Animate` carrega uma única track por rig no Animator já existente, usa prioridade `Action`, loop e transições de entrada/saída. O proprietário inicia a track; os observadores usam sua replicação, sem carregar cópias. Esse é o fluxo documentado para [animações em personagens de jogadores](https://create.roblox.com/docs/reference/engine/classes/Animator). Falha síncrona de carregamento mantém a locomoção original. Permissão de uso do asset e compatibilidade com R6 precisam de playtest.

Os campos aceitam `"rbxassetid://ID"` ou números em string. Vazio desativa áudio; nenhum som de terceiros foi escolhido automaticamente. A ativação tem velocidade de reprodução configurável e Equalizer com graves realçados. Som é criado localmente sob o root, com atenuação espacial e limpeza ao terminar. Todos os ajustes de cor, partículas, luz, LOD, pós-processamento e câmera ficam em **`ShadowRush.Visual`**.

## Orçamento e LOD

| Distância da câmera | Apresentação |
| --- | --- |
| Até 75 studs | Corpo dissolvido, três camadas de fumaça, fios, trails, 12 arcos, luz breve; atualização até 30 Hz |
| 75–170 studs | Corpo dissolvido, fumaça reduzida a 42% e sem trails; até 20 Hz |
| Acima de 170 studs | Apenas aparência escura/translúcida do rig, a cada 0,15 s; sem objetos de partículas/luz/beams |
| Mobile ou qualidade gráfica salva ≤ 4 | Orçamento médio mesmo perto (8 arcos, 2 fios), sem trails |

O dono sempre recebe a transformação próxima, respeitando a redução para mobile. Os emissores e attachments são alocados uma vez por handle/entrada no alcance e reutilizados; não são criados a cada frame. Não há conexões RenderStepped por monstro, raycasts de VFX ou remotes enviados por frame. Partes visuais são locais, ancoradas e com `CanCollide`, `CanTouch`, `CanQuery` e `CastShadow` desligados. Os efeitos pessoais só existem enquanto a visão está ativa ou terminando seu fade.

## Verificação

```sh
python3 tests/run_shadow_presentation.py /caminho/para/luau
rojo build -o /tmp/meujogo-shadow-visual.rbxlx
```

A suíte executa os módulos, controlador e trecho real do `Animate` com dublês determinísticos: 25 ciclos, transparência/cor/áudio restaurados, entrada e contração, parada precoce, cancelamento externo, LOD, streaming, orçamento mobile, ausência de replay de explosão, áudio configurado, isolamento proprietário/observador, troca de câmera, cancelamento do shake, morte e limpeza de conexões/HUD/tracks. IDs sintéticos de teste não entram no projeto.

Compilação Luau e build Rojo passaram. A suíte antiga `run_shadow_rush.py` já falhava antes desta alteração: seu dublê de CFrame não implementa `Angles`, agora usado em GameConfig. Ela também contém expectativas da versão anterior de movimento. Não foi alterada para acomodar esta revisão visual.

**Ainda requer Studio:** revisão estética renderizada, multiplayer real/StreamingEnabled, desempenho em aparelhos e aprovação dos assets de áudio/animação. Foi possível ler as propriedades do Sound no Studio; a tentativa posterior de controlar a janela retornou `noWindowsAvailable`, impedindo concluir o playtest visual nesta sessão.

## Playtest

1. Sincronize e reinicie o Play, com monstro e sobrevivente. Use F/L1/touch e observe a explosão leve de entrada, o volume de fumaça preta em movimento, resíduos e retorno.
2. Compare os clientes: ambos veem a transformação; somente o monstro recebe visão, blur, vinheta do poder, FOV e shake. O feedback preexistente de Shadow Pass continua separado.
3. Teste parado, em movimento, contra paredes e na água; confirme as velocidades e bloqueios anteriores. Pare com F durante a entrada e no meio do rush.
4. Observe a 30, 110 e 250 studs; aproxime-se de uma habilidade já em andamento. Não deve surgir uma explosão de entrada atrasada. Teste qualidade baixa e emulador mobile.
5. Interrompa por morte, respawn, fim de round, troca de papel e `ShadowRush.Cancel`. Após o fade, não deve sobrar alteração de aparência/câmera, partículas ou loop sonoro.
6. Preencha IDs válidos de Animation R6/Sounds, confira replicação da track e atenuação espacial. Ajuste visão no mapa real de dia/noite, sem perder a leitura do caminho.
