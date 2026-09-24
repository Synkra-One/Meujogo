# Câmera sobre o ombro

A câmera usa o PlayerModule para mouse, controle e toque. O enquadramento é composto por `ShoulderCameraController`, após a câmera padrão; a última verificação de colisão roda depois de recoil e impactos. `CustomShiftLock` mantém cursor/rotação, sem adicionar outro deslocamento. O balanço antigo fica suspenso enquanto a câmera adaptativa está ativa.

O estilo é inspirado em The Last of Us: posição baixa e próxima, personagem deslocado para um lado, olhar livre ao explorar, corpo acompanhando a direção com ferramenta equipada, aproximação ao mirar e movimento de câmera discreto. Não é uma reprodução exata da câmera proprietária.

| Situação | Distância alvo | FOV |
| --- | --- | --- |
| Exploração | 5,2 studs | 68° |
| Interior estreito | até 3,65 studs | até 66° |
| Mira | 3,1 studs | até 60° |
| Agachado | 4,4 studs | 66° |
| Corrida ao ar livre | 5,65 studs | 75° |

`V`, clique no analógico direito ou botão **Ombro** no celular alternam o lado. Perto de obstáculos, o deslocamento lateral se reduz junto com a distância. A câmera não troca de lado automaticamente, evitando saltos de composição nas portas.

Paredes, teto e móveis são detectados sem marcar zonas manualmente. A detecção de interior tem retenção breve para evitar oscilação em portas. A colisão usa esfera envolvendo a lente e os cantos do plano próximo, raio complementar e consulta de sobreposição. Esta última cobre a limitação de não detectar interseções iniciais do [Spherecast, documentada pelo Roblox](https://create.roblox.com/docs/reference/engine/classes/WorldRoot#Spherecast). Aproxima imediatamente para respeitar a geometria e afasta suavemente quando o caminho fica livre. Meshes usam a geometria de colisão disponível no Roblox; a consulta de sobreposição é conservadora com suas caixas orientadas. Peças não colidíveis e personagens são ignorados.

Os parâmetros estão em `src/ReplicatedStorage/Modules/ShoulderCameraConfig.lua`. O script de movimento publica `MovementCameraFOV`; a câmera compõe interiores/mira/Shadow Rush. O teleporte mantém seu efeito temporário de FOV. O desvanecimento do corpo muito próximo preserva o Manto de Sombras. Câmeras Scriptable, espectador, VR e preparação da partida não são assumidos por este controlador.

## Validação

`python3 tests/run_shoulder_camera.py /Users/math/.rokit/bin/luau` executa os módulos reais com serviços/geometria simulados, incluindo colisão, retorno em diferentes FPS, ciclo de vida e integração do controlador. Também verifica a sintaxe dos scripts embutidos alterados. Não substitui renderização/física do Studio.

No Studio, conferir os seguintes cenários:

1. Nascer no Lobby e movimentar câmera livremente; iniciar seleção/carregamento e depois entrar na partida.
2. Entrar/sair de uma casa, atravessar portas e andar de costas até paredes; girar 360° perto de quinas, armários e teto baixo.
3. Mirar, trocar ombro, correr, agachar e rastejar; verificar crosshair e trajetória da arma com uma parede ao lado.
4. Fechar uma porta próxima da câmera, receber impacto e usar poderes junto de paredes.
5. Repetir em celular, controle, tela larga e 30/60/144 FPS; respawn, teleporte e abertura/fechamento do menu.

O volume precisa de espaço físico para caber. Se o personagem for colocado dentro de geometria sólida por outro sistema, nenhuma posição local garante uma imagem útil até ele sair dela.
