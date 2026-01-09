--[[
	NPCStateMachine.module.luau
	
	Pilar 2: STATE MACHINE
	
	Responsabilidades:
	- Gerenciar estado atual (Enter, Update, Exit)
	- Processar transições de estado
	- Garantir que apenas UM estado esteja ativo
	
	NÃO FAZ:
	- Tomar decisões (Pilar 3)
	- Executar combate (Pilar 5)
]]

local NPCStateMachine = {}
local States = {}

-- Carrega todos os estados da pasta States
local StatesFolder = script.Parent:WaitForChild("States")
for _, module in ipairs(StatesFolder:GetChildren()) do
	if module:IsA("ModuleScript") then
		States[module.Name] = require(module)
		print("📦 [StateMachine] Estado carregado:", module.Name)
	end
end

-- ======================================================================
-- DADOS DE ESTADO (por NPC)
-- ======================================================================

local StateData = {}

function NPCStateMachine.InitializeNPC(npc)
	StateData[npc] = {
		CurrentState = nil,
		StateName = "None",
		StateTime = 0,
		Context = {}  -- Dados compartilhados entre estados
	}
	
	-- Estado inicial padrão: IDLE
	NPCStateMachine.ChangeState(npc, "Idle")
end

-- ======================================================================
-- TRANSIÇÃO DE ESTADO
-- ======================================================================

function NPCStateMachine.ChangeState(npc, newStateName)
	local data = StateData[npc]
	if not data then return end
	
	-- Se já está no estado e ele não permite reentrada, ignora
	if data.StateName == newStateName then
		return
	end
	
	local newState = States[newStateName]
	if not newState then
		warn("❌ [StateMachine] Estado inexistente:", newStateName)
		return
	end
	
	-- 1. Sai do estado anterior
	if data.CurrentState and data.CurrentState.Exit then
		data.CurrentState.Exit(npc, data.Context)
	end
	
	-- 2. Atualiza referência
	local oldStateName = data.StateName
	data.CurrentState = newState
	data.StateName = newStateName
	data.StateTime = tick()
	
	-- 3. Entra no novo estado
	if newState.Enter then
		newState.Enter(npc, data.Context)
	end
	
	-- DEBUG (opcional)
	-- print(string.format("🔄 [State] %s: %s -> %s", npc.Name, oldStateName, newStateName))
end

-- ======================================================================
-- ATUALIZAÇÃO
-- ======================================================================

function NPCStateMachine.Update(npc, dt)
	local data = StateData[npc]
	if not data or not data.CurrentState then return end
	
	-- Chama Update do estado atual
	if data.CurrentState.Update then
		data.CurrentState.Update(npc, data.Context, dt)
	end
end

-- ======================================================================
-- API PÚBLICA
-- ======================================================================

function NPCStateMachine.GetState(npc)
	local data = StateData[npc]
	return data and data.StateName or "None"
end

function NPCStateMachine.GetContext(npc)
	local data = StateData[npc]
	return data and data.Context or nil
end

function NPCStateMachine.Cleanup(npc)
	local data = StateData[npc]
	if data and data.CurrentState and data.CurrentState.Exit then
		data.CurrentState.Exit(npc, data.Context)
	end
	StateData[npc] = nil
end

return NPCStateMachine
