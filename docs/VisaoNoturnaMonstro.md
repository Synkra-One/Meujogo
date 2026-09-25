# Visão noturna do Monstro

O Monstro não usa lanterna. Enquanto está vivo em uma rodada, apenas o seu
cliente aplica uma correção de cor azul-fria que levanta as sombras e reduz o
contraste. Assim ele lê chão, árvores e silhuetas à noite com clareza maior que
um Sobrevivente, sem iluminar o mapa nem alterar a tela de outros jogadores.

O efeito é criado por `client/MonsterVisionController.client.luau` e só fica
ativo quando `Role = Monstro`, `InRound = true`, o jogador não está eliminado
e o Humanoid está vivo. Ele se desativa ao morrer, trocar de papel, sair da
rodada ou reaparecer. Durante o Shadow Rush, mantém a mesma leitura de sombras
com um lift igualmente discreto.

Na caverna, `client/CaveDarknessController.client.luau` acrescenta uma luz
local presa à câmera do Monstro para ele não depender de nenhuma lanterna. Essa
luz não existe para os outros clientes e não cria colisão, interação ou marca
visível no mundo compartilhado.

Os ajustes ficam em `GameConfig.Monster.Vision`:

- `Brightness`: ajuste mínimo (`0.03`) para evitar uma tela lavada.
- `Contrast`: negativo (`-0.08`), que levanta sombras suavemente e reduz o
  brilho relativo das áreas já iluminadas.
- `Saturation` e `TintColor`: definem o tom frio da visão noturna.
- `BloomIntensity = 0`: lâmpadas e reflexos continuam nítidos, sem halo.
- `CornerOpacity = 0.045`: moldura roxa bem sutil no ponto de vista do Monstro.

Como testar no Studio: inicie uma partida à noite como Monstro e como
Sobrevivente em dois clientes. Em um mesmo ponto escuro, o Monstro deve ler
melhor terreno e obstáculos; o Sobrevivente deve manter a iluminação normal.
Verifique também morte, troca de papel e entrada/saída da caverna para confirmar
que a correção some sem deixar efeitos locais presos.
