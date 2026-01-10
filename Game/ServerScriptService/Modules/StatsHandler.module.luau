local StatsHandler = {}
StatsHandler.__index = StatsHandler
StatsHandler.Registry = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

-- Módulos
local DataFolder = ReplicatedStorage:WaitForChild("Data")
local ItemData = require(DataFolder:WaitForChild("ItemData"))

-- Remotes & Events
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local UpdateStatsEvent = Remotes:FindFirstChild("UpdateStats") 
if not UpdateStatsEvent then
    UpdateStatsEvent = Instance.new("RemoteEvent")
    UpdateStatsEvent.Name = "UpdateStats"
    UpdateStatsEvent.Parent = Remotes
end

local ServerEvents = ServerStorage:FindFirstChild("ServerEvents")
if not ServerEvents then
    ServerEvents = Instance.new("Folder")
    ServerEvents.Name = "ServerEvents"
    ServerEvents.Parent = ServerStorage
end

local GearUpdateEvent = ServerEvents:FindFirstChild("GearUpdate")
if not GearUpdateEvent then
    GearUpdateEvent = Instance.new("BindableEvent")
    GearUpdateEvent.Name = "GearUpdate"
    GearUpdateEvent.Parent = ServerEvents
end

-- ======================================================================
-- CONSTRUTOR
-- ======================================================================

function StatsHandler.new(owner)
    local self = setmetatable({}, StatsHandler)
    self.Owner = owner
    
    self.BaseStats = {
        Level = 1,
        XP = 0,
        MaxXP = 100,
        BaseDamage = 5,
        BaseDefense = 0,
        BaseCritChance = 5,
        BaseCritDamage = 150
    }
    self.CurrentGear = {} -- Cache
    
    StatsHandler.Registry[owner] = self
    
    -- Inicializa
    task.delay(1, function()
        if self.Owner then -- check validity
             self:Recalculate()
        end
    end)
    
    return self
end

function StatsHandler:Destroy()
    StatsHandler.Registry[self.Owner] = nil
    self.Owner = nil
end

-- ======================================================================
-- MÉTODOS
-- ======================================================================

function StatsHandler:Recalculate(newGear)
    if newGear then self.CurrentGear = newGear end
    
    local base = self.BaseStats
    
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
	for slot, item in pairs(self.CurrentGear) do
		local data = ItemData.Get(item.Name)
		if data then
			if data.Damage then finalStats.Damage += data.Damage end
			if data.Defense then finalStats.Defense += data.Defense end
			if data.CritChance then finalStats.CritChance += data.CritChance end
			if data.CritDamage then finalStats.CritDamage += data.CritDamage end
		end
	end
    
    self.ComputedStats = finalStats -- Store for getters
    
    -- Envia pro Cliente
    if self.Owner:IsA("Player") then
	    UpdateStatsEvent:FireClient(self.Owner, finalStats)
    end
end

function StatsHandler:GetStats()
    return self.ComputedStats or self.BaseStats -- Fallback
end

-- Static helper
function StatsHandler.GetHandler(entity)
    return StatsHandler.Registry[entity]
end


-- ======================================================================
-- INIT
-- ======================================================================

local Initialized = false
function StatsHandler.Init()
    if Initialized then return end
    Initialized = true
    
    print("📊 Inicializando StatsHandler (Static)...")

    GearUpdateEvent.Event:Connect(function(owner, newGear)
        local handler = StatsHandler.Registry[owner]
        if handler then
            handler:Recalculate(newGear)
        end
    end)
    
    print("✅ StatsHandler Events iniciados")
end

return StatsHandler
