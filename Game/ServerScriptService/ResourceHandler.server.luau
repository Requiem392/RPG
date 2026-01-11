--[[
	ResourceHandler.server.luau
	
	Gerencia recursos de todos os jogadores no servidor
	- Validação autoritativa (anti-cheat)
	- Sincronização com clientes
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Módulos
local ResourceManager = require(ReplicatedStorage:WaitForChild("ResourceManager"))
local Modules = game:GetService("ServerScriptService"):WaitForChild("Modules") 
-- SoundManager está em ReplicatedStorage/Modules agora, mas vamos checar onde o user pediu. 
-- User pediu em ReplicatedStorage/Modules.
local ReplicatedModules = ReplicatedStorage:WaitForChild("Modules")
local SoundManager = require(ReplicatedModules:WaitForChild("SoundManager"))

-- Remotes
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local ResourceEvent = Instance.new("RemoteEvent")
ResourceEvent.Name = "ResourceUpdate"
ResourceEvent.Parent = Remotes

local ResourceRequest = Instance.new("RemoteFunction")
ResourceRequest.Name = "ResourceRequest"
ResourceRequest.Parent = Remotes

local ServerStorage = game:GetService("ServerStorage")
local ServerEvents = ServerStorage:FindFirstChild("ServerEvents")
if not ServerEvents then
	ServerEvents = Instance.new("Folder")
	ServerEvents.Name = "ServerEvents"
	ServerEvents.Parent = ServerStorage
end

local ResourceBindable = Instance.new("BindableFunction")
ResourceBindable.Name = "ResourceBindable"
ResourceBindable.Parent = ServerEvents

-- Estado
local PlayerResources = {} -- { [Player] = PlayerResources }

-- ============================================================================
-- FUNÇÕES
-- ============================================================================

-- Cria recursos para novo jogador
local function SetupPlayerResources(player)
	local resources = ResourceManager.CreatePlayerResources()
	PlayerResources[player] = resources

	print("🔋 [ResourceHandler] Recursos criados para:", player.Name)

	-- Envia estado inicial para cliente
	ResourceEvent:FireClient(player, "Init", {
		Stamina = resources.Stamina.Current,
		Mana = resources.Mana.Current
	})
end

-- Tenta usar stamina
local function UseStamina(player, amount)
	local resources = PlayerResources[player]
	if not resources then return false end

	local success = resources.Stamina:Use(amount)

	if success then
		-- Notifica cliente da mudança
		ResourceEvent:FireClient(player, "Update", {
			Stamina = resources.Stamina.Current
		})
	end

	return success
end

-- Tenta usar mana
local function UseMana(player, amount)
	local resources = PlayerResources[player]
	if not resources then return false end

	local success = resources.Mana:Use(amount)

	if success then
		ResourceEvent:FireClient(player, "Update", {
			Mana = resources.Mana.Current
		})
	end

	return success
end

-- Verifica se pode gastar
local function CanAffordStamina(player, amount)
	local resources = PlayerResources[player]
	if not resources then return false end

	return resources.Stamina:CanAfford(amount)
end

-- ============================================================================
-- EVENTOS
-- ============================================================================

-- Player entra
Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function()
		SetupPlayerResources(player)
	end)

	if player.Character then
		SetupPlayerResources(player)
	end
end)

-- Player sai
Players.PlayerRemoving:Connect(function(player)
	PlayerResources[player] = nil
end)

-- Requisições do cliente (ex: gastar energia)
ResourceRequest.OnServerInvoke = function(player, action, amount)
	if action == "UseStamina" then
		return UseStamina(player, amount)
	elseif action == "UseMana" then
		return UseMana(player, amount)
	elseif action == "CanAffordStamina" then
		return CanAffordStamina(player, amount)
	elseif action == "GetStamina" then
		local resources = PlayerResources[player]
		return resources and resources.Stamina.Current or 0
	end

	return false
end

-- Server-Side API (via BindableFunction)
ResourceBindable.OnInvoke = function(action, player, amount)
	if action == "UseStamina" then
		return UseStamina(player, amount)
	elseif action == "CanAffordStamina" then
		return CanAffordStamina(player, amount)
	elseif action == "UseMana" then
		return UseMana(player, amount)
	end
	return false
end

-- Update loop (regeneração)
local lastUpdate = tick()
RunService.Heartbeat:Connect(function()
	local now = tick()
	local deltaTime = now - lastUpdate
	lastUpdate = now

	-- Atualiza recursos de cada player
	for player, resources in pairs(PlayerResources) do
		local oldStamina = resources.Stamina.Current
		local oldMana = resources.Mana.Current

		resources:Update(deltaTime)

		-- LOW STAMINA LOGIC
		if player.Character then
			local humanoid = player.Character:FindFirstChild("Humanoid")
			if humanoid then
				local maxStamina = resources.Stamina.Max
				local currentStamina = resources.Stamina.Current
				local ratio = currentStamina / maxStamina
				
				local isLowStamina = ratio < 0.25
				if humanoid:GetAttribute("LowStamina") ~= isLowStamina then
					humanoid:SetAttribute("LowStamina", isLowStamina)
					
					local rootPart = player.Character:FindFirstChild("HumanoidRootPart")
					if rootPart then
						if isLowStamina then
							-- Create & Play Sound via SoundManager
							SoundManager.PlaySound("rbxassetid://1386876127", rootPart, 1.0, true, "TiredBreathingSound")
						else
							-- Fade Out & Destroy Sound via SoundManager
							SoundManager.DestroySound(rootPart, "TiredBreathingSound", 1.0)
						end
					end
				end
			end
		end

		-- Se mudou, notifica cliente
		if resources.Stamina.Current ~= oldStamina or resources.Mana.Current ~= oldMana then
			ResourceEvent:FireClient(player, "Update", {
				Stamina = resources.Stamina.Current,
				Mana = resources.Mana.Current
			})
		end
	end
end)

print("✅ ResourceHandler iniciado")
