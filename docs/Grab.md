# Monster Grab

O sistema usa `E` no teclado e `ButtonX` no controle. O cliente apenas pede a
habilidade; alcance, cone, linha de visao, alvo, cooldown, sincronizacao e morte
sao decididos pelo servidor.

## Animacoes

Cole os IDs em `src/ReplicatedStorage/Modules/GameConfig.lua`, dentro de:

```lua
GameConfig.Monster.Grab.AnimationIds = {
	GrabAttempt = "rbxassetid://SEU_ID",
	Grab = "rbxassetid://SEU_ID",
	VictimGrab = "rbxassetid://SEU_ID", -- opcional
}
```

As tracks usam prioridade `Action4`. `Grab` e `VictimGrab` devem ser exportadas
com a mesma duracao e o mesmo frame zero no Moon Animator.

Markers esperados na animacao `Grab` do monstro:

- `GrabStart`: primeiro frame em que a mao confirma o contato no pescoco.
- `Lift`: frame em que a vitima comeca a sair do chao.
- `Kill`: frame exato do golpe/finalizacao. A morte e aplicada pelo servidor.
- `Release`: frame em que a mao deixa a vitima. O `GrabWeld` e removido aqui.
- `Finished`: ultimo frame util, depois da soltura e antes do fim da track.

Na `GrabAttempt`, coloque somente `Finished` no inicio do recovery. O termino
natural da track tambem libera a habilidade, e existe um timeout de seguranca
para qualquer animacao interrompida.

## Posicao dos rigs

`VictimOffset` e a posicao da `HumanoidRootPart` da vitima relativa a
`HumanoidRootPart` do monstro no frame zero. O valor inicial do projeto foi
medido diretamente da cena montada com `monstro` e `bolha`. Se essa posicao de
autoria mudar, execute na Command Bar:

```lua
local m = workspace.monstro.HumanoidRootPart
local b = workspace.bolha.HumanoidRootPart
print(m.CFrame:ToObjectSpace(b.CFrame))
```

Copie o `CFrame` exibido para `GameConfig.Monster.Grab.VictimOffset`. Esse e o
unico offset de encaixe; nao existem numeros de pose espalhados pelo sistema.

## Teste multiplayer

1. No Studio, abra a aba `Test`, escolha `Server & Clients` e use 2 clientes.
2. Inicie uma partida para que um jogador receba o papel `Monstro` e o outro
   seja `Sobrevivente` ou `Espiao`.
3. Sem alvo na frente, pressione `E`: deve tocar apenas `GrabAttempt`.
4. Com o alvo vivo, na frente e dentro de `GrabRange`, pressione `E`: os dois
   rigs devem alinhar, travar e tocar as tracks juntos.
5. Repita com uma parede no meio, alvo atras do monstro, alvo fora do alcance,
   morte/desconexao no meio e interrupcao da track. Nenhum caso deve deixar
   `GrabWeld`, `GrabLocked`, movimento zero ou raiz ancorada para tras.
