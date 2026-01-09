local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

-- Módulos
local DataFolder = ReplicatedStorage:WaitForChild("Data")
local ItemData = require(DataFolder:WaitForChild("ItemData"))

-- Remotes & Events
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local UpdateStatsEvent = Remotes:WaitForChild("UpdateStats") -- Criar Manualmente

local ServerEvents = ServerStorage:WaitForChild("ServerEvents")
local GearUpdateEvent = ServerEvents:WaitForChild("GearUpdate") -- Criar Manualmente

-- Dados
local PlayerStats = {} -- { [UserId] = { Level=1, XP=0, BaseDamage=5, ... } }
local PlayerGear = {} -- Cache do gear atual pra calculo

-- Inicialização
local function SetupStats(player)
	PlayerStats[player.UserId] = {
		Level = 1,
		XP = 0,
		MaxXP = 100,
		-- Status Base (Sem Equipamento)
		BaseDamage = 5,
		BaseDefense = 0,
		BaseCritChance = 5, -- %
		BaseCritDamage = 150 -- %
	}
	PlayerGear[player.UserId] = {}

	-- Primeira atualização
	task.wait(1) -- Espera carregar
	RecalculateAndSend(player)
end

function RecalculateAndSend(player)
	local userId = player.UserId
	local base = PlayerStats[userId]
	local gear = PlayerGear[userId] or {}

	if not base then return end

	-- Totais
	local finalStats = {
		Level = base.Level,
		XP = base.XP,
		MaxXP = base.MaxXP,
		Damage = base.BaseDamage,
		Defense = base.BaseDefense,
		CritChance = base.BaseCritChance,
		CritDamage = base.BaseCritDamage
	}

	-- Soma Equipamentos
	for slot, item in pairs(gear) do
		local data = ItemData.Get(item.Name)
		if data then
			if data.Damage then finalStats.Damage += data.Damage end
			if data.Defense then finalStats.Defense += data.Defense end
			if data.CritChance then finalStats.CritChance += data.CritChance end
			if data.CritDamage then finalStats.CritDamage += data.CritDamage end
		end
	end

	-- Envia pro Cliente
	UpdateStatsEvent:FireClient(player, finalStats)
end

-- Listeners
-- GearUpdateEvent já foi definido no topo via WaitForChild

GearUpdateEvent.Event:Connect(function(player, newGear)
	PlayerGear[player.UserId] = newGear
	RecalculateAndSend(player)
end)

Players.PlayerAdded:Connect(SetupStats)
for _, p in ipairs(Players:GetPlayers()) do SetupStats(p) end

Players.PlayerRemoving:Connect(function(p)
	PlayerStats[p.UserId] = nil
	PlayerGear[p.UserId] = nil
end)

-- Exporta para outros sistemas usarem
_G.PlayerStats = PlayerStats
_G.RecalculateAndSend = RecalculateAndSend

print("✅ StatsHandler iniciado")
