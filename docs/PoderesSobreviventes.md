# Poderes dos sobreviventes

Os sete personagens usam os campos `PowerId1/PowerId2` de `CharacterData.lua`, com os IDs e cooldowns solicitados. `CharacterData[characterId]` e `GetById(characterId)` consultam o mesmo registro.

O Rojo já mapeia `src/server` para `ServerScriptService.Server`; por isso o sistema fica em `src/server/SurvivorPowerSystem.lua`, sem duplicar a árvore do projeto.

As verificações espaciais usam as APIs documentadas de [WorldRoot: Blockcast e consultas de volume](https://create.roblox.com/docs/reference/engine/classes/WorldRoot); a interação do rádio usa os eventos de [ProximityPrompt](https://create.roblox.com/docs/ui/proximity-prompts), com validação adicional no servidor.

## Controles e apresentação

Q ativa o primeiro poder; E ativa o segundo. Os botões também aceitam clique/toque. Enquanto o HUD do sobrevivente está ativo, os prompts de interação que usavam E passam localmente para F e voltam à tecla original ao sair da partida/papel. No celular, o painel deixa espaço para o botão de pulo.

`StarterGui/SurvivorPowersHUD` é preenchido por `SurvivorPowersController`: dois botões circulares, nome legível, tecla, overlay e segundos restantes. O cliente consulta timestamps replicados pelo servidor; pedidos rejeitados não iniciam cooldown. Mensagens explicam falta de alvo, vida cheia ou destino inseguro.

`AssetRegistry.SurvivorPowers[powerId]` concentra nome de exibição, cor, estilo, ícone, som e animação opcional. Os ícones começam com `rbxassetid://0`; o HUD mostra um glifo até receber um ID real. Os sons têm um fallback local do Roblox. `AnimationId` está vazio por padrão: os deslocamentos usam a locomoção/pulo existente, com efeitos animados, sem carregar animações privadas ou travar o rig. Para usar clips próprios, forneça IDs autorizados para a experiência.

`SurvivorPowerVFX.lua` contém trilhas, partículas, flashes, brilho na arma, transparência de sombra, cura, escudo, postura e aura. As instâncias visuais não têm colisão, toque ou consulta física. Elas são locais, têm duração limitada, respeitam oclusão e são removidas quando o efeito é consumido, expira, o personagem morre ou a rodada termina. Os efeitos de mundo só são enviados a jogadores próximos (180 studs).

## Integrações e decisões

| Poder | Comportamento |
| --- | --- |
| Rajada Final | Multiplicador de velocidade 2 por 5s no controlador existente; stamina cheia e sem gasto durante o efeito. |
| Salto Longo | LinearVelocity inicial para frente/cima, seguido de queda normal; poeira na saída e aterrissagem. Exige chão firme. |
| Conserto Relâmpago | +25 pontos percentuais na jangada enquanto está dentro de `LocalJangada`, ou na sintonia durante a interação do rádio. |
| Armadilha Improvisada | Gatilho invisível 5×1×5; consulta de proximidade no servidor, sem aceitar `Touched` do cliente. Primeiro Monstro/Espião dispara stun de 3s; expira em 60s. |
| Tiro Certeiro | Próximo ataque validado em até 8s: dano 3× e stun de 2s. Um disparo/swing que erra também consome o efeito. Integra pistola, armadura e armas corpo a corpo; não inventa dano base para armas configuradas com dano zero. |
| Instinto de Caçadora | Direção relativa do monstro vivo mais próximo por 4s; pulsação/indicador na borda da tela. |
| Manto de Sombras | Suspende a detecção e os efeitos de tensão por 8s, preservando o valor acumulado; apresentação semitransparente e partículas de sombra. |
| Passo Fantasma | Até 15 studs; verifica trajetória com volume corporal, chão, inclinação, água e espaço no destino. Obstáculo pode encurtar o alcance; rejeição não gasta cooldown. |
| Adrenalina de Emergência | Cura 50% da vida máxima de si e sobreviventes vivos a até 15 studs, limitada à vida máxima. |
| Escudo Protetor | Protege o sobrevivente aliado mais próximo, a até 10 studs e visível; sem aliado, protege a si. `Imune` por 4s. |
| Investida Brutal | Avanço físico curto; verifica trajetória e inimigos atingidos, com stun de 3s, poeira e tremor leve perto do impacto. |
| Postura Inabalável | 5s de imunidade a atordoamento e multiplicador 0,5 no dano recebido. |
| Golpe de Sorte | Uma tentativa de 50% de anular o próximo ataque em até 10s; a tentativa é consumida também quando o sorteio falha. |
| Intuição Sortuda | Direção do item raro disponível mais próximo por 6s, incluindo a lança ancestral; ignora itens carregados/equipados e removidos do mundo. |

O rádio ainda usa o minigame de sorteio existente. Agora acumula `RadioSintonia` em percentuais: o bônus de reparo melhora a chance existente e atingir 100% conclui a sintonia. Continua exigindo as três peças. Segure F no prompt de sintonia e pressione Q durante os 2 segundos da interação. A jangada continua usando sua zona de entrega por toque, e o bônus participa da montagem visual e conclusão existentes.

`SurvivorPowerStatus` gerencia efeitos temporários, stun e restauração de velocidade/pulo/network ownership. O controlador de movimento e o watchdog respeitam esses estados. As entradas de ataque do Monstro, Espião, armas e teleporte não aceitam uso durante stun. Escudo/sorte também bloqueiam as execuções existentes; redução de dano atua no dano numérico, não transforma execução em ataque comum.

## Autoridade e limpeza

O único argumento de `UseSurvivorPower` aceito do cliente é o slot numérico 1 ou 2. O servidor lê personagem/papel, valida rodada, participação, vida e impedimentos, limita frequência, escolhe alvos e controla cooldown por slot. Morte/respawn cancela efeitos e armadilhas, mas não zera cooldown; início/fim de rodada zera ambos. Trocar personagem/papel cancela os efeitos anteriores. Armadilhas não sobrevivem à morte do dono.

Direção chega somente ao solicitante, como vetor unitário relativo e instante de término: nenhum pacote de sentido contém posição, distância ou instância do alvo. VFX usa um remote separado sem listener de requisições no servidor.

## Verificação

Execute `python3 tests/run_survivor_powers.py /caminho/luau` para verificar os módulos reais com serviços simulados: autoridade, cooldowns, dano, sorte, stun, escudo/cura, reparo dos objetivos, trajetórias bloqueadas, sentidos e limpeza. Os testes não simulam a física/renderização do Roblox.

No Studio, testar em multiplayer: todos os pares Q/E; F junto de Q no rádio; colisões em árvores/portas/tetos; consumo de Tiro Certeiro ao errar/acertar; stun durante investida; morte/respawn/fim de rodada durante buffs; HUD em desktop e celular; transparência e sons para outro jogador. A seleção de assets próprios e o ajuste visual final precisam desse teste na experiência.
