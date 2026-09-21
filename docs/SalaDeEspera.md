# Preparação e seleção de sobrevivente

O jogador entra na fila pelo botão **Jogar** do menu ou pelo prompt **Iniciar partida** do lobby. Não existe uma sala de espera física: enquanto prepara skin e perk, o avatar continua no lobby.

O fluxo autoritativo é:

1. `Lobby`: ninguém está na fila.
2. `Waiting`: participantes escolhem skin/perk e marcam **Pronto**.
3. `Selecting`: os papéis são sorteados e abre a escolha de sobrevivente por 30 segundos. O Monstro recebe Jason automaticamente.
4. `Starting`: escolhas são congeladas e os corpos da partida são criados.
5. `Playing`: os jogadores são enviados à ilha e as fases começam.
6. `Intermission` / `Returning`: resultado, limpeza e retorno ao lobby.

Não há outra contagem entre `Waiting` e `Selecting`. O prazo único usa `Workspace:GetServerTimeNow()` e `SurvivorSelectionConfig.Duration`. Se todos os jogadores humanos confirmarem, `Selecting` termina antes dos 30 segundos. Se o prazo acabar, o servidor confirma a escolha atual e usa o primeiro sobrevivente livre como fallback em caso de conflito.

## Elenco e interface

`Modules/CharacterData.lua` é a fonte da verdade dos sobreviventes. Adicionar uma entrada em `CharacterData.Characters` cria automaticamente um cartão novo.

`Modules/SurvivorSelectionConfig.lua` guarda:

- duração e aviso dos últimos 10 segundos;
- disponibilidade (`Available`, `Locked`, `Unavailable`);
- paleta e rig de pré-visualização;
- modo do retrato (`Viewport` ou `Image`) e `ImageId` futuro.

Os cartões usam `ViewportFrame`. Se existir `ReplicatedStorage.SurvivorPreviewRigs/<CharacterId>`, o modelo é clonado apenas para um `WorldModel`; caso contrário, aparece um R6 neutro. Esses clones são ancorados, não têm scripts nem ligação com o personagem real.

## Segurança e exclusividade

`CharacterStatsApplier` valida no servidor:

- fase e prazo ativos;
- participação na partida;
- papel humano;
- ID existente;
- estado bloqueado/indisponível;
- exclusividade no momento da confirmação.

Escolhas tentativas podem coincidir. O primeiro jogador que confirma reserva o personagem; os demais precisam selecionar outro. `FinishSelection` resolve automaticamente escolhas não confirmadas sem duplicar personagens. A escolha final publica `CharacterId`, atributos, passivas e poderes antes do spawn.

## Testes

```sh
python3 tests/run_waiting_room.py /caminho/para/luau
ruby tests/run_match_tests.rb
rojo build default.project.json --output /tmp/Meujogo-check.rbxlx
```

Os testes standalone cobrem prazo do servidor, seleção padrão, conflitos, bloqueios, confirmação antecipada, fallback, teste solo, entrada tardia e integração com o ciclo da rodada. Renderização, foco de gamepad e enquadramento final dos rigs ainda devem ser conferidos em Play no Studio.
