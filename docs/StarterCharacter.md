# Personagem padrão R6

`rigR6.rbxmx` (exportação de `Workspace.R6 novo`) é o rig de referência do
Animation Editor e fica em escala **1.2**, igual ao Monster dentro da partida.
`StarterPlayer.StarterCharacter` é a cópia jogável normalizada para escala 1,
sincronizada pelo Rojo a partir de `src/StarterPlayer/StarterCharacter.rbxmx`.
`LoadCharacterAppearance = false` impede o carregamento da aparência pessoal
dos jogadores.

O `default.project.json` sincroniza `rigR6.rbxmx` como `Workspace/R6 novo`,
para o Animation Editor já enxergar o corpo 1.2x antes do Play. O gerador
também cria `src/Workspace/R6Monster.rbxmx` como `Workspace/R6 Monster`, 4 studs
ao lado do R6 normal e com os pés no mesmo plano. Ambos permanecem visíveis
durante o Play para permitir comparação direta com o Monster jogável. A raiz
fica ancorada e esses rigs são apenas referências de animação.

A exportação foi validada: Humanoid R6, sete peças, RootJoint, Neck, dois
Shoulders e dois Hips com Part0/Part1 corretos. Tamanhos, CFrames, C0/C1,
meshes e attachments são preservados, incluindo os offsets personalizados.

Na cópia jogável, a raiz foi desancorada e foi acrescentado um Animator.
AnimSaves, a Glock-17 de referência e juntas sem conexão foram omitidos.
O arquivo exportado e o rig no Workspace permanecem intactos. Os scripts
existentes de StarterCharacterScripts continuam fornecendo a locomoção.
O R6Ragdoll deixou de reduzir o tamanho da cabeça para 1×1×1.

O spawn inicial e os respawns continuam usando LoadCharacter e os
SpawnLocation existentes, incluindo a seleção de LobbySpawn pelo LobbyManager.
Não há troca de corpo posterior ao spawn nem dependência do atalho M.

Para atualizar o corpo, exporte novamente para `rigR6.rbxmx`, deixe a referência
do Animation Editor em 1.2 e gere a cópia jogável normalizada:

```sh
python3 tools/prepare_starter_character.py --scale-reference 1.2
python3 tools/prepare_starter_character.py
```

Após sincronizar com Rojo, inicie uma nova sessão de Play. Confira caminhada,
corrida, pulo, morte/respawn e equipar/mirar/recarregar a pistola. Em teste com
dois jogadores, ambos devem nascer com esse mesmo corpo e sem acessórios da conta.
