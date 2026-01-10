--[[
	NPCManager.server.luau
	
	Gerencia NPCs:
	- Spawn de NPCs
	- Inicialização de sistemas (Stats, Defense, Inventory, Posture)
	- Loop de atualização de Percepção
	- Cleanup quando NPC morre
]]

local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Modules = ServerScriptService:WaitForChild("Modules")

-- Módulos de IA
local NPCPerception = require(script.Parent.NPCPerception)
local NPCStateMachine = require(script.Parent.NPCStateMachine)
local NPCDecision = require(script.Parent.NPCDecision)

-- Módulos de Gameplay (Classes)
local StatsHandler = require(Modules:WaitForChild("StatsHandler"))
local DefenseHandler = require(Modules:WaitForChild("DefenseHandler"))
local PostureHandler = require(Modules:WaitForChild("PostureHandler"))
local InventoryHandler = require(Modules:WaitForChild("InventoryHandler"))

-- ======================================================================
-- CONFIGURAÇÃO
-- ======================================================================

local UPDATE_INTERVAL = 0.2  -- Atualiza percepção a cada 0.2s

-- Função para obter posições de spawn
local function GetSpawnPositions()
	local positions = {}
	local spawnLocation = workspace:FindFirstChildOfClass("SpawnLocation")
	if spawnLocation then
		local spawnPos = spawnLocation.Position
		table.insert(positions, spawnPos + Vector3.new(0, 0, 8))
	else
		warn("⚠️ [NPCManager] SpawnLocation não encontrado, usando posições padrão")
		table.insert(positions, Vector3.new(0, 5, 20))
	end
	return positions
end

-- ======================================================================
-- GERENCIAMENTO DE NPCs
-- ======================================================================

local ActiveNPCs = {} -- Lista de Models
local NPCSessions = {} -- Mapa de Sessions { [NPCModel] = {Stats=..., Defense=...} }
local LastUpdateTime = 0

-- Spawna um NPC
local function SpawnNPC(position)
	local npcTemplate = ServerStorage:FindFirstChild("NPC")
	if not npcTemplate then
		warn("❌ [NPCManager] Modelo 'NPC' não encontrado no ServerStorage!")
		return nil
	end
	
	-- Clona NPC
	local npc = npcTemplate:Clone()
	npc.Name = "NPC_" .. tick()
	
	if npc.PrimaryPart then
		npc:SetPrimaryPartCFrame(CFrame.new(position))
	elseif npc:FindFirstChild("HumanoidRootPart") then
		npc.HumanoidRootPart.CFrame = CFrame.new(position)
	end
	
	npc.Parent = workspace
	
	-- 1. Inicializa IA
	NPCPerception.InitializeNPC(npc)
	NPCStateMachine.InitializeNPC(npc)
	
    -- 2. Inicializa Sistemas de Gameplay (Isolados)
    -- Cria instâncias dos handlers para este NPC específico
    local session = {
        Stats = StatsHandler.new(npc),
        Defense = DefenseHandler.new(npc),
        Posture = PostureHandler.new(npc),
        Inventory = InventoryHandler.new(npc)
    }
    NPCSessions[npc] = session
    
    -- Debug: Dar item pro NPC?
    -- session.Inventory:AddItem("Sword", 1) 
	
	table.insert(ActiveNPCs, npc)
	
	-- Listener de morte
	local humanoid = npc:FindFirstChild("Humanoid")
	if humanoid then
		humanoid.Died:Connect(function()
			RemoveNPC(npc)
		end)
	end
	
	print("✅ [NPCManager] NPC spawnado e inicializado com sucesso:", npc.Name)
	return npc
end

-- Remove NPC
function RemoveNPC(npc)
	for i, activeNPC in ipairs(ActiveNPCs) do
		if activeNPC == npc then
			table.remove(ActiveNPCs, i)
			break
		end
	end
	
    -- Cleanup Sistemas Gameplay
    local session = NPCSessions[npc]
    if session then
        if session.Inventory then session.Inventory:Destroy() end
        if session.Posture then session.Posture:Destroy() end
        if session.Defense then session.Defense:Destroy() end
        if session.Stats then session.Stats:Destroy() end
        NPCSessions[npc] = nil
    end

	-- Cleanup IA
	NPCPerception.Cleanup(npc)
	NPCStateMachine.Cleanup(npc)
	
	task.delay(3, function()
		if npc and npc.Parent then
			npc:Destroy()
		end
	end)
	
	print("🗑️ [NPCManager] NPC removido:", npc.Name)
end

-- ======================================================================
-- LOOP DE ATUALIZAÇÃO
-- ======================================================================

RunService.Heartbeat:Connect(function(step)
	local currentTime = tick()
	local dt = currentTime - LastUpdateTime
	
	for _, npc in ipairs(ActiveNPCs) do
		if npc and npc.Parent then
			-- 1. Percepção (Throttle)
			if dt >= UPDATE_INTERVAL then
				NPCPerception.Update(npc)
				
				-- DEBUG info (opcional, pode ser comentado)
				-- local data = NPCPerception.GetData(npc)
				-- if data and data.CurrentTarget then ... end
			end
			
			-- 2. Tomada de Decisão
			local currentState = NPCStateMachine.GetState(npc)
			local context = NPCStateMachine.GetContext(npc)
			local perception = NPCPerception.GetData(npc)
			local nextState = NPCDecision.DecideNextState(npc, perception, currentState, context)
			
			if nextState and nextState ~= currentState then
				NPCStateMachine.ChangeState(npc, nextState)
			end
			
			-- 3. State Machine Update
			NPCStateMachine.Update(npc, step)
		end
	end
	
	if dt >= UPDATE_INTERVAL then
		LastUpdateTime = currentTime
	end
end)

-- ======================================================================
-- SPAWN TESTE
-- ======================================================================

task.wait(2)
print("🤖 [NPCManager] Spawnando NPCs...")
local spawnPositions = GetSpawnPositions()
for i, position in ipairs(spawnPositions) do
	SpawnNPC(position)
end
