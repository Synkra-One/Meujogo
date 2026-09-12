# Backup seguro do Moon Animator 2

O plugin `tools/MoonRigBackup.plugin.lua` protege os dados reais que o Moon
Animator 2 grava em `ServerStorage > MoonAnimator2Saves`.

O projeto Rojo também declara as pastas `MoonAnimator2Saves` e
`AnimationBackup` com `ignoreUnknownInstances`. Isso é essencial: sem essa
opção, conectar o Rojo pode apagar os arquivos do Moon e os snapshots que só
existem no arquivo aberto do Studio. A proteção é aplicada somente nessas duas
pastas, sem esconder alterações desconhecidas no restante de `ServerStorage`.

## O que mudou

- A proteção automática vem ligada e verifica alterações a cada 45 segundos.
- São mantidas até 30 versões saudáveis completas.
- Se um projeto que tinha dois ou mais rigs/trilhas perder uma delas, a nova
  cópia é marcada como suspeita e não substitui o histórico saudável.
- `ProtectMoon` força um backup imediato.
- `RecoverMoon` copia o último backup saudável de volta com o prefixo
  `RECUPERADO_`. Nada atual é apagado ou sobrescrito.
- Backups de rigs agora são versionados; criar um novo não apaga o anterior.
- Antes de `ResetRigs`, o plugin tenta proteger os arquivos do Moon.

## Rotina recomendada

1. Depois de criar ou abrir a animação, salve dentro do Moon Animator.
2. Clique em `ProtectMoon` ao terminar uma parte importante.
3. Feche a animação no Moon antes de fechar o Studio ou usar `ResetRigs`.
4. Salve também o place (`Cmd+S`). Os snapshots ficam dentro do place em
   `ServerStorage > AnimationBackup > MoonHealthySnapshots`.

Se uma animação sumir ou separar os rigs, clique em `RecoverMoon`, abra no Moon
o arquivo com prefixo `RECUPERADO_` e só apague o arquivo quebrado depois de
confirmar que todas as trilhas e frames voltaram.
