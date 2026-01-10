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

		-- Stuna o atacante (se houver atacante e for registrado no sistema, podemos interagir)
        -- Aqui recebemos o 'attacker' que pode ser um Player ou NPC
        -- O sistema de combate deve chamar .Stun() no handler do atacante.
        -- Mas aqui, dentro do handler de quem DEFENDEU, precisamos aplicar o efeito no atacante.
        -- Para isso, precisamos do Handler do atacante.
        
        -- O argumento 'attacker' aqui era 'player object' no código antigo?
        -- No código antigo: function DefenseService.OnParrySuccess(player, attacker) ... StunPlayer(attacker)
        -- Agora: self é quem defendeu. 'attacker' é quem atacou.
        
        -- Se o attacker for Player, buscamos no Registry.
        -- Se for NPC, precisaríamos de um jeito de pegar o handler dele.
        -- POR ENQUANTO, assumiremos que 'attacker' é um PlayerInstance ou Model.
        -- O ideal seria passar o AttackerHandler, mas manteremos compatibilidade básica.
        
		local config = DefenseManager.GetConfig()
        
        -- Tenta resolver o Handler do atacante
        local attackerHandler = nil
        if attacker:IsA("Player") then
            attackerHandler = DefenseHandler.Registry[attacker]
        else
            -- Para NPC, o chamador deveria ter resolvido, ou usamos um método global de lookup se existisse.
            -- Como não temos global lookup fácil para NPC aqui, vamos deixar para o chamador lidar com o stun do atacante?
            -- O código antigo chamava DefenseService.StunPlayer(attacker).
            -- Se eu mantiver DefenseHandler.GetHandler(entity), posso resolver.
        end

        -- Vamos criar um Helper estático GetHandler
        local targetHandler = DefenseHandler.GetHandler(attacker)
		if targetHandler then
			targetHandler:Stun(config.Parry.StunDuration)
		end

		return config.Parry.Damage
	end
	return 0
end

-- ============================================================================
-- LOGICA DE RESOLUÇÃO DE HIT (Hit / Block / Parry)
-- ============================================================================

function DefenseHandler:ResolveHit(attacker, attackData)
    -- Retorna: "Hit", "Block", "Parry" (ou tabela mais complexa)
    
    if self:IsParrying() then
        -- Sucesso de Parry
        -- Chama callback interna (Stun e Dano de Parry deve ser resolvido aqui ou pelo orquestrador?)
        -- O usuário pediu: "CombatHandler só orquestra".
        -- Então DefenseHandler diz "Foi Parry", e CombatHandler aplica os efeitos (Stun attacker).
        -- Mas a lógica de "quem stuna quem" é regra de combate.
        -- Vamos retornar o STATUS e deixar CombatHandler aplicar os efeitos colaterais baseados nisso?
        -- Ou melhor: ResolveHit aplica efeitos de DEFESA (consumo de stamina, stun no defender se break posture) 
        -- e retorna info pro CombatHandler aplicar efeitos no ATTACKER.
        
        self:OnParrySuccess(attacker) -- Aplica efeitos internos (reset janela, fx)
        return "Parry"
    end
    
    if self:IsBlocking() then
        -- Verifica angulo de bloqueio? (Futuro)
        -- Verifica Posture
        return "Block"
    end
    
    return "Hit"
end

-- Método para recuperar a instância de defesa de uma entidade (Player ou NPC se registrado)
-- OBS: Para NPC, precisaremos de um mecanismo de registro também se quisermos lookup global.
-- Por enquanto, usaremos apenas para Players no Registry.
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
    -- Isso evita ter N conexões heartbeat.
	RunService.Heartbeat:Connect(function(dt)
        -- Atualiza Players
		for player, handler in pairs(DefenseHandler.Registry) do
			handler:Update(dt)
		end
        -- TODO: Se tivermos NPCs, iterar sobre lista de NPCs também.
	end)
	
	print("✅ DefenseHandler Loop iniciado")
end

return DefenseHandler
