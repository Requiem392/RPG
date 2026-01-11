local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")
local Modules = ServerScriptService:WaitForChild("Modules")

print("🔄 Inicializando Game Services (Handlers)...")

-- Carrega Modulos (Handlers Classe)
local StatsHandler = require(Modules:WaitForChild("StatsHandler"))
local DefenseHandler = require(Modules:WaitForChild("DefenseHandler"))
local PostureHandler = require(Modules:WaitForChild("PostureHandler"))
local InventoryHandler = require(Modules:WaitForChild("InventoryHandler"))
local SprintHandler = require(Modules:WaitForChild("SprintHandler"))

-- Inicializa Componentes Estáticos (Networking, Loops Globais)
StatsHandler.Init()
DefenseHandler.Init()
PostureHandler.Init()
InventoryHandler.Init()
SprintHandler.Init()

-- Gerenciamento de Sessão
local PlayerSessions = {}

local function SetupPlayer(player)
	if PlayerSessions[player] then return end

	print("🎮 Criando sessão de sistemas para:", player.Name)
    
    player.CharacterAdded:Connect(function(char)
        -- Inicialização de ATRIBUTOS (Estado)
        char:SetAttribute("InCombat", false)
        char:SetAttribute("IsAttacking", false)
        char:SetAttribute("IsBlocking", false)
        char:SetAttribute("IsParrying", false)
        char:SetAttribute("EquippedWeapon", "") -- Nome da arma ou Vazio
        
        print("✅ Atributos de combate inicializados para:", player.Name)
    end)
    
    -- Se o char já existe (ex: reload)
    if player.Character then
        local char = player.Character
        char:SetAttribute("InCombat", false)
        char:SetAttribute("IsAttacking", false)
        char:SetAttribute("IsBlocking", false)
        char:SetAttribute("IsParrying", false)
        char:SetAttribute("EquippedWeapon", "") 
    end

	local session = {
        -- Cria instâncias vinculadas ao Player
        Stats = StatsHandler.new(player),
        Defense = DefenseHandler.new(player),
        Posture = PostureHandler.new(player),
        Inventory = InventoryHandler.new(player),
		Sprint = SprintHandler.new(player)
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
		if session.Sprint then session.Sprint:Destroy() end
        
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
