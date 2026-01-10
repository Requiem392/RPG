local DefenseHandler = {}
DefenseHandler.__index = DefenseHandler

-- Tabela estática para mapear Player -> Handler (para Networking)
DefenseHandler.Registry = {}

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

-- ============================================================================
-- CONSTRUTOR / DESTRUTOR
-- ============================================================================

function DefenseHandler.new(owner)
    local self = setmetatable({}, DefenseHandler)
    
    self.Owner = owner
    self.State = DefenseManager.CreateDefenseState()
    
    -- Se for player, registra para Networking
    if owner:IsA("Player") then
        DefenseHandler.Registry[owner] = self
        print("🛡️ [DefenseHandler] Estado criado para Player:", owner.Name)
    else
        print("🛡️ [DefenseHandler] Estado criado para NPC/Entity:", owner.Name)
    end

    return self
end

function DefenseHandler:Destroy()
    if self.Owner:IsA("Player") then
        DefenseHandler.Registry[self.Owner] = nil
    end
    self.State = nil
    self.Owner = nil
end

-- ============================================================================
-- MÉTODOS DE INSTÂNCIA
-- ============================================================================

function DefenseHandler:Update(dt)
    if self.State then
        self.State:Update(dt)
    end
end

function DefenseHandler:IsBlocking()
	return self.State and self.State:IsCurrentlyBlocking() or false
end

function DefenseHandler:IsParrying()
	return self.State and self.State:IsInParryWindow() or false
end

function DefenseHandler:IsStunned()
	return self.State and self.State:IsCurrentlyStunned() or false
end

function DefenseHandler:CanParry()
    return self.State and self.State:CanParry() or false
end

function DefenseHandler:Stun(duration)
	if self.State then
		self.State:ApplyStun(duration)

		-- Se for Player, notifica Client
        if self.Owner:IsA("Player") then
            DefenseEvent:FireClient(self.Owner, "StunApplied", {
                Duration = duration
            })
        end

		print("💫 [DefenseHandler]", self.Owner.Name, "stunado por", duration, "segundos")
	end
end

function DefenseHandler:OnParrySuccess(attacker)
	if self.State then
		self.State:ParrySucceeded()

		-- Notifica player que parry foi bem-sucedido
        if self.Owner:IsA("Player") then
		    DefenseEvent:FireClient(self.Owner, "ParrySuccess")
        end

		local config = DefenseManager.GetConfig()
		return config.Parry.Damage
	end
	return 0
end

-- ============================================================================
-- LOGICA DE RESOLUÇÃO DE HIT (Hit / Block / Parry)
-- ============================================================================

function DefenseHandler:ResolveHit(attacker, attackData)
    local result = {
        Status = "Hit",
        Multiplier = 1,
        PostureDamage = 0,
        StunDuration = 0,
        DamageReturn = 0
    }
    
    if self:IsParrying() then
        self:OnParrySuccess(attacker) -- Atualiza estado interno
        result.Status = "Parry"
        
        local config = DefenseManager.GetConfig()
        result.StunDuration = config.Parry.StunDuration
        result.DamageReturn = config.Parry.Damage
        result.Multiplier = 0
        return result
    end
    
    if self:IsBlocking() then
        result.Status = "Block"
        result.Multiplier = 0 
        return result
    end
    
    return result
end

-- Método para recuperar a instância de defesa de uma entidade (Player ou NPC se registrado)
function DefenseHandler.GetHandler(entity)
    if entity:IsA("Player") then
        return DefenseHandler.Registry[entity]
    end
    -- TODO: Implementar lookup para NPCs se não forem Players (usando CollectionService ou atributo?)
    return nil
end


-- ============================================================================
-- INICIALIZAÇÃO ESTÁTICA (NETWORKING & LOOP)
-- ============================================================================

local Initialized = false

function DefenseHandler.Init()
    if Initialized then return end
    Initialized = true

	print("🛡️ Inicializando DefenseHandler (Static)...")

	-- Ações defensivas do cliente (Roteamento)
	DefenseEvent.OnServerEvent:Connect(function(player, action, data)
		local handler = DefenseHandler.Registry[player]
        if not handler then return end
        
        local state = handler.State
		if not state then return end

		if action == "StartBlock" then
			local success = state:StartBlock()
			if success then
				-- print("🛡️ [DefenseHandler]", player.Name, "começou a bloquear")
			end

		elseif action == "StopBlock" then
			state:StopBlock()
			-- print("🛡️ [DefenseHandler]", player.Name, "parou de bloquear")

		elseif action == "StartParry" then
			local success = state:StartParry()
			if success then
				print("⚔️ [DefenseHandler]", player.Name, "ativou parry")
				DefenseEvent:FireClient(player, "ParryActive", {
					Window = DefenseManager.GetConfig().Parry.Window
				})
			end
		end
	end)

	-- Requisições do cliente (Roteamento)
	DefenseRequest.OnServerInvoke = function(player, action)
		local handler = DefenseHandler.Registry[player]
		if not handler or not handler.State then return false end
        local state = handler.State

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

	-- Update Loop (Global Heartbeat para todos os handlers registrados)
	RunService.Heartbeat:Connect(function(dt)
        -- Atualiza Players
		for player, handler in pairs(DefenseHandler.Registry) do
			handler:Update(dt)
		end
	end)
	
	print("✅ DefenseHandler Loop iniciado")
end

return DefenseHandler
