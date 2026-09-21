# Backup do monstro antes da aparência Meshy

Cópia exata (com as alterações locais que já existiam no momento) dos arquivos
que a aparência Meshy toca ou depende. Para desfazer, copie de volta cada
arquivo para o mesmo caminho relativo à raiz do projeto.

- `src/StarterPlayer/StarterCharacter.rbxmx` — rig R6 do monstro em jogo (não é alterado)
- `src/Workspace/R6Monster.rbxmx` — template de animação (não é alterado)
- `src/server/AppearanceManager.lua` — alterado (chama MonsterMeshyVisuals)
- `src/ReplicatedStorage/Modules/AssetRegistry.lua` — alterado (novo campo `Monstro_Modelo.Meshy`)
- `default.project.json` — só cópia de segurança; não foi alterado nesta etapa

Arquivos novos desta etapa (apagar para reverter por completo):
`src/server/MonsterMeshyVisuals.lua`, `src/ServerStorage/MonsterMeshyVisuals.rbxmx`,
`tools/meshy_appearance_once.server.luau`, `tests/meshy_visuals.luau`,
`tests/run_meshy_visuals.py`. Alternativa sem apagar nada: `Meshy.Enabled = false`.
