--[[
	NPCMovement.module.luau
	
	Responsabilidades:
	- Centralizar movimentação
	- Pathfinding (evitar paredes)
	- Steering (evitar outros NPCs)
	- Execução de movimento (Humanoid:Move)
]]

local PathfindingService = game:GetService("PathfindingService")
local BuildRS = game:GetService("RunService")
local Players = game:GetService("Players")

local NPCMovement = {}

-- ======================================================================
-- CONFIGURAÇÃO
-- ======================================================================

local PATH_PARAMS = {
	AgentRadius = 2,
	AgentHeight = 5,
	AgentCanJump = true,
	WaypointSpacing = 4,
}

local STEER_FORCE = 15 -- Força do desvio lateral
local AVOID_DISTANCE = 6 -- Distância para começar a desviar de NPCs

local MovementData = {}

-- ======================================================================
-- FUNÇÕES AUXILIARES
-- ======================================================================

local function GetPath(startPos, endPos)
	-- Validação básica
	if (startPos - endPos).Magnitude < 1 then
		return nil -- Muito perto, não precisa de path
	end

	local path = PathfindingService:CreatePath(PATH_PARAMS)
	local success, errorMessage = pcall(function()
		path:ComputeAsync(startPos, endPos)
	end)
	
	if success and path.Status == Enum.PathStatus.Success then
		return path:GetWaypoints()
	else
		-- Não warnar nil, mostra erro real se houver
		if not success then
			warn("⚠️ [NPCMovement] Erro ComputeAsync:", errorMessage)
		-- else
		-- 	warn("⚠️ [NPCMovement] PathStatus não Success:", path.Status)
		end
		return nil
	end
end

-- ======================================================================
-- CORE
-- ======================================================================

function NPCMovement.InitializeNPC(npc)
	MovementData[npc] = {
		Path = nil,
		CurrentWaypointIndex = 2, -- O 1 é sempre onde a gente já está
		TargetPosition = nil,
		IsMoving = false,
		Speed = 16,
		LastPathTime = 0,
		StuckTimer = 0,
		LastPosition = nil
	}
end

function NPCMovement.Cleanup(npc)
	MovementData[npc] = nil
end

function NPCMovement.MoveTo(npc, position, options)
	local data = MovementData[npc]
	if not data then return end
	
	options = options or {}
	data.Speed = options.speed or 16
	
	-- Se o destino é quase o mesmo e path é recente, ignora (Throttle de recalculo)
	if data.TargetPosition and (data.TargetPosition - position).Magnitude < 3 and (tick() - data.LastPathTime < 1.0) then
		return 
	end
	
	data.TargetPosition = position
	data.IsMoving = true
	
	local npcRoot = npc:FindFirstChild("HumanoidRootPart")
	if not npcRoot then return end
	
	-- Calcula Path
	local waypoints = GetPath(npcRoot.Position, position)
	if waypoints and #waypoints > 1 then
		data.Path = waypoints
		data.CurrentWaypointIndex = 2 -- Pula o primeiro (início)
		data.LastPathTime = tick()
	else
		-- Fallback: anda direto
		data.Path = nil 
	end
end

function NPCMovement.Stop(npc)
	local data = MovementData[npc]
	if not data then return end
	
	data.IsMoving = false
	data.Path = nil
	data.TargetPosition = nil
	-- Não limpa FaceDirection aqui para poder olhar parado se quiser
	-- mas se chamar Stop, geralmente quer parar tudo, então vamos limpar se não tiver Face explícito
	-- Por enquanto, limpa tudo.
	data.FaceDirection = nil
	
	local humanoid = npc:FindFirstChild("Humanoid")
	if humanoid then
		humanoid:Move(Vector3.new(0,0,0))
	end
end

function NPCMovement.Face(npc, position)
	local data = MovementData[npc]
	if not data then return end
	
	-- Calcula direção para a posição
	local root = npc:FindFirstChild("HumanoidRootPart")
	if root then
		local dir = (position - root.Position)
		data.FaceDirection = (dir.Magnitude > 0.1) and dir.Unit or nil
	end
end

function NPCMovement.FaceDirection(npc, direction)
	local data = MovementData[npc]
	if not data then return end
	data.FaceDirection = direction.Unit
end

-- ======================================================================
-- UPDATE LOOP
-- ======================================================================

function NPCMovement.Update(npc, dt)
	local data = MovementData[npc]
	if not data then return end
	
	local humanoid = npc:FindFirstChild("Humanoid")
	local root = npc:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root then return end
	
	-- ROTAÇÃO EXPLÍCITA (Prioridade sobre movimento se parado, ou junto?)
	-- Se tiver FaceDirection e NÃO estiver andando rápido (ou se quiser override)
	if data.FaceDirection then
		local currentLook = root.CFrame.LookVector
		local newLook = currentLook:Lerp(data.FaceDirection, 0.15) -- Suave
		-- CFrame.lookAt requer Eye e Target. 
		-- Criamos um CFrame na posição atual olhando para (posição + newLook)
		root.CFrame = CFrame.new(root.Position, root.Position + newLook)
	end
	
	-- Se não está movendo, acabou
	if not data.IsMoving or not data.TargetPosition then return end
	
	humanoid.WalkSpeed = data.Speed
	
	-- 1. Determina próximo ponto
	local nextPoint = data.TargetPosition
	
	if data.Path and data.CurrentWaypointIndex <= #data.Path then
		local waypoint = data.Path[data.CurrentWaypointIndex]
		nextPoint = waypoint.Position
		
		-- Pula pro próximo waypoint se chegou perto (distância horizontal)
		local dist = (Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(nextPoint.X, 0, nextPoint.Z)).Magnitude
		if dist < 4 then
			data.CurrentWaypointIndex = data.CurrentWaypointIndex + 1
			if waypoint.Action == Enum.PathWaypointAction.Jump then
				humanoid.Jump = true
			end
		end
	end
	
	-- 2. Direção Básica
	local diff = (nextPoint - root.Position)
	local direction = (diff.Magnitude > 0.1) and diff.Unit or root.CFrame.LookVector
	
	-- 3. STEERING MELHORADO (3 Raios + Memória de Desvio)
	local avoidVector = Vector3.new(0,0,0)
	local rayParams = RaycastParams.new()
	rayParams.FilterDescendantsInstances = {npc}
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	
	-- Verifica se ainda estamos usando uma decisão anterior
	local currentAvoidSide = data.AvoidSide
	if data.AvoidUntil and tick() > data.AvoidUntil then
		data.AvoidSide = nil -- Expirou, pode escolher de novo
		currentAvoidSide = nil
	end
	
	-- Se já tem um lado decidido, mantém (blind steering por um tempo curto)
	-- MAS, verifica se o caminho escolhido ainda está válido pra não bater em parede
	-- ... Otimização simples: se tem lado, tenta usar ele.
	
	if currentAvoidSide then
		local sideDir = (currentAvoidSide == "Right") and root.CFrame.RightVector or -root.CFrame.RightVector
		avoidVector = sideDir * STEER_FORCE
	else
		-- Nova Decisão
		local rightVec = root.CFrame.RightVector
		local lookVec = root.CFrame.LookVector
		
		-- Raios: Centro, Esquerda (-30 graus), Direita (+30 graus)
		local rayFront = workspace:Raycast(root.Position, lookVec * AVOID_DISTANCE, rayParams)
		local rayLeft  = workspace:Raycast(root.Position, (lookVec - rightVec).Unit * AVOID_DISTANCE, rayParams)
		local rayRight = workspace:Raycast(root.Position, (lookVec + rightVec).Unit * AVOID_DISTANCE, rayParams)
		
		local blockedFront = rayFront and rayFront.Instance and rayFront.Instance.Parent:FindFirstChild("Humanoid")
		local blockedLeft  = rayLeft  and rayLeft.Instance  and rayLeft.Instance.Parent:FindFirstChild("Humanoid")
		local blockedRight = rayRight and rayRight.Instance and rayRight.Instance.Parent:FindFirstChild("Humanoid")
		
		if blockedFront then
			-- Precisa desviar
			local chosenSide = nil
			
			if not blockedRight then
				chosenSide = "Right"
			elseif not blockedLeft then
				chosenSide = "Left"
			else
				-- Bloqueado total: Random
				chosenSide = (math.random() > 0.5) and "Right" or "Left"
			end
			
			-- Salva decisão na memória (0.6s a 1.0s)
			data.AvoidSide = chosenSide
			data.AvoidUntil = tick() + math.random(6, 10) / 10.0
			
			local sideDir = (chosenSide == "Right") and rightVec or -rightVec
			avoidVector = sideDir * STEER_FORCE
			
		elseif blockedLeft then
			-- Empurra leve pra direita (sem travar memória, só ajuste fino)
			avoidVector = rightVec * (STEER_FORCE * 0.5)
		elseif blockedRight then
			-- Empurra leve pra esquerda
			avoidVector = -rightVec * (STEER_FORCE * 0.5)
		end
	end
	
	-- Aplica a força de desvio
	local finalDirection = (direction * 10 + avoidVector).Unit
	
	-- 4. Executa
	humanoid:Move(finalDirection)
	
	-- 5. Anti-Impasse (Se colidir e não andar, repath)
	if data.LastPosition and (root.Position - data.LastPosition).Magnitude < 0.2 then
		data.StuckTimer = data.StuckTimer + dt
		if data.StuckTimer > 2.0 then
			-- Travou mesmo, força repath total
			data.Path = nil 
			data.LastPathTime = 0 
			humanoid.Jump = true 
			data.StuckTimer = 0
			data.AvoidSide = nil -- Reseta memória de desvio
		end
	else
		data.StuckTimer = 0
	end
	data.LastPosition = root.Position
end


return NPCMovement
