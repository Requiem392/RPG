--[[
	NPCManager.server.luau
	
	Gerencia NPCs:
	- Spawn de NPCs
	- Loop de atualização de Percepção
	- Cleanup quando NPC morre
]]

local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")

-- Módulos
local NPCPerception = require(script.Parent.NPCPerception)
local NPCStateMachine = require(script.Parent.NPCStateMachine)
local NPCDecision = require(script.Parent.NPCDecision)

-- ======================================================================
-- CONFIGURAÇÃO
-- ======================================================================

local UPDATE_INTERVAL = 0.2  -- Atualiza percepção a cada 0.2s

-- Função para obter posições de spawn
local function GetSpawnPositions()
	local positions = {}
	
	-- Busca SpawnLocation no workspace
	local spawnLocation = workspace:FindFirstChildOfClass("SpawnLocation")
	
	if spawnLocation then
		local spawnPos = spawnLocation.Position
		-- Spawna 1 NPC perto do SpawnLocation
		table.insert(positions, spawnPos + Vector3.new(0, 0, 8))
	else
		-- Fallback: posições padrão
		warn("⚠️ [NPCManager] SpawnLocation não encontrado, usando posições padrão")
		table.insert(positions, Vector3.new(0, 5, 20))
		table.insert(positions, Vector3.new(10, 5, 20))
		table.insert(positions, Vector3.new(-10, 5, 20))
	end
	
	return positions
end

-- ======================================================================
-- GERENCIAMENTO DE NPCs
-- ======================================================================

local ActiveNPCs = {}
local LastUpdateTime = 0

-- Spawna um NPC
local function SpawnNPC(position)
	-- Busca modelo no ServerStorage
	local npcTemplate = ServerStorage:FindFirstChild("NPC")
	if not npcTemplate then
		warn("❌ [NPCManager] Modelo 'NPC' não encontrado no ServerStorage!")
		return nil
	end
	
	-- Clona NPC
	local npc = npcTemplate:Clone()
	npc.Name = "NPC_" .. tick()
	
	-- Posiciona
	if npc.PrimaryPart then
		npc:SetPrimaryPartCFrame(CFrame.new(position))
	elseif npc:FindFirstChild("HumanoidRootPart") then
		npc.HumanoidRootPart.CFrame = CFrame.new(position)
	end
	
	npc.Parent = workspace
	
	-- Inicializa percepção
	NPCPerception.InitializeNPC(npc)
	-- Inicializa State Machine (Inicia em Idle)
	NPCStateMachine.InitializeNPC(npc)
	
	-- Adiciona à lista de NPCs ativos
	table.insert(ActiveNPCs, npc)
	
	-- Listener de morte
	local humanoid = npc:FindFirstChild("Humanoid")
	if humanoid then
		humanoid.Died:Connect(function()
			RemoveNPC(npc)
		end)
	end
	
	print("✅ [NPCManager] NPC spawnado:", npc.Name, "em", position)
	return npc
end

-- Remove NPC
function RemoveNPC(npc)
	-- Remove da lista
	for i, activeNPC in ipairs(ActiveNPCs) do
		if activeNPC == npc then
			table.remove(ActiveNPCs, i)
			break
		end
	end
	
	-- Cleanup de percepção
	NPCPerception.Cleanup(npc)
	NPCStateMachine.Cleanup(npc)
	
	-- Remove do workspace após delay
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

RunService.Heartbeat:Connect(function()
	local currentTime = tick()
	
	-- Throttle: percepção a cada UPDATE_INTERVAL
	local dt = currentTime - LastUpdateTime
	
	-- Atualiza todos os NPCs ativos
	for _, npc in ipairs(ActiveNPCs) do
		if npc and npc.Parent then
			-- 1. Percepção (Throttle)
			if dt >= UPDATE_INTERVAL then
				NPCPerception.Update(npc)
				
				-- 2. Decision Making (Pilar 3)
				local perceptionData = NPCPerception.GetData(npc)
				local currentState = NPCStateMachine.GetState(npc)
				local stateData = NPCStateMachine.GetStateData(npc)
				
				if perceptionData and stateData then
					local nextState = NPCDecision.GetNextState(npc, perceptionData, currentState, stateData.StateTime)
					
					if nextState and nextState ~= currentState then
						print(string.format("🔄 [Decision] %s: %s -> %s", npc.Name, currentState, nextState))
						NPCStateMachine.ChangeState(npc, nextState)
					end
				end
				
				-- DEBUG: Mostra dados de percepção
				local data = NPCPerception.GetData(npc)
				if data and data.CurrentTarget then
					local status = ""
					local currentTime = tick()
					local hasMemory = data.LastSeenPosition and (currentTime - data.LastSeenTime <= 5)
					
					if data.HasVisual then
						status = "👁️ VÊ"
					elseif data.HasSuspicion then
						status = "🎧 OUVIU"
					elseif hasMemory then
						status = "🧠 LEMBRA"
					else
						status = "❓ PERDEU"
					end
					
					local state = NPCStateMachine.GetState(npc)
					print(string.format("[%s] %s (%s) | Dist: %.1f | Target: %s", 
						npc.Name, 
						status,
						state,
						data.DistanceToTarget,
						data.CurrentTarget.Name
					))
				end
			end
			
			-- 2. State Machine (Todo frame)
			NPCStateMachine.Update(npc, currentTime - (LastUpdateTime - dt)) -- dt real aproximado
		end
	end
	
	if dt >= UPDATE_INTERVAL then
		LastUpdateTime = currentTime
	end
end)

-- ======================================================================
-- COMANDOS DE TESTE
-- ======================================================================

-- Spawna NPCs de teste ao iniciar
task.wait(2)  -- Espera o jogo carregar

print("🤖 [NPCManager] Spawnando NPCs de teste...")
local spawnPositions = GetSpawnPositions()
for i, position in ipairs(spawnPositions) do
	SpawnNPC(position)
end

print("✅ [NPCManager] Iniciado")
