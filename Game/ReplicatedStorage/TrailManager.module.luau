--[[
	TrailManager.module.luau
	
	Gerencia os trails das armas:
	- Ativa trail somente durante ataques
	- Detecta automaticamente a Part "Trail" na arma
	- Desativa após duração especificada
]]

local TrailManager = {}

-- Cache de trails por arma
local ActiveTrails = {} -- { [weaponModel] = { Trail = trail } }

-- ============================================================================
-- FUNÇÕES PRIVADAS
-- ============================================================================

-- Encontra o trail dentro do modelo da arma
local function FindTrail(weaponModel)
	-- Procura por uma Part chamada "Trail"
	local trailPart = weaponModel:FindFirstChild("Trail", true) -- true = recursive

	if trailPart and trailPart:IsA("BasePart") then
		-- Procura pelo objeto Trail dentro dessa part
		local trail = trailPart:FindFirstChildOfClass("Trail")
		return trail
	end

	return nil
end

-- ============================================================================
-- FUNÇÕES PÚBLICAS
-- ============================================================================

-- Ativa o trail da arma
function TrailManager.EnableTrail(weaponModel)
	if not weaponModel then 
		warn("[TrailManager] weaponModel é nil!")
		return 
	end

	local trail = FindTrail(weaponModel)

	if trail then
		trail.Enabled = true
		ActiveTrails[weaponModel] = { Trail = trail }
		return true
	else
		warn("[TrailManager] Trail não encontrado em:", weaponModel.Name)
		return false
	end
end

-- Desativa o trail da arma
function TrailManager.DisableTrail(weaponModel)
	if not weaponModel then return end

	local data = ActiveTrails[weaponModel]

	if data and data.Trail then
		data.Trail.Enabled = false
	end

	ActiveTrails[weaponModel] = nil
end

-- Ativa o trail por uma duração específica (em segundos)
function TrailManager.ActivateTrailForDuration(weaponModel, duration)
	if not weaponModel then return end

	-- Ativa o trail
	local success = TrailManager.EnableTrail(weaponModel)
	if not success then return end

	-- Agenda desativação
	-- Nota: Não precisamos cancelar timers anteriores pois DisableTrail é idempotente
	task.delay(duration, function()
		TrailManager.DisableTrail(weaponModel)
	end)
end

-- Verifica se o trail está ativo
function TrailManager.IsTrailActive(weaponModel)
	if not weaponModel then return false end

	local data = ActiveTrails[weaponModel]
	return data ~= nil and data.Trail and data.Trail.Enabled
end

-- Limpa todos os trails (útil para cleanup)
function TrailManager.CleanupAll()
	for weaponModel, _ in pairs(ActiveTrails) do
		TrailManager.DisableTrail(weaponModel)
	end
	ActiveTrails = {}
end

return TrailManager
