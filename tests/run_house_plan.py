"""HouseGenerator.PlanSite com as clareiras reais do mapa salvo.
Uso: python3 tests/run_house_plan.py [caminho/para/luau]
"""
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
MODULES = {
    "RobloxStub": "tests/robloxstub.luau",
    "HouseGenerator": "src/server/Tools/HouseGenerator.lua",
}
sources = "local sources = {}\n" + "\n".join(
    f'sources["{name}"] = [====[\n{(ROOT / path).read_text()}\n]====]'
    for name, path in MODULES.items()
)
PRELUDE = """
local cfm = getmetatable(CFrame.identity)
function cfm:PointToObjectSpace(p)
	local d = p - self.Position
	return Vector3.new(d:Dot(self.RightVector), d:Dot(self.UpVector), d:Dot(-self.LookVector))
end
"""
with tempfile.TemporaryDirectory(prefix="meujogo-plano-") as directory:
    runner = pathlib.Path(directory) / "house_plan.luau"
    test = (ROOT / "tests/house_plan.luau").read_text()
    # O prelúdio precisa vir depois do stub carregar CFrame.
    test = test.replace('local stub = loadstring(sources.RobloxStub, "RobloxStub")()', 'local stub = loadstring(sources.RobloxStub, "RobloxStub")()\n' + PRELUDE, 1)
    runner.write_text(sources + "\n" + test)
    subprocess.run([sys.argv[1] if len(sys.argv) > 1 else "luau", str(runner)], check=True)
