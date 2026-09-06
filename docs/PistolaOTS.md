# Pistola OTS — integração R6

Origem: `Sistema de armas/Digital's OTS Patch2.rbxm`. A Glock17 de 65 instâncias
já extraída em `WeaponAssets/Tools.rbxmx` é a pistola desse pacote. O projeto
carrega apenas essa Tool; fuzis e shotgun não são entregues nem aceitos pelo
controlador. Meshes, grip, welds, sons, efeitos e as quatro animações da pistola
foram reaproveitados. O Framework, PlayerModule e Animate originais não são importados.

## Testar no lobby

Sincronize pelo Rojo e reinicie o Play. Não importe o pacote inteiro novamente.
À direita do spawn há a bancada `Workspace.TestePistolaLobby`, criada em runtime:

1. `E` perto da pistola para pegar; equipe pela hotbar (normalmente `1`).
2. Pegue a caixa de **34 cartuchos**, ao lado. O pente começa com **17**.
3. Botão esquerdo atira; botão direito segurado mira; `R` recarrega; `G` larga.
4. Atire no alvo diante da bancada: a vida aparece sobre ele e o alvo renasce em 3 s.
5. No controle: gatilho direito atira pelo sistema de Tools, esquerdo mira, `X` recarrega.
   No toque: botões ATIRAR, MIRAR (alternar) e RECARREGAR.

Apenas **uma pistola de treino** existe por servidor. Pegar não cria uma cópia
extra; após destruição/morte ela volta em 3 s. Uma arma largada conserva munição.
A caixa volta 5 s após esgotar; pegar com a reserva quase cheia conserva a sobra.
A pistola de teste só dá dano em alvos marcados `FirearmTestTarget`; jogadores
no lobby/sala de espera também ficam protegidos das outras pistolas.

`GameConfig.Testing.LobbyPistol = false` desativa a bancada no próximo servidor.
O atalho `M` continua trocando para `R6 novo`; desequipa antes para conservar
a Tool na mochila e garante Animator criado no servidor. A reserva segue a regra
geral do jogo e reinicia ao trocar Character: pegue munição novamente.

## Comportamento e parâmetros

`Modules/FirearmRules.lua`: semiautomática, intervalo mínimo **0,18 s**, alcance
**600 studs**, recarga **2,2 s**, dispersão de quadril **1,05°** e mira **0,25°**.
O dano original da Tool foi mantido: cabeça 17, tronco 13, membros 7, antes dos
modificadores de personagem/armadura do jogo. Reserva máxima: 68.

O servidor verifica posse, vida, restrição, fase, cadência, pente e recarga.
Um disparo desconta uma bala e faz raycast do cano, incluindo obstrução entre
cabeça e cano; não atravessa paredes para atingir o ponto visto pela câmera.
Valores não finitos e mensagens antigas de dano/recarga são rejeitados.
O cliente só antecipa pose, recuo e contador; hitmarkers dependem do servidor.
Não há compensação de lag/rebobinamento de alvos: teste acertos móveis com latência.

Recarga tem início/fim e sons agendados no servidor. Markers do cliente não
concedem munição. Largar, desequipar, morrer ou trocar Character cancela,
restaura o pente visível e invalida callbacks antigos.

## Compatibilidade e limitações verificáveis

O jogo continua usando o PlayerModule/CustomShiftLock, caminhada, corrida,
idle e healing atuais. A mira sinaliza `Character.FirearmAiming`; o próprio
`Crouching` resolve FOV/sprint. O recuo é uma rotação aditiva, sem substituir
posição, colisão, zoom ou CameraType da câmera.

As animações OTS são R6 e pertencem a terceiros:

| Pose | ID |
|---|---|
| Holster | 17837420732 |
| Aim | 17834125927 |
| Fire | 17861277580 |
| Reload | 17837428175 |

A autorização destes assets na experiência não pode ser confirmada pelo build.
Se o Output mostrar falha de carregamento, autorize os assets para a experiência
ou substitua por animações publicadas na sua conta/grupo. A pistola ainda atira
e recarrega sem elas, mas a pose/recarga visual ficará incompleta. Sons/meshes
também precisam estar disponíveis. [Permissões de assets no Roblox](https://create.roblox.com/docs/projects/assets).

## Verificação

`python3 tests/run_firearms.py /caminho/luau` exercita o servidor e pickups com
serviços simulados. `rojo build` valida a montagem do projeto; `luau-compile`
valida a sintaxe. Isso não substitui Play no Studio nem teste com dois jogadores.
Confira no Play as quatro poses, mão/grip no R6 novo, FOV ao mirar/agachar/correr,
colisão com paredes, recarga cancelada, queda/repickup, respawn, mouse e toque.
