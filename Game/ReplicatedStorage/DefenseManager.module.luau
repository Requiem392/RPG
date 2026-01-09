--[[
	DefenseManager.module.luau
	
	Gerencia estados defensivos:
	- Block: Bloqueio contínuo (drena energia)
	- Parry: Contra-ataque com timing (risco/recompensa)
]]

local DefenseManager = {}

-- Configurações
local CONFIG = {
	Block = {
		DrainPerSecond = 5,  -- Energia drenada por segundo
	},

	Parry = {
		Cost = 15,           -- Custo único ao ativar
		Window = 0.5,        -- Janela de tempo para parry (segundos)
		Damage = 20,         -- Dano causado em parry bem-sucedido
		StunDuration = 2,    -- Duração do stun (segundos)
		Cooldown = 3,        -- Cooldown entre parries (segundos)
	}
}

-- ============================================================================
-- CLASSE DE ESTADO DEFENSIVO
-- ============================================================================

local DefenseState = {}
DefenseState.__index = DefenseState

function DefenseState.new()
	local self = setmetatable({}, DefenseState)

	-- Block
	self.IsBlocking = false
	self.BlockStartTime = 0

	-- Parry
	self.IsParrying = false
	self.ParryStartTime = 0
	self.LastParryTime = 0
	self.ParrySuccess = false  -- Se parry foi bem-sucedido

	-- Stun
	self.IsStunned = false
	self.StunEndTime = 0

	return self
end

-- ============================================================================
-- BLOCK
-- ============================================================================

function DefenseState:StartBlock()
	if self.IsStunned then return false end
	if self.IsParrying then return false end

	self.IsBlocking = true
	self.BlockStartTime = tick()
	return true
end

function DefenseState:StopBlock()
	self.IsBlocking = false
end

function DefenseState:IsCurrentlyBlocking()
	return self.IsBlocking and not self.IsStunned
end

-- ============================================================================
-- PARRY
-- ============================================================================

function DefenseState:CanParry()
	if self.IsStunned then return false end
	if self.IsBlocking then return false end
	if self.IsParrying then return false end

	-- Verifica cooldown
	local timeSinceLastParry = tick() - self.LastParryTime
	if timeSinceLastParry < CONFIG.Parry.Cooldown then return false end

	return true
end

function DefenseState:StartParry()
	if not self:CanParry() then return false end

	self.IsParrying = true
	self.ParryStartTime = tick()
	self.ParrySuccess = false
	return true
end

function DefenseState:IsInParryWindow()
	if not self.IsParrying then return false end

	local elapsed = tick() - self.ParryStartTime
	return elapsed <= CONFIG.Parry.Window
end

function DefenseState:ParrySucceeded()
	self.ParrySuccess = true
	self.IsParrying = false
	self.LastParryTime = tick()
end

function DefenseState:ParryFailed()
	self.IsParrying = false
	self.LastParryTime = tick()
	-- Auto-stun por falhar parry
	self:ApplyStun(CONFIG.Parry.StunDuration)
end

function DefenseState:CheckParryTimeout()
	if not self.IsParrying then return end

	local elapsed = tick() - self.ParryStartTime

	-- Se passou da janela e não teve sucesso, falhou
	if elapsed > CONFIG.Parry.Window and not self.ParrySuccess then
		self:ParryFailed()
	end
end

-- ============================================================================
-- STUN
-- ============================================================================

function DefenseState:ApplyStun(duration)
	self.IsStunned = true
	self.StunEndTime = tick() + duration

	-- Cancela qualquer estado defensivo
	self.IsBlocking = false
	self.IsParrying = false
end

function DefenseState:UpdateStun()
	if not self.IsStunned then return end

	if tick() >= self.StunEndTime then
		self.IsStunned = false
	end
end

function DefenseState:IsCurrentlyStunned()
	self:UpdateStun()
	return self.IsStunned
end

-- ============================================================================
-- UPDATE
-- ============================================================================

function DefenseState:Update()
	self:UpdateStun()
	self:CheckParryTimeout()
end

-- ============================================================================
-- FUNÇÕES PÚBLICAS
-- ============================================================================

function DefenseManager.GetConfig()
	return CONFIG
end

function DefenseManager.CreateDefenseState()
	return DefenseState.new()
end

return DefenseManager
