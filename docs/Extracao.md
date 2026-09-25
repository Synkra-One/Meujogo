# Extração — o helicóptero do resgate

Fim da linha do objetivo do Rádio. **Concluir o rádio não ganha mais a
partida**: ele só CHAMA o resgate. Quem ganha é quem chega na praia.

É uma das duas fugas: a outra é o barco, independente do rádio (ver
[Barco.md](Barco.md)).

| Arquivo | Papel |
|---|---|
| `server/ExtractionSystem.lua` | Zona na praia, fumaça vermelha, contagem, helicóptero, embarque. |
| `server/ExtractionPassenger.lua` | Oculta e restaura corpo, acessórios e colisões. |
| `client/ExtractionCamera.lua` | Câmera externa em terceira pessoa, independente da fuselagem. |
| `client/ExtractionController.client.luau` | Partir, esperar e sair, confirmados pelo servidor. |
| `server/RoundManager.lua` | `onRescueCountdownStarted` chama `Begin`; `onExtracted` encerra a partida. |
| `client/ObjectivesController.client.luau` | Aviso na tela + relógio da contagem. |

## Linha do tempo

```
  rádio concluído
        │
        ▼
  INBOUND (120s)    zona na praia + fumaça vermelha + letreiro
                    entrar NÃO faz nada — o Monstro ainda mata
        │ contagem zera
        ▼
  CHEGANDO (11s)    voa do mar até a praia: desacelera, inclina na curva,
                    levanta o nariz pra frear (flare) e desce reto
        │ patins no chão
        ▼
  POUSADO           vira SÓLIDO (não dá pra atravessar)
                    prompt "Embarcar" liberado
        │ você embarca
        ▼
  A BORDO           corpo oculto + câmera externa do helicóptero
                    [ PARTIR AGORA ]  [ ESPERAR ]  [ SAIR ]
        │ alguém escolhe partir
        ▼
  PARTINDO (9s)     sobe reto, vira e acelera pro mar
        │
        ▼
  vence quem estava a bordo
```

**Chegar antes do pouso não vale nada** — era exatamente o pedido. Quem chega
cedo fica parado numa praia aberta, iluminada por fumaça vermelha que o
Monstro enxerga de longe, sem nada pra fazer além de esperar.

**Não existe decolagem automática**: quem decide a hora de ir é quem está a
bordo. Se ninguém chegar, o helicóptero espera — não há segunda chance de
chamar o resgate, então tirá-lo do mapa seria só frustrante.

## O helicóptero

Modelo do Toolbox (`GameConfig.Extraction.ModeloId` = `8915950341`),
normalizado pra `ComprimentoModelo` studs. Se o asset não carregar, entra uma
versão em Parts com os **mesmos nomes** (`PrimaryPart` + um Model `Rotor`),
então nada no resto do sistema precisa saber qual dos dois está no mapa.

- **Rotor girando**: achado por nome (`rotor`, `hélice`, `blade`,
  `propeller`...) e girado **todo frame** (`RotorRPS` = 4,5 voltas/s).
- **Voo suave**: a trajetória é atualizada a cada frame, separada do resto do
  sistema, que roda throttled a 4 Hz. Animar o voo no tique throttled era o
  que deixava tudo travado.
- **Sólido**: colisão liga **no pouso** (no ar ele prensaria quem estivesse na
  pista) e desliga na decolagem. As pás nunca colidem — rotor empurrando
  jogador é bug, não realismo.
- **Atitude**: nariz baixo acelerando, inclinação na curva de aproximação,
  nariz alto no flare pra frear, nivelado no toque. Na saída, o inverso.

> **Se o helicóptero voar de lado ou de ré**, o modelo define "frente" num
> eixo diferente do que o `CFrame.lookAt` assume. Ajuste
> `GameConfig.Extraction.GuinadaModelo` (0 / 90 / 180 / 270). É o único lugar
> que precisa mudar.

## Embarcar, esperar e sair

- **Embarcar**: prompt `Embarcar` no helicóptero (só depois do pouso). O
  corpo e acessórios ficam invisíveis e sem colisão. O root acompanha o
  helicóptero e a câmera observa o veículo em terceira pessoa, por fora.
- **Três opções** aparecem na tela ao embarcar
  (`client/ExtractionController.client.luau`):

  | Botão | O que faz |
  |---|---|
  | **PARTIR AGORA** | decola imediatamente com quem estiver a bordo |
  | **ESPERAR** | mantém o painel e a possibilidade de sair/partir |
  | **SAIR DO HELICÓPTERO** | restaura corpo, controles e câmera no solo |

- **Sair**: botão no painel ou prompt `Sair`. Só enquanto pousado e para
  quem está registrado a bordo; volta à posição de solo onde embarcou.
- Durante a viagem, ações de gameplay e dano ficam bloqueados. Morte,
  desconexão, troca de personagem e fim da rodada liberam a vaga e restauram
  o corpo. A restauração nunca solta alguém da altitude do helicóptero.
- São 6 assentos; lotado, o prompt de embarcar some.

O servidor valida tudo: quem manda `"Partir"` sem estar a bordo é ignorado em
silêncio.

## Onde a zona nasce

Na praia do lado **oposto ao site "Radio"** do `IslandLayout` — a corrida
final atravessa a ilha inteira. É calculado em runtime (varre ângulos em leque
a partir do oposto, procurando areia firme acima da linha d'água), então
**não precisa regerar o mapa** pra existir.

Se o ponto cair em uma área inadequada, ele gira e procura outro local seguro.

A pista tem raio 18 e nasce a ~18 studs da beira d'água (a praia tem 45 de
largura), então o helipad inteiro fica na areia.

## Como o jogador acha o lugar

Três camadas, de propósito — a pergunta "pra onde eu corro?" precisa ter
resposta mesmo no escuro, dentro da floresta, do outro lado da ilha:

1. **Letreiro `BillboardGui`** com `AlwaysOnTop = true` e `MaxDistance = 3000`:
   atravessa terreno, árvore e relevo. Mostra a contagem (`HELICÓPTERO EM
   1:23` → `EMBARQUE ABERTO` → `DECOLA EM 0:12`).
2. **Feixe vermelho** de ~180 studs subindo da pista, visível acima da copa
   das árvores (que têm 30-56).
3. **Fumaça vermelha** em quatro sinalizadores na borda + balizas acesas.

E na HUD: aviso grande **"RESGATE A CAMINHO — corra até a fumaça vermelha na
praia!"** no primeiro segundo da contagem, mais o relógio no texto da torre.

## Quem pode embarcar

Sobreviventes e Espião vivos, participantes da rodada ativa (`InRound`),
fora da sala de espera. Embarcar exige proximidade 3D e ausência de stun ou
agarrão. Jogadores do lobby, atrasados e Monstro são recusados pelo servidor.

Só passageiros válidos no fim da decolagem são reportados ao `RoundManager`.
Se todos desconectarem durante o voo, o helicóptero retorna para novo embarque.
O reset libera todos os passageiros, inclusive quando a partida acaba por tempo.

O modelo usa streaming `Atomic` e a câmera tolera o remote chegar antes do
modelo, conforme o [contrato de streaming do Roblox](https://create.roblox.com/docs/workspace/streaming).

No Studio, testar embarque/saída repetidos, esperar e sair, decolar, morte,
desconexão, fim por tempo e segunda rodada. Conferir câmera com mouse, toque e
controle e em tela estreita. Os testes locais verificam estado e enquadramento
matemático; não substituem a inspeção da câmera renderizada.

## Ajustes

`GameConfig.Extraction`: raio da zona, id/escala/guinada do modelo, durações
de chegada e partida, distância e altura de entrada, altura do flare, folga do
pouso, inclinações do voo, rotação do rotor e o intervalo de checagem.

`GameConfig.RadioObjective.RescueCountdownDuration` (**120s**) é o tempo da
contagem — era 15s quando concluir o rádio ganhava sozinho, e virou o tempo de
atravessar a ilha.

## Trocar o helicóptero por outro modelo

Troque `GameConfig.Extraction.ModeloId`. O sistema só espera duas coisas do
Model: um `PrimaryPart` (se não tiver, ele elege a maior Part) e algo com nome
de rotor pra girar. Se o novo modelo apontar pra outro lado, ajuste
`GuinadaModelo`; se ficar grande ou pequeno demais, `ComprimentoModelo`.

## Falta

Nada de assets — modelo (`8915950341`) e som (`99103708154004`) já estão
ligados. O som é um loop só, usado da chegada até a partida.

## Checklist de teste

1. Complete a corrente do rádio até "Enviar socorro" (ver [Radio.md](Radio.md)).
2. Assim que o socorro sai: aviso grande na tela, relógio `Helicóptero em
   2:00` na HUD, e o letreiro + fumaça vermelha na praia (visíveis de longe).
3. Vá até a zona **antes** da contagem zerar e fique lá: nada deve acontecer.
4. Contagem zera → o helicóptero **voa** do mar até a praia (11s), inclinando
   na curva e levantando o nariz pra frear. Tem que parecer fluido, não
   travado.
5. Pousado: tente **atravessar** o helicóptero — não deve dar.
6. Prompt `Embarcar` → o painel com **duas opções** aparece na tela.
7. Clique **ESPERAR**: o painel some e você continua a bordo. Use o prompt
   `Sair` pra desembarcar (e confira que você volta pro lado de fora, sem
   ficar preso na geometria).
8. Embarque de novo e clique **PARTIR AGORA**: ele sobe, vira e acelera pro
   mar; no fim a partida termina com "Resgate de helicóptero: <nome>".
9. Rode outra rodada: zona e helicóptero da anterior devem ter sumido
   (`ExtractionSystem.Reset()` roda no preparo da partida).
10. Se o helicóptero voar de lado/de ré, ajuste `GuinadaModelo` (0/90/180/270).
