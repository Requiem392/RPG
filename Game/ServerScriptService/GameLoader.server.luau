local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")
local Modules = ServerScriptService:WaitForChild("Modules")

print("🔄 Inicializando Game Services (Handlers)...")

-- Carrega Modulos (Handlers Classe)
local StatsHandler = require(Modules:WaitForChild("StatsHandler"))
local DefenseHandler = require(Modules:WaitForChild("DefenseHandler"))
local PostureHandler = require(Modules:WaitForChild("PostureHandler"))
local InventoryHandler = require(Modules:WaitForChild("InventoryHandler"))

-- Inicializa Componentes Estáticos (Networking, Loops Globais)
StatsHandler.Init()
DefenseHandler.Init()
PostureHandler.Init()
InventoryHandler.Init()

-- Gerenciamento de Sessão
local PlayerSessions = {}

local function SetupPlayer(player)
	if PlayerSessions[player] then return end

	print("🎮 Criando sessão de sistemas para:", player.Name)
    
    player.CharacterAdded:Connect(function(char)
        -- Se precisarmos de handlers específicos pro Character (ex: hitbox), faríamos aqui.
        -- Por enquanto os Handlers são atrelados ao Player object.
    end)

	local session = {
        -- Cria instâncias vinculadas ao Player
        Stats = StatsHandler.new(player),
        Defense = DefenseHandler.new(player),
        Posture = PostureHandler.new(player),
        Inventory = InventoryHandler.new(player)
	}

	PlayerSessions[player] = session
end

local function CleanupPlayer(player)
	local session = PlayerSessions[player]
	if session then
		print("🗑️ Limpando sessão de:", player.Name)
        
        -- Destroi na ordem inversa de criação recomendada ou indistinto
        if session.Inventory then session.Inventory:Destroy() end
        if session.Posture then session.Posture:Destroy() end
        if session.Defense then session.Defense:Destroy() end
        if session.Stats then session.Stats:Destroy() end
        
		PlayerSessions[player] = nil
	end
end

Players.PlayerAdded:Connect(SetupPlayer)
Players.PlayerRemoving:Connect(CleanupPlayer)

-- Suporte a players que já entraram (Play Solo)
for _, player in ipairs(Players:GetPlayers()) do
	SetupPlayer(player)
end

print("✅ GameLoader inicializado com sucesso!")
