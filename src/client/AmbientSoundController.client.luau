--!strict
-- Entrada de áudio ambiente existente, agora apresenta o Fear replicado.
-- O heartbeat por tempo fora de ZonaSegura foi substituído para evitar duplicação.
local Presentation = require(script.Parent.FearPresentation)
Presentation.Init()
script.Destroying:Connect(function() Presentation.Destroy() end)
