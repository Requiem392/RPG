local ServerScriptService = game:GetService("ServerScriptService")
local Modules = ServerScriptService:WaitForChild("Modules")

-- Ordem de carregamento pode importar
print("🔄 Inicializando Game Services...")

local StatsService = require(Modules:WaitForChild("StatsService"))
local DefenseService = require(Modules:WaitForChild("DefenseService"))
local PostureService = require(Modules:WaitForChild("PostureService"))
local InventoryService = require(Modules:WaitForChild("InventoryService"))

-- Inicializa
StatsService.Init()
DefenseService.Init()
PostureService.Init()
InventoryService.Init()

print("✅ Todos os serviços foram inicializados com sucesso!")
