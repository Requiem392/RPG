local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Remotes
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local PostureUpdate = Instance.new("RemoteEvent")
PostureUpdate.Name = "PostureUpdate"
PostureUpdate.Parent = Remotes

-- ======================================================================
-- CONFIGURAÇÃO
-- ======================================================================

local CONFIG = {
	MaxPosture = 100,
	RegenRate = 10,           -- Postura regenerada por segundo
	PostureBreakStun = 2.5,   -- Duração do stun ao quebrar postura
	MinPostureDamage = 5,     -- Dano mínimo de postura (mesmo com alta defesa)
}

-- ======================================================================
-- ESTADO
-- ======================================================================

local PlayerPostureStates = {} -- { [Player] = { Posture = 100 } }

-- ======================================================================
-- FUNÇÕES
-- ======================================================================

-- Cria estado de postura para novo jogador
local function SetupPlayerPosture(player)
	PlayerPostureStates[player] = {
		Posture = CONFIG.MaxPosture
	}
	
	-- Envia estado inicial para cliente
	PostureUpdate:FireClient(player, "Init", {
		Posture = CONFIG.MaxPosture
	})
	
	print("⚖️ [PostureHandler] Postura criada para:", player.Name)
end

-- Aplica dano de postura
local function DamagePosture(player, damage)
	local state = PlayerPostureStates[player]
	if not state then return end
	
	-- Aplica dano
	state.Posture = math.max(state.Posture - damage, 0)
	
	print("⚖️ [PostureHandler]", player.Name, "perdeu", damage, "de postura →", state.Posture)
	
	-- Atualiza cliente
	PostureUpdate:FireClient(player, "Update", {
		Posture = state.Posture
	})
	
	-- Verifica Posture Break
	if state.Posture <= 0 then
		print("💥 [PostureHandler] POSTURE BREAK!", player.Name)
		
		-- Reseta postura (para não ficar infinito)
		state.Posture = CONFIG.MaxPosture
		
		-- FORÇA PARAR DE BLOQUEAR
		local defenseEvent = Remotes:FindFirstChild("DefenseAction")
		if defenseEvent then
			defenseEvent:FireClient(player, "ForceStopBlock")
		end
		
		-- Aplica stun via DefenseHandler (usando _G)
		local defenseHandler = _G.DefenseHandler
		if defenseHandler then
			defenseHandler.StunPlayer(player, CONFIG.PostureBreakStun)
		end
		
		-- Notifica cliente
		PostureUpdate:FireClient(player, "Break", {
			Posture = CONFIG.MaxPosture
		})
	end
end

-- Obtém postura atual de um jogador
local function GetPosture(player)
	local state = PlayerPostureStates[player]
	return state and state.Posture or CONFIG.MaxPosture
end

-- ======================================================================
-- REGENERAÇÃO
-- ======================================================================

-- Loop de regeneração (roda a cada frame)
RunService.Heartbeat:Connect(function(deltaTime)
	for player, state in pairs(PlayerPostureStates) do
		-- Só regenera se NÃO estiver bloqueando e postura < máximo
		local defenseHandler = _G.DefenseHandler
		local isBlocking = defenseHandler and defenseHandler.IsPlayerBlocking(player) or false
		
		if not isBlocking and state.Posture < CONFIG.MaxPosture then
			state.Posture = math.min(state.Posture + CONFIG.RegenRate * deltaTime, CONFIG.MaxPosture)
			
			-- Atualiza cliente (throttle: só atualiza se mudou significativamente)
			if tick() % 0.1 < deltaTime then -- ~10 FPS de update
				PostureUpdate:FireClient(player, "Update", {
					Posture = state.Posture
				})
			end
		end
	end
end)

-- ======================================================================
-- EVENTOS
-- ======================================================================

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function()
		SetupPlayerPosture(player)
	end)
	
	if player.Character then
		SetupPlayerPosture(player)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	PlayerPostureStates[player] = nil
end)

-- ======================================================================
-- API PÚBLICA
-- ======================================================================

local PostureHandler = {}

function PostureHandler.DamagePosture(player, damage)
	DamagePosture(player, damage)
end

function PostureHandler.GetPosture(player)
	return GetPosture(player)
end

-- Expõe via _G para outros scripts
_G.PostureHandler = PostureHandler

print("⚖️ [PostureHandler] Sistema de postura inicializado")
