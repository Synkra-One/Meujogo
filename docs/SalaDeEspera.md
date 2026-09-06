# Sala de espera

Ao dar Play, o jogador nasce no lobby sem a tela de seleção. O pilar **Entrar na sala** leva a uma área separada de preparação. A restrição de teste existente foi mantida: apenas o UserId `11555748600` abre a primeira sala; depois, qualquer jogador pode entrar enquanto houver vaga.

Cada participante escolhe um personagem, uma skin e um perk e marca **Pronto**. O personagem fica reservado no servidor imediatamente; trocar ou sair libera o anterior. Com o mínimo de participantes e todos prontos, começa uma contagem de 10 segundos. Mudar uma escolha cancela o pronto; entrar, sair ou cancelar pronto reavalia a contagem. Só os participantes da sala vão à ilha.

**Ver sala** fecha a interface para andar pela área. O botão **Preparar personagem** ou a tecla **C** reabre a seleção. **Sair da sala** volta ao lobby e libera a vaga. Após a partida e o intervalo, as reservas são limpas antes da próxima sala. Quem entra no servidor durante a rodada aguarda no lobby.

## Configuração

- Capacidade: menor valor entre `GameConfig.Players.Max` e a quantidade de personagens em `CharacterData`. Atualmente são 7 vagas, sem repetição de personagens.
- Mínimo: `GameConfig.Players.Min` (6); o modo `Testing.SoloStart` já existente permite testar sozinho quando `ForceRole` está definido.
- Contagem: `GameConfig.Round.WaitingCountdown` (10 segundos).
- Skins/perks: `Modules/LoadoutData.lua`. As opções iniciais são avatar original, colete marrom e colete azul; perks de regeneração de stamina (+10%), reparo (+10%) e resistência a dano (−5%), além de nenhum perk. Os bônus só são aplicados durante a rodada. As skins humanas não substituem o visual do Monstro.
- A sala física é criada por `WaitingRoomManager` em `(100, 10, -400)`, fora da área da ilha. Não é necessário gerar novamente a ilha.

## Validação

Com o interpretador standalone do Luau disponível:

```sh
python3 tests/run_waiting_room.py /caminho/para/luau
rojo build -o /tmp/Meujogo-check.rbxlx
```

Os testes executam os módulos reais com serviços Roblox simulados: exclusividade, liberações, limite de vagas, validação de escolhas, pronto, cancelamento, contagens antigas, entrada tardia, reset, mínimo, efeitos dos perks e preparação da rodada.

No Studio, sincronize pelo Rojo e reinicie o Play. Para teste local com vários clientes fictícios, ajuste temporariamente a lista de host em `LobbyManager` para os UserIds do teste e restaure depois. Confira dois clientes tentando o mesmo personagem, troca durante a contagem, saída/desconexão, respawn na sala, visual do colete, interface em celular e retorno após a rodada. Os testes standalone não validam renderização, física ou replicação do motor.
