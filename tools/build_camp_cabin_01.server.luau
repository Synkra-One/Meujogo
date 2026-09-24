-- Cole na Command Bar do Studio (modo de edição) e rode.
--
-- A CampCabin_01 virou o estilo "CampCabin" de Tools/Houses e agora é posta
-- nas clareiras (Acampamento, CabanasA, CabanasB, VilaNativa) junto com o
-- estilo "CasaDoCaseiro", com terreno preparado, portas e gavetas
-- funcionando. Detalhes em docs/Casas.md. Isto só chama o gerador:
require(game.ServerScriptService.Server.Tools.HouseGenerator).Generate()
