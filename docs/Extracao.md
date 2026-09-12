# Extração — o helicóptero do resgate

Fim da linha do objetivo do Rádio. **Concluir o rádio não ganha mais a
partida**: ele só CHAMA o resgate. Quem ganha é quem chega na praia.

| Arquivo | Papel |
|---|---|
| `server/ExtractionSystem.lua` | Zona na praia, fumaça vermelha, contagem, helicóptero, embarque. |
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
  A BORDO           senta num assento + DUAS opções na tela:
                    [ PARTIR AGORA ]  [ ESPERAR ]
                    sair exige o prompt "Sair"
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
  personagem senta num assento — a pose acompanha o helicóptero pela mesma
  técnica da Jangada (root ancorado + CFrame relativo por frame).
- **As duas opções** aparecem na tela ao embarcar
  (`client/ExtractionController.client.luau`):

  | Botão | O que faz |
  |---|---|
  | **PARTIR AGORA** | decola imediatamente com quem estiver a bordo |
  | **ESPERAR** | fecha o painel e segura o voo pelos colegas |

- **Sair**: prompt `Sair` no helicóptero — ninguém é ejetado sozinho, e quem
  desembarca é reposicionado **do lado de fora** (soltar alguém dentro da
  fuselagem sólida deixaria o personagem preso na geometria).
- Morrer ou ser amarrado no assento **perde a vaga** (checado a cada tique).
- São 6 assentos; lotado, o prompt de embarcar some.

O servidor valida tudo: quem manda `"Partir"` sem estar a bordo é ignorado em
silêncio.

## Onde a zona nasce

Na praia do lado **oposto ao site "Radio"** do `IslandLayout` — a corrida
final atravessa a ilha inteira. É calculado em runtime (varre ângulos em leque
a partir do oposto, procurando areia firme acima da linha d'água), então
**não precisa regerar o mapa** pra existir.

Se o ponto cair em cima do `LocalJangada`, ele gira e procura outro: jangada e
helicóptero são duas fugas diferentes e não deveriam dividir a mesma praia.

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

Qualquer um que **não seja o Monstro**, vivo e não amarrado — igual à Jangada,
um Espião infiltrado também consegue subir. Quem decide o vencedor é o
`RoundManager`.

Vale quem está **sentado** na decolagem: ser arrastado pra fora pelo Monstro,
morrer no assento ou desembarcar antes custa a vaga.

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
