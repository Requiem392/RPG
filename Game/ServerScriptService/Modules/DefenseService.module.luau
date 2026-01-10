--[[
	DefenseService.module.luau
	
	Gerencia estados defensivos de todos os jogadores no servidor:
	- Block (bloqueio)
	- Parry (contra-ataque)
	- Stun (atordoamento)
]]

local DefenseService = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Módulos
local DefenseManager = require(ReplicatedStorage:WaitForChild("DefenseManager"))

-- Remotes
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local DefenseEvent = Remotes:FindFirstChild("DefenseAction")
if not DefenseEvent then
    DefenseEvent = Instance.new("RemoteEvent")
    DefenseEvent.Name = "DefenseAction"
    DefenseEvent.Parent = Remotes
end

local DefenseRequest = Remotes:FindFirstChild("DefenseRequest")
if not DefenseRequest then
    DefenseRequest = Instance.new("RemoteFunction")
    DefenseRequest.Name = "DefenseRequest"
    DefenseRequest.Parent = Remotes
end

-- Estado
local PlayerDefenseStates = {} -- { [Player] = DefenseState }

-- ============================================================================
-- FUNÇÕES INTERNAS
-- ============================================================================

-- Cria estado defensivo para novo jogador
local function SetupPlayerDefense(player)
	if PlayerDefenseStates[player] then return end
	
	local defenseState = DefenseManager.CreateDefenseState()
	PlayerDefenseStates[player] = defenseState

	print("🛡️ [DefenseService] Estados defensivos criados para:", player.Name)
end

-- ============================================================================
-- MÉTODOS DO SERVIÇO
-- ============================================================================

function DefenseService.IsPlayerBlocking(player)
	local state = PlayerDefenseStates[player]
	return state and state:IsCurrentlyBlocking() or false
end

function DefenseService.IsPlayerParrying(player)
	local state = PlayerDefenseStates[player]
	return state and state:IsInParryWindow() or false
end

function DefenseService.IsPlayerStunned(player)
	local state = PlayerDefenseStates[player]
	return state and state:IsCurrentlyStunned() or false
end

function DefenseService.StunPlayer(player, duration)
	local state = PlayerDefenseStates[player]
	if state then
		state:ApplyStun(duration)

		-- Notifica cliente para tocar animação de stun
		DefenseEvent:FireClient(player, "StunApplied", {
			Duration = duration
		})

		print("💫 [DefenseService]", player.Name, "stunado por", duration, "segundos")
	end
end

function DefenseService.OnParrySuccess(player, attacker)
	local state = PlayerDefenseStates[player]
	if state then
		state:ParrySucceeded()

		-- Notifica player que parry foi bem-sucedido
		DefenseEvent:FireClient(player, "ParrySuccess")

		-- Stuna o atacante
		local config = DefenseManager.GetConfig()
		if attacker then
			DefenseService.StunPlayer(attacker, config.Parry.StunDuration)
		end

		-- Retorna dano do parry
		return config.Parry.Damage
	end
	return 0
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

function DefenseService.Init()
	print("🛡️ Inicializando DefenseService...")

	-- Player entra
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			SetupPlayerDefense(player)
		end)

		if player.Character then
			SetupPlayerDefense(player)
		end
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then
			SetupPlayerDefense(player)
		end
	end

	-- Player sai
	Players.PlayerRemoving:Connect(function(player)
		PlayerDefenseStates[player] = nil
	end)

	-- Ações defensivas do cliente
	DefenseEvent.OnServerEvent:Connect(function(player, action, data)
		local state = PlayerDefenseStates[player]
		if not state then return end

		if action == "StartBlock" then
			local success = state:StartBlock()
			if success then
				print("🛡️ [DefenseService]", player.Name, "começou a bloquear")
			end

		elseif action == "StopBlock" then
			state:StopBlock()
			print("🛡️ [DefenseService]", player.Name, "parou de bloquear")

		elseif action == "StartParry" then
			local success = state:StartParry()
			if success then
				print("⚔️ [DefenseService]", player.Name, "ativou parry")

				-- Notifica cliente que parry está ativo
				DefenseEvent:FireClient(player, "ParryActive", {
					Window = DefenseManager.GetConfig().Parry.Window
				})
			end
		end
	end)

	-- Requisições do cliente
	DefenseRequest.OnServerInvoke = function(player, action)
		local state = PlayerDefenseStates[player]
		if not state then return false end

		if action == "IsBlocking" then
			return state:IsCurrentlyBlocking()
		elseif action == "IsParrying" then
			return state:IsInParryWindow()
		elseif action == "IsStunned" then
			return state:IsCurrentlyStunned()
		elseif action == "CanParry" then
			return state:CanParry()
		end

		return false
	end

	-- Update loop
	RunService.Heartbeat:Connect(function()
		for player, state in pairs(PlayerDefenseStates) do
			state:Update()
		end
	end)
	
	print("✅ DefenseService iniciado")
end

return DefenseService
