# Digital's OTS Patch2 — integração da Glock17

Origem preservada: `Sistema de armas/Digital's OTS Patch2.rbxm`.
Backup das nove Tools preservado: `WeaponAssets_backup/Tools-todas-as-armas.rbxmx`.

O projeto ativo usa somente a Glock17. A Tool, meshes, welds, sons, partículas,
tracers, impactos, HUD e animações vieram do pacote. O Framework foi adaptado
porque a versão original tentava substituir o PlayerModule, Animate, sprint,
passos, câmera e movimentação, além de aceitar alvo/dano enviados pelo cliente.
O resultado mantém a apresentação do OTS e usa o servidor do jogo para validar
posse, vida, mira, cadência, munição, parede, raycast, dano e recarga.

## IDs de animação da Glock17

Todos ficam em `src/ReplicatedStorage/WeaponAssets/Animations.rbxmx`, dentro de
`Animations/PistolAnimations`. Troque o valor entre `<uri>` e `</uri>`.

| Estado | ID atual | Marker esperado |
| --- | --- | --- |
| Fire | `rbxassetid://17861277580` | nenhum obrigatório |
| Holster/equipada | `rbxassetid://17837420732` | nenhum obrigatório |
| Reload | `rbxassetid://17837428175` | `Start`, `MagOut`, `MagIn`, `BoltPull`, `BoltRelease`, `End` |
| Aim | `rbxassetid://97722809924272` | nenhum obrigatório |

As animações novas devem ser R6, publicadas pela conta/grupo autorizado para a
experiência. Se a nova recarga não tiver markers, o servidor usa tempos de
fallback e a arma continua funcional, mas som e movimento do pente podem ficar
menos sincronizados com o clipe.

## Arquivos antigos removidos

- `src/server/FirearmServer.lua`
- `src/client/PistolController.client.luau`
- `src/client/PistolHUD.lua`
- `src/client/PistolPose.lua`
- `src/client/PistolGripTest.client.luau`
- `src/server/PistolGripCalibration.server.luau`
- `src/ReplicatedStorage/Modules/FirearmRules.lua`
- `src/ReplicatedStorage/Modules/Ammo.lua`
- `src/ReplicatedStorage/Modules/WeaponEffects.lua`
- `src/ReplicatedStorage/Modules/PistolGrip.lua`
- `src/ReplicatedStorage/Remotes/FirearmHit.model.json`
- `src/ReplicatedStorage/Remotes/PistolGripTest.model.json`
- documentação/teste do calibrador e da pose antigos

## Componentes ativos do OTS

- `src/client/OTSController.client.luau`: equipar, mirar, atirar, recarregar,
  animações, recoil e input de mouse/controle/touch.
- `src/client/OTSHUD.lua`: controla o ScreenGui original e integra o contador de
  pente/reserva na mesma interface.
- `src/server/OTSFirearmService.lua`: autoridade de tiro, dano, recarga e
  replicação dos efeitos.
- `src/ReplicatedStorage/Modules/OTSAmmo.lua`, `OTSRules.lua`, `OTSEffects.lua`.
- `src/StarterGui/Weapon.rbxmx`: HUD original do pacote, sem uma segunda vinheta.
- `src/ReplicatedStorage/WeaponAssets`: Glock17 e apenas os assets necessários
  de pistola/HUD/impacto.

Os quatro RemoteEvents reaproveitados ficam em `ReplicatedStorage/Remotes`:
`FirearmShoot`, `FirearmReload`, `FirearmDamage` e `FirearmFeed`. Os vinte
remotes inseguros do pacote original não foram copiados.

## Duplicações eliminadas e sistemas preservados

Não existe um segundo Animate, PlayerModule, sistema de sprint, stamina,
crouch, footsteps, câmera, hotbar, dano ou inventário. A mira publica o atributo
`Character.FirearmAiming`; o `Crouching` atual continua dono do FOV e agora
compõe o `AimFOV` da Tool e a mira com a mesma vinheta já usada por
crouch/crawl. O
`CustomShiftLock` continua dono da câmera de ombro e de sua colisão.

Continuam ativos por serem integração do jogo, e não uma segunda implementação
da Glock: `AmmoSystem`, `WeaponSpawner`, `LobbyFiringRange`, `DropItemSystem`,
`DamageSystem`, `HotbarController` e `ItemDiscovery`.

## Dependências e verificações

Dependências diretas: `WeaponAssets/{Tools,Animations,Audios,Effects}`,
`OTSAmmo`, `OTSRules`, `OTSEffects`, `Remotes`, `AmmoSystem`, `DamageSystem` e
`SurvivorPowerStatus`. A Tool ativa contém somente `Glock17` e não tem scripts
embutidos.

Verificado automaticamente:

- build completo do Rojo;
- compilação das fontes OTS dentro do arquivo construído;
- somente uma Glock, um HUD e um controlador ativos;
- raycast e dano no servidor, cadência, paredes, posse, lobby e estados
  bloqueados;
- recarga, reserva parcial, cancelamento, morte, troca de Character e pickups;
- pacote original e backup permaneceram com os mesmos hashes.

Ainda depende de Play no Roblox Studio: autorização dos assets, aparência da
Glock na mão R6, markers reais das animações publicadas, câmera em paredes,
touch/gamepad e teste com dois jogadores. Falha de autorização aparece no
Output como `Failed to load animation` ou `not authorized to access Asset`.
Na validação headless, os sons OTS de kill/armour break `17146316146` e
`17146437786` retornaram sem autorização; tiro, recarga e hitmarker precisam ser
confirmados no Play, e esses dois IDs devem ser trocados se o erro também surgir
na experiência publicada.

## Roteiro de teste no Studio

1. Sincronize o Rojo, pare qualquer Play antigo e inicie uma sessão nova.
2. Equipe a Glock17. A postura Holster deve substituir apenas os braços/torso;
   pernas e locomoção continuam usando as animações normais do jogo.
3. Segure botão direito/L2 (ou MIRAR no touch), confirme FOV/crosshair, e atire.
4. Pressione `R`/`X`, confirme pente, sons, markers e reserva.
5. Tente atirar sem mirar, sem munição, durante recarga e através de parede.
6. Largue com `G`, pegue novamente e confirme que o pente foi preservado.
7. Teste morte, respawn, crouch, sprint, stamina e troca de personagem com a
   arma equipada e guardada.
