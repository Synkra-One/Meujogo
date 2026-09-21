# Teleporte do Monstro — o Mapa e a Fenda

Poder sobrenatural do Monstro. **Q** abre o **mapa da ilha** (visão de cima);
clicar num ponto do mapa abre uma fenda nos pés dele, ele é **engolido**, e
**emerge** de uma segunda fenda exatamente no lugar clicado. Não é "fica
transparente e reaparece" — a posição real do rig e os VFX trabalham juntos
pra esconder o teleporte, e a fenda do destino começa a surgir *antes* do
Monstro sair (antecipação pra quem está por perto).

## O mapa

O mapa **não é decorativo**. Ele é amostrado de `Tools/IslandLayout` — a mesma
matemática que escreveu o terreno — então a proporção é 1:1 com o mundo e
clicar em `(u, v)` devolve o `(x, z)` real (round-trip com erro 0 stud).

- `server/IslandMap.lua` amostra uma grade 100×100 cobrindo
  `±CoastRadiusMax × 1.12` (~±918 studs), classifica cada célula
  (mar fundo / mar / raso / praia / campo / floresta / terra / rocha / pico /
  lago), aplica **hillshading** (luz do noroeste) pro relevo aparecer, funde a
  grade em ~1700 **retângulos** e publica tudo num StringValue em
  `ReplicatedStorage.IslandMapData`.
- O mar escurece conforme se afasta da costa (banda por **distância da costa**,
  não por profundidade — a batimetria da ilha muda em ~1 stud, menos de uma
  célula do mapa).
- `Modules/IslandMapUI.lua` (renomeado de `MonsterMapUI.lua` -- ver
  [MapaSobrevivente.md](MapaSobrevivente.md)) desenha: relevo, **trilhas** por
  cima (na grade elas sumiriam), POIs com losango + nome, a caverna, onde o
  Monstro está (marcador pulsando), mira que segue o mouse mostrando as
  coordenadas e ficando vermelha sobre água, grade de referência, rosa dos
  ventos (norte = −Z = topo) e **barra de escala de 200 studs**. O mesmo
  módulo agora também roda em modo `"view"` pro mapa do Sobrevivente/Espião
  (tecla M) e desenha a camada de itens descobertos -- só o modo `"teleport"`
  (Monstro/Q) usa a mira e o clique deste arquivo.
- Enquanto o mapa está aberto: o movimento é travado, o mouse é solto do
  centro (via atributo `CursorLivre` no LocalPlayer — o mesmo gancho da tela
  de escolha de personagem, que o `CustomShiftLock` respeita; render step é só
  rede de segurança), a mira segue o mouse por poll do cursor absoluto todo
  frame (não depende de eventos de movimento, que somem se o shift-lock
  reprender o cursor por um frame), e o clique **não** vira golpe
  (`MonsterController` respeita `MapaAberto`).
- A câmera cinematográfica soma um delta de FieldOfView **absoluto** (`base +
  delta`), nunca `FieldOfView + delta` frame a frame — o pacote `Crouching` só
  reescreve o FOV na troca de sprint/agachar, então acumular estourava o zoom
  até o mínimo. O FOV é devolvido ao valor pré-teleporte ao final.
- Fechar: **Q** de novo ou **botão direito**.
- Se os dados do mapa não chegarem, a habilidade cai automaticamente pro modo
  antigo (mira com a câmera) em vez de ficar inutilizável.

## Sequência

```
Q -> mapa abre  ->  clique num ponto  ->  (x, z) real vai pro servidor
ativação (servidor valida destino + inicia cooldown)
 → [OpeningRift]  fenda de entrada abre (pequena → grande, com fade)   RiftOpenDuration
 → [Entering]     Monstro afunda + some (sink + transparência)         EnterDuration
 → [Traveling]    "vazio"; a entrada fecha; a fenda do DESTINO abre    TravelDuration
                  DestRiftLeadTime antes do Monstro sair               (antecipação)
 → teleporte real (Monstro invisível e enterrado — ninguém vê o "pop")
 → [Exiting]      Monstro emerge + reaparece                           ExitDuration
 → fenda do destino fecha (assíncrono)                                 RiftCloseDuration
 → [Recovery]     tonto: sem atacar/reativar                           PostTeleportRecovery
 → [Idle]
```

Estados no **character** (Attributes, replicam sozinhos): `TeleportState`
(`OpeningRift`/`Entering`/`Traveling`/`Exiting`/`Recovery`, ausente = Idle) e
`TeleportBusy` (`true` durante toda a habilidade).

## Arquivos

**Criados**

| Arquivo | O quê |
|---|---|
| `src/ReplicatedStorage/Modules/IslandMapData.lua` | Formato + matemática do mapa: paleta, fusão em retângulos, encode/decode e as conversões mundo↔mapa. Compartilhado server/cliente. |
| `src/server/IslandMap.lua` | Amostra a ilha de `IslandLayout`, aplica hillshading, funde em retângulos e publica em `ReplicatedStorage.IslandMapData`. |
| `src/ReplicatedStorage/Modules/IslandMapUI.lua` (era `MonsterMapUI.lua`) | Desenha e opera o mapa (relevo, trilhas, POIs, mira, escala, marcador do Monstro/você, itens descobertos). Roda no cliente, em modo `"teleport"` (Monstro) ou `"view"` (Sobrevivente/Espião -- ver [MapaSobrevivente.md](MapaSobrevivente.md)). |
| `src/server/MonsterTeleport.lua` | Autoridade: valida ativação/destino/cooldown, roda a máquina de estados, faz o teleporte real, limpa tudo. Carrega o asset da fenda (InsertService, só server) e publica em `ReplicatedStorage.RiftAssets.Template`. |
| `src/ReplicatedStorage/Modules/RiftVFX.lua` | Monta/anima/limpa **uma** fenda (asset + partículas + luz + distorção). Roda no cliente, tudo com TweenService. Fenda de reserva (só `Part`) se o asset não carregar. |
| `src/client/RiftVFXController.client.luau` | Recebe os "beats" de `Remotes.RiftVFX` (só pra quem está perto), chama `RiftVFX`, toca os sons 3D. |
| `src/client/MonsterTeleportController.client.luau` | Input do Monstro (mira + tecla), desliga o controle de movimento durante a habilidade, câmera cinematográfica, som de charge, aviso de "destino inválido". |
| `src/ReplicatedStorage/Remotes/MonsterTeleport.model.json`, `RiftVFX.model.json` | RemoteEvents. |

**Modificados**

| Arquivo | Mudança |
|---|---|
| `GameConfig.lua` | `GameConfig.Monster.Teleport` — **todos** os tempos/escala/alcance/cooldown/IDs de animação. |
| `AssetRegistry.lua` | `AssetRegistry.RiftTeleport` — AssetId da fenda + 6 SoundIds (vazios). |
| `Remotes.lua` | contratos de `MonsterTeleport` e `RiftVFX`. |
| `MonsterCombat.lua` | não ataca enquanto `TeleportBusy`. |
| `MonsterController.client.luau` | não golpeia com o mapa aberto (`MapaAberto`) nem durante o teleporte. |
| `MovementWatchdog.client.luau` | respeita `TeleportBusy` (HRP ancorado é de propósito). |
| `HUDController.client.luau` + `MainHUD.model.json` | `MonsterCooldownFrame` com o cooldown do teleporte. |
| `init.server.luau` | `safeInit("MonsterTeleport", ...)` depois de MonsterCombat. |

## Onde configurar

`GameConfig.Monster.Teleport` (`src/ReplicatedStorage/Modules/GameConfig.lua`):

- **Timings**: `RiftOpenDuration`, `EnterDuration`, `TravelDuration`,
  `DestRiftLeadTime`, `ExitDuration`, `RiftCloseDuration`,
  `PostTeleportRecovery`, `TeleportCooldown`, `FailureCooldown`, `SafetyTimeout`.
- **Alcance/destino**: `MaxRange`, `MinRange`, `MaxSlopeCos`, `BoundsMargin`,
  `ClearanceRadius`, `ClearanceHeight`, `GroundSnapUp/Down`,
  `DestinationSearchRadius/Step/Samples` (busca automática de uma posição
  livre próxima quando o ponto exato estiver bloqueado).
- **Escala**: `RiftScale` (multiplicador extra), `RiftWidthFactor` (a fenda é
  ~`RiftWidthFactor` × a altura REAL do rig, medida em runtime), `SinkDepth`.
- **Orientação do asset**: `RiftAssetFaceAxis` (`"auto"` mede e deita a menor
  dimensão no chão — force `"Y"`/`"Z"`/`"X"` se renderizar de lado),
  `RiftExtraRotationDeg` (ajuste fino em graus), `RiftGroundOffset` (<0 crava
  no chão), `RiftUpright` (fenda vertical em vez de deitada).
- **Rede/visual**: `VFXBroadcastRadius` (só clientes a até isso recebem VFX),
  `RiftLightBrightness` (PointLight sutil; 0 = sem luz), `RiftLightRangeFactor`.

Cores/taxas de partícula: `RiftVFX.Style` (topo de `Modules/RiftVFX.lua`).

### AnimationIds (opcionais — o sistema funciona sem)

`GameConfig.Monster.Teleport.TeleportEnterAnimationId` e
`TeleportExitAnimationId`. Vazio (`""`) = usa só o afundar + fade, que funciona
em **qualquer rig**. Se tiver animações R6 próprias, cole o `rbxassetid` aí —
elas tocam por cima do movimento, não substituem nada. **Não invente ids.**

### SoundIds

`AssetRegistry.RiftTeleport.Sounds` (`src/ReplicatedStorage/Modules/AssetRegistry.lua`):
`TeleportCharge`, `RiftOpen`, `RiftEnter`, `RiftTravel`, `RiftExit`,
`RiftClose`. Todos vazios (`""`) por padrão — o sistema roda sem som. Os sons
de fenda tocam em **3D** na posição da fenda (raio ~95 studs): um Sobrevivente
perto do destino ouve algo surgindo antes do Monstro sair.

### Asset da fenda

`AssetRegistry.RiftTeleport.AssetId = 16376740571`. O servidor carrega uma vez
no boot e loga no Output o tamanho medido e o `FaceAxis` escolhido:
```
[MonsterTeleport] Fenda: asset 16376740571 carregado -- tamanho (X, Y, Z), faceAxis=Y, largura natural W.
```
Se não carregar (privado/moderado, ou fora do modo de edição), loga um aviso e
**o cliente usa a fenda de reserva** (disco preto + aro carmim + rachas) — tudo
o mais funciona igual. Trocar o visual = trocar o `AssetId`, nada mais.

## Autoridade / rede

- **Servidor**: ativação, destino permitido (clamp de alcance + raycast no
  terreno real + rampa + limites do mapa + água + espaço livre pro rig),
  busca lateral automática quando o ponto exato está bloqueado, cooldown,
  posição final, estado. O cliente **nunca** teleporta sozinho — ele só manda
  um ponto mirado como sugestão.
- **Cliente**: os VFX. O servidor manda "beats" (`open`/`enter`/`emerge`/
  `close`/`cancel`) por `Remotes.RiftVFX:FireClient` **só pros jogadores a até
  `VFXBroadcastRadius`** da fenda. Nenhum ParticleEmitter/tween é controlado
  pelo servidor frame a frame; a posição do rig usa TweenService nativo (HRP
  ancorado, membros seguem pelos Motor6D) e as fases usam `task.wait`.

## Segurança / cleanup

- Uma sessão por vez (só existe um Monstro); reativar durante a habilidade é
  ignorado.
- Ponto inválido sem coordenadas utilizáveis ou sem qualquer terreno seguro
  dentro das margens → `cancel` com motivo, cooldown curto
  (`FailureCooldown`), nenhuma sessão iniciada. Obstáculos pontuais são
  resolvidos pela busca lateral antes de chegar neste caso.
- Aborta e restaura (desancorar, transparência, AutoRotate, assentar no chão)
  se: Monstro morre/é eliminado, character removido, partida termina, jogador
  sai, ou `SafetyTimeout` estoura.
- Cada fenda (cliente) tem tweens, emitters, luz, sons e conexões próprios e se
  autodestrói depois do rastro; `HardMaxLifetime` (30 s) é a rede de segurança.
  `RoundEnded` limpa qualquer fenda presa.
- O asset original nunca é alterado — sempre `:Clone()`.

## Como testar no Studio

1. `rojo serve` / sincronize. Confirme no Output do servidor as duas linhas:
   `[IslandMap] Mapa pronto ... 100x100 células -> N retângulos, alcance +-918 studs`
   e `[MonsterTeleport] Fenda: asset ... carregado` (ou o aviso de reserva).
2. Entre numa partida como **Monstro** (`GameConfig.Testing.ForceRole = "Monstro"`
   ou o painel de dev, se estiver ligado).
3. Aperte **Q**: o mapa da ilha abre. Confira que a **forma da ilha bate** com
   o mundo, que os POIs estão nos lugares certos, e que o marcador vermelho
   (você) está onde você realmente está. Passe o mouse — as coordenadas na
   mira são as do mundo; sobre o mar a mira fica vermelha.
4. **Clique num ponto em terra.** Observe:
   - o mapa fecha e a fenda abre nos pés (pequena → grande, partículas escuras
     puxadas pra dentro, luz sutil);
   - o Monstro afundando + sumindo (não instantâneo);
   - a fenda do destino aparecendo **antes** de ele sair;
   - o Monstro emergindo **exatamente no ponto clicado**, a fenda fechando
     (encolhe + perde intensidade + recolhe partículas), e o controle/golpe
     voltando.
5. Clique em árvore, parede ou outro ponto obstruído: o servidor procura uma
   posição segura próxima, mantendo o teleporte ativo. A altura é sempre
   calculada pelo terreno, nunca pela copa de uma árvore.
6. HUD: `MonsterCooldownFrame` mostra "Teleporte (Q): 00:30". O próprio mapa
   mostra "recarregando: Ns" enquanto estiver em cooldown.
7. **Multiplayer** (2+ clientes): com um segundo cliente perto do destino,
   confirme que ele vê a fenda surgir e ouve os sons (quando houver ids), e que
   o Monstro aparece sincronizado. Com o segundo cliente longe (> `VFXBroadcastRadius`),
   ele não recebe nada.
8. **Casos**: clicar no mar / numa parede / num teto baixo → o servidor tenta
   um ponto seguro próximo ou retorna pela direção do salto. Matar/eliminar o Monstro no meio →
   tudo limpa, sem fenda presa, sem Monstro invisível.
9. Se a fenda renderizar de lado/em pé, ajuste `RiftAssetFaceAxis` /
   `RiftExtraRotationDeg` / `RiftUpright` no GameConfig.
10. Se você regerar a ilha com outra seed, rode
   `require(game.ServerScriptService.Server.IslandMap).Generate()` na Command
   Bar pra o mapa acompanhar (ou só reinicie o servidor).

## Verificação automática

- `rojo build` e `luau` (sintaxe) em todos os arquivos novos + editados.
- Smoke test do **mapa**: round-trip mundo↔mapa com **erro 0 stud**, centro e
  cantos batendo com o mundo, os 9 POIs dentro do enquadramento e em terra
  firme, distribuição de terreno coerente (mar/praia/vegetação/lago presentes),
  encode/decode de 10.000 células reconstruindo idêntico, paleta completa.
- Smoke test da `RiftVFX` (build/open/enter/emerge/close/cancel/destroy, flat e
  upright) e do `MonsterTeleport` (ativação, sequência completa, teleporte pro
  destino exato, restaura visível/desancorado, rifts fecham, destino inválido
  rejeitado, mira-em-si rejeitada, dupla ativação bloqueada, abort no fim de
  partida) — no scratchpad da sessão.
