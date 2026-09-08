# Personagem padrão R6

`StarterPlayer.StarterCharacter` é a cópia jogável de `rigR6.rbxmx`
(exportação de `Workspace.R6 novo`). O Rojo sincroniza essa cópia a partir de
`src/StarterPlayer/StarterCharacter.rbxmx`. `LoadCharacterAppearance = false`
impede o carregamento da aparência pessoal dos jogadores.

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

Para atualizar o corpo, exporte novamente para rigR6.rbxmx e execute:

```sh
python3 tools/prepare_starter_character.py
```

Após sincronizar com Rojo, inicie uma nova sessão de Play. Confira caminhada,
corrida, pulo, morte/respawn e equipar/mirar/recarregar a pistola. Em teste com
dois jogadores, ambos devem nascer com esse mesmo corpo e sem acessórios da conta.
