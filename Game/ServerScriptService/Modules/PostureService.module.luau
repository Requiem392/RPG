local PostureService = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

-- Dependências
local DefenseService -- Será carregado no Init para evitar dependência circular se houver (mas aqui é hierárquica)
-- (Na prática, DefenseService não depende de Posture, então podemos exigir direto se quisermos, mas faremos no Init por segurança de ordem de load)

-- Remotes
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local PostureUpdate = Remotes:FindFirstChild("PostureUpdate")
if not PostureUpdate then
	PostureUpdate = Instance.new("RemoteEvent")
	PostureUpdate.Name = "PostureUpdate"
	PostureUpdate.Parent = Remotes
end

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
	if PlayerPostureStates[player] then return end

	PlayerPostureStates[player] = {
		Posture = CONFIG.MaxPosture
	}
	
	-- Envia estado inicial para cliente
	PostureUpdate:FireClient(player, "Init", {
		Posture = CONFIG.MaxPosture
	})
	
	print("⚖️ [PostureService] Postura criada para:", player.Name)
end

-- ======================================================================
-- MÉTODOS
-- ======================================================================

function PostureService.DamagePosture(player, damage)
	local state = PlayerPostureStates[player]
	if not state then return end
	
	-- Aplica dano
	state.Posture = math.max(state.Posture - damage, 0)
	
	print("⚖️ [PostureService]", player.Name, "perdeu", damage, "de postura →", state.Posture)
	
	-- Atualiza cliente
	PostureUpdate:FireClient(player, "Update", {
		Posture = state.Posture
	})
	
	-- Verifica Posture Break
	if state.Posture <= 0 then
		print("💥 [PostureService] POSTURE BREAK!", player.Name)
		
		-- Reseta postura (para não ficar infinito)
		state.Posture = CONFIG.MaxPosture
		
		-- FORÇA PARAR DE BLOQUEAR
		local defenseEvent = Remotes:FindFirstChild("DefenseAction")
		if defenseEvent then
			defenseEvent:FireClient(player, "ForceStopBlock")
		end
		
		-- Aplica stun via DefenseService
		if DefenseService then
			DefenseService.StunPlayer(player, CONFIG.PostureBreakStun)
		end
		
		-- Notifica cliente
		PostureUpdate:FireClient(player, "Break", {
			Posture = CONFIG.MaxPosture
		})
	end
end

function PostureService.GetPosture(player)
	local state = PlayerPostureStates[player]
	return state and state.Posture or CONFIG.MaxPosture
end

-- ======================================================================
-- INITIALIZATION
-- ======================================================================

function PostureService.Init(params)
    -- Injeção de dependência opcional ou require direto
    local Modules = ServerScriptService:WaitForChild("Modules")
    DefenseService = require(Modules:WaitForChild("DefenseService"))

	print("⚖️ Inicializando PostureService...")

	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			SetupPlayerPosture(player)
		end)
		
		if player.Character then
			SetupPlayerPosture(player)
		end
	end)

    for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then
			SetupPlayerPosture(player)
		end
	end

	Players.PlayerRemoving:Connect(function(player)
		PlayerPostureStates[player] = nil
	end)

	-- Loop de regeneração (roda a cada frame)
	RunService.Heartbeat:Connect(function(deltaTime)
		for player, state in pairs(PlayerPostureStates) do
			-- Só regenera se NÃO estiver bloqueando e postura < máximo
			local isBlocking = DefenseService and DefenseService.IsPlayerBlocking(player) or false
			
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

	print("⚖️ PostureService iniciado")
end

return PostureService
