--[[
	ResourceManager.module.luau
	
	Gerencia recursos do jogador (Energia/Stamina e Mana)
	- Energia: Para ataques físicos e block
	- Mana: Para habilidades mágicas (futuro)
]]

local ResourceManager = {}

-- Configurações
local CONFIG = {
	Stamina = {
		Max = 100,
		AttackCost = 10,
		BlockCostPerSecond = 5,
		RegenRate = 20,        -- Por segundo
		RegenDelay = 1.5       -- Segundos de espera após gastar
	},
	Mana = {
		Max = 100,
		RegenRate = 5,         -- Por segundo
		RegenDelay = 0         -- Regen constante
	}
}

-- ============================================================================
-- CLASSE DE RECURSO
-- ============================================================================

local Resource = {}
Resource.__index = Resource

function Resource.new(maxValue, regenRate, regenDelay)
	local self = setmetatable({}, Resource)

	self.Max = maxValue
	self.Current = maxValue
	self.RegenRate = regenRate
	self.RegenDelay = regenDelay
	self.LastUseTime = 0
	self.IsRegenerating = false

	return self
end

-- Usa recurso (retorna true se tinha suficiente)
function Resource:Use(amount)
	if self.Current >= amount then
		self.Current = math.max(0, self.Current - amount)
		self.LastUseTime = tick()
		return true
	end
	return false
end

-- Verifica se tem recurso suficiente
function Resource:CanAfford(amount)
	return self.Current >= amount
end

-- Regenera recurso (chamado a cada frame)
function Resource:Update(deltaTime)
	if self.Current >= self.Max then
		self.Current = self.Max
		self.IsRegenerating = false
		return
	end

	-- Verifica delay de regeneração
	local timeSinceUse = tick() - self.LastUseTime
	if timeSinceUse < self.RegenDelay then
		self.IsRegenerating = false
		return
	end

	-- Regenera
	self.IsRegenerating = true
	self.Current = math.min(self.Max, self.Current + (self.RegenRate * deltaTime))
end

-- Seta valor (usado para sincronização)
function Resource:Set(value)
	self.Current = math.clamp(value, 0, self.Max)
end

-- Pega percentual (0-1)
function Resource:GetPercent()
	return self.Current / self.Max
end

-- ============================================================================
-- GERENCIADOR DE RECURSOS DO PLAYER
-- ============================================================================

local PlayerResources = {}
PlayerResources.__index = PlayerResources

function PlayerResources.new()
	local self = setmetatable({}, PlayerResources)

	self.Stamina = Resource.new(
		CONFIG.Stamina.Max,
		CONFIG.Stamina.RegenRate,
		CONFIG.Stamina.RegenDelay
	)

	self.Mana = Resource.new(
		CONFIG.Mana.Max,
		CONFIG.Mana.RegenRate,
		CONFIG.Mana.RegenDelay
	)

	return self
end

-- Update (chame via RunService)
function PlayerResources:Update(deltaTime)
	self.Stamina:Update(deltaTime)
	self.Mana:Update(deltaTime)
end

-- ============================================================================
-- FUNÇÕES PÚBLICAS
-- ============================================================================

-- Retorna configurações
function ResourceManager.GetConfig()
	return CONFIG
end

-- Cria novo gerenciador de recursos para um player
function ResourceManager.CreatePlayerResources()
	return PlayerResources.new()
end

return ResourceManager
