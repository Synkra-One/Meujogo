"""Run the real main-menu modules against deterministic Roblox doubles.

Usage: python3 tests/run_menu.py /path/to/luau
Rendering, camera, audio and the 3D scene still require a Studio playtest.
"""
import json
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
MODULES = {
    "Stub": "tests/robloxstub.luau",
    "CharacterData": "src/ReplicatedStorage/Modules/CharacterData.lua",
    "MenuConfig": "src/ReplicatedFirst/Menu/MenuConfig.lua",
    "MenuTheme": "src/ReplicatedFirst/Menu/MenuTheme.lua",
    "MenuScreens": "src/ReplicatedFirst/Menu/MenuScreens.lua",
    "MenuSounds": "src/ReplicatedFirst/Menu/MenuSounds.lua",
    "MenuScene": "src/ReplicatedFirst/Menu/MenuScene.lua",
    "MenuBoot": "src/ReplicatedFirst/MenuBoot.client.luau",
}

boot = (ROOT / "src/ReplicatedFirst/MenuBoot.client.luau").read_text()
scene = (ROOT / "src/ReplicatedFirst/Menu/MenuScene.lua").read_text()
screens = (ROOT / "src/ReplicatedFirst/Menu/MenuScreens.lua").read_text()
sounds = (ROOT / "src/ReplicatedFirst/Menu/MenuSounds.lua").read_text()

# 1. ORDEM DE CARGA. ReplicatedFirst roda ANTES de ReplicatedStorage replicar.
#    Um require de módulo do jogo no topo do boot trava o cliente na tela preta.
top_level = boot.split("local sounds = Sounds.new()")[0]
for forbidden in ("require(ReplicatedStorage.Modules", "require(ReplicatedStorage:WaitForChild"):
    assert forbidden not in top_level, f"MenuBoot nao pode fazer {forbidden} no topo"
assert "RemoveDefaultLoadingScreen" in boot, "a tela de carregamento padrao tem de sair"

# 2. NENHUM SISTEMA DUPLICADO. O menu so pode falar com o servidor pelos
#    remotes que a sala de espera JA usava -- nenhum RemoteEvent novo.
remotes_dir = ROOT / "src/ReplicatedStorage/Remotes"
assert not (remotes_dir / "MainMenu.model.json").exists(), "o menu nao cria RemoteEvent proprio"
assert "FireServer" not in boot, "ENTRAR apenas libera o lobby, sem entrar na fila automaticamente"
assert "Instance.new(\"RemoteEvent\")" not in boot
assert "leaveMenu()" in boot.split("local function onPlay()")[1].split("-- Fluxo")[0]
for removed in ("onQuickPlay", "canQuickPlay", "onQuit", ":Kick("):
    assert removed not in boot, f"acao removida ainda presente: {removed}"
assert "OnQuickPlay" not in screens and "OnQuit" not in screens

# 3. O SERVIDOR preserva a acao "Join" para a sala de espera e
#    continua validando tudo dentro de Join().
room = (ROOT / "src/server/WaitingRoomManager.lua").read_text()
assert 'if action == "Join" then' in room, "WaitingRoomManager precisa aceitar Join"
assert "WaitingRoomManager.Join(player)" in room, "Join tem de passar pela validacao existente"
assert 'isDevRoleTester' in room and 'action == "DevRole" and isDevRoleTester(player)' in room, \
    "o papel dev continua validado por UserId no servidor"

# 4. O MENU NAO PODE VOLTAR AO RENASCER, nem deixar o jogador preso.
assert "ResetOnSpawn = false" in screens, "ScreenGui do menu nao pode resetar no spawn"
assert "ReopenOnRespawn" in boot and "setControlsEnabled(true)" in boot, \
    "controles precisam voltar ao fechar o menu"
assert "script.Destroying:Connect" in boot, "sair com o menu aberto nao pode travar os controles"

# 5. A CENA E LOCAL E NAO MEXE NO LIGHTING GLOBAL (que e compartilhado com o
#    gameplay deste mesmo cliente).
assert 'GetService("Lighting")' not in scene, "a cena do menu nao altera o Lighting global"
assert "FireServer" not in scene and "FireAllClients" not in scene, "a cena e 100% local"
assert "part.CanCollide = false" in scene and "part.CanQuery = false" in scene, \
    "nada da cena entra em colisao ou raycast do jogo"
assert "previousType" in scene and "previousFov" in scene, "a camera tem de ser devolvida como estava"
assert "EvaluateStateMachine = false" in scene, "o personagem do menu nao pode ser controlavel"
assert "GetBoundingBox" in scene, "os pes do monstro precisam encostar no chao (qualquer rig, nao so o placeholder)"

# 5.5 CENA EDITAVEL NO EXPLORER (Tools/MenuSceneGenerator.lua). Precisa
#    existir o gerador, e MenuScene precisa procurar a cena dele com
#    fallback gracioso para a versao 100% por codigo (nunca fica sem cena).
generator_path = ROOT / "src/server/Tools/MenuSceneGenerator.lua"
assert generator_path.exists(), "falta o gerador da cena editavel"
generator = generator_path.read_text()
assert 'Workspace:WaitForChild("MenuSceneSet"' in scene, \
    "MenuScene roda em ReplicatedFirst -- tem que ESPERAR a pasta replicar (WaitForChild), " \
    "nao so espiar o que ja chegou (FindFirstChild), senao da falso negativo por corrida"
assert 'Workspace:FindFirstChild("MenuSceneSet")' not in scene, \
    "nao pode sobrar nenhum FindFirstChild direto -- e exatamente o bug de corrida ja confirmado"
assert "watchHandBuiltSet" in scene and "buildSet(self)" in scene, \
    "precisa manter os dois caminhos: cena a mao (ao vivo) E o fallback por codigo"
for anchor_name in ("CameraAnchor", "CameraLookAt", "MonsterMarker"):
    assert f'"{anchor_name}"' in scene and f'"{anchor_name}"' in generator, \
        f"o nome do marcador {anchor_name} tem que bater entre gerador e consumidor"
# O monstro precisa de um boneco de verdade (Model selecionavel/arrastavel),
# nao uma bolinha -- e tudo tem que ficar achatado numa pasta so, sem
# subpastas do tipo "Props"/"Hangar" aninhadas dentro da cena gerada.
assert 'Instance.new("Model")' in generator and 'model.Name = "MonsterMarker"' in generator, \
    "MonsterMarker precisa ser um boneco selecionavel, nao uma bolinha"
assert "folder(root, \"Props\")" not in generator and "folder(root, \"Hangar\")" not in generator, \
    "nada de subpastas dentro da cena gerada -- tem que ficar tudo numa pasta so"

# 5.6 TEMPO REAL. MenuScene nao pode mais clonar-e-esquecer: tem que ESCUTAR
#    a pasta mestre (GetPropertyChangedSignal nas ancoras, ChildAdded/
#    ChildRemoved pra pegar o MonsterMarker sendo criado/apagado com o Play
#    rodando) e nao pode destruir as ancoras (elas precisam continuar vivas
#    no Workspace pra dar pra editar de novo).
watch_body = scene.split("local function bindPositionAnchor")[1].split("function Scene.new")[0]
assert "GetPropertyChangedSignal(\"CFrame\")" in watch_body, \
    "precisa escutar mudanca de posicao das ancoras, nao so ler uma vez"
assert "ChildAdded" in watch_body and "ChildRemoved" in watch_body, \
    "precisa reagir a criar/apagar MonsterMarker com o Play ja rodando"
assert ":Destroy()" not in watch_body, \
    "as ancoras NAO podem mais ser destruidas -- tem que continuar vivas pra dar pra editar de novo"
assert "self.masterSet = master" in watch_body, "guarda a pasta mestre pra registrar ouvintes novos depois"
# Apagar o MonsterMarker tem que literalmente remover o monstro da cena --
# nao so parar de seguir a posicao.
assert "requireMonsterMarker = true" in watch_body, \
    "sem MonsterMarker a cena editavel tem que ficar SEM monstro, nao usar a posicao padrao"
assert "despawnMonster" in scene and "spawnMonster" in scene, \
    "monstro precisa poder ser removido/recriado em tempo real, nao so montado uma vez"
# As conexoes tem que ser desligadas ao fechar o menu, senao vaza memoria.
assert "liveConnections" in scene and ":Disconnect()" in scene.split("function Scene.Destroy")[1], \
    "as conexoes ao vivo precisam ser desconectadas em Scene.Destroy"

assert "MenuSceneSet" in generator and "root:SetAttribute" in generator, \
    "o gerador precisa marcar a pasta gerada"
assert generator.count('"MenuSceneSet"') >= 2, "Generate/Clear tem de usar o mesmo nome"
assert "function MenuSceneGenerator.UpdateLighting" in generator, \
    "precisa de um jeito de atualizar cor/luz sem apagar as posicoes ja editadas"

# 5.7 STREAMING. Workspace.StreamingEnabled=true e a cena fica de proposito
#    LONGE de tudo (Origin) -- sem ModelStreamingMode=Persistent o cliente
#    nunca recebe a pasta durante o Play, e editar as ancoras nao faz efeito
#    nenhum (o bug real que gerou este teste).
assert "Instance.new(\"Model\")" in generator and "Enum.ModelStreamingMode.Persistent" in generator, \
    "a cena gerada precisa ser um Model marcado Persistent, senao o streaming a esconde do cliente"
assert "function MenuSceneGenerator.FixStreaming" in generator, \
    "precisa de um jeito de migrar uma cena antiga (Folder) sem apagar as posicoes"

# 5.8 GENERATE() NAO PODE APAGAR SEM PERGUNTAR. Rodar Generate() de novo por
#    engano e a causa mais provavel de "minhas edicoes sumiram" -- precisa
#    recusar por padrao quando ja existe uma cena, e so apagar com Confirm=true.
generate_body = generator.split("function MenuSceneGenerator.Generate")[1].split("function MenuSceneGenerator.FixStreaming")[0]
assert "opts.Confirm ~= true" in generate_body, "Generate() precisa recusar por padrao se ja existir uma cena"
assert "return nil" in generate_body, "a recusa tem que sair sem chamar Clear()"
assert "CameraAnchor" not in generator.split("function MenuSceneGenerator.UpdateLighting")[1].split("function MenuSceneGenerator.Generate")[0], \
    "UpdateLighting nao pode tocar nas ancoras/posicoes"

# 5.6 O HUD ANTIGO (minimapa + folego + barra de itens) nao pode aparecer
#    por baixo da tela inicial -- ambos precisam checar o mesmo Attribute
#    que o MenuBoot liga/desliga.
stamina_hud = (ROOT / "src/client/StaminaHUD.client.luau").read_text()
hotbar = (ROOT / "src/client/HotbarController.client.luau").read_text()
assert 'player:SetAttribute("IntroMenuOpen", true)' in boot, "MenuBoot precisa avisar o resto do HUD"
assert 'player:SetAttribute("IntroMenuOpen", nil)' in boot, "e desligar o aviso ao fechar"
assert 'GetAttribute("IntroMenuOpen")' in stamina_hud, "StaminaHUD precisa esconder o minimapa/folego"
assert 'GetAttribute("IntroMenuOpen")' in hotbar, "HotbarController precisa esconder a barra de itens"
# O HUD tem que voltar sozinho depois -- nao pode ficar escondido pra sempre.
assert "gui.Enabled = true" in stamina_hud, "StaminaHUD precisa reabilitar o gui fora do menu"

# 6.5 CURSOR/CAMERA. CustomShiftLock reprende o mouse no centro e gira a
#    camera TODO FRAME; sem soltar via o Attribute "CursorLivre" (o mesmo
#    gancho que MonsterTeleportController/CharacterSelectController ja usam),
#    o cursor fica preso e as duas cameras brigam pelo CFrame (tremor).
shift_lock = (ROOT / "src/MovementPack/StarterCharacterScripts/CustomShiftLock.rbxmx").read_text()
assert 'GetAttribute("CursorLivre")' in shift_lock, "premissa mudou: CustomShiftLock nao respeita mais CursorLivre"
assert 'player:SetAttribute("CursorLivre", true)' in boot, "o menu precisa soltar o CustomShiftLock"
assert 'player:SetAttribute("CursorLivre", nil)' in boot, "e devolver o travamento ao fechar"
assert "MouseBehavior" in boot and "MouseIconEnabled" in boot, \
    "rede de seguranca contra re-lock do PlayerModule, como o MonsterTeleportController ja faz"

# 6. TODA transicao passa pelo TweenService, e todo painel tem VOLTAR.
theme = (ROOT / "src/ReplicatedFirst/Menu/MenuTheme.lua").read_text()
assert 'TweenService:Create' in theme, "as animacoes usam TweenService"
assert 'addBackButton' in screens and '"VOLTAR"' in screens, "todo painel precisa de VOLTAR"
assert "if self.busy then return end" in screens, "cliques duplicados tem de ser barrados"

# 7. O Rojo precisa publicar ReplicatedFirst, senao nada disso existe no jogo.
project = json.loads((ROOT / "default.project.json").read_text())
first = project["tree"].get("ReplicatedFirst")
assert first and first.get("$path") == "src/ReplicatedFirst", "ReplicatedFirst nao esta no projeto Rojo"

sources = "local sources = {}\n" + "\n".join(
    f'sources["{name}"] = [====[\n{(ROOT / path).read_text()}\n]====]'
    for name, path in MODULES.items()
)
luau = sys.argv[1] if len(sys.argv) > 1 else "luau"
runner = ROOT / "tests" / ".menu.generated.luau"
runner.write_text(sources + "\n" + (ROOT / "tests/menu.luau").read_text() + "\n" + (ROOT / "tests/menu_scene.luau").read_text())
try:
    subprocess.run([luau, str(runner)], check=True)
finally:
    runner.unlink(missing_ok=True)
