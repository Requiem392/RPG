--[[
	NPCPerception.module.luau
	
	Pilar 1: PERCEPÇÃO
	
	Responsabilidades:
	- Visão (Range + FOV + Raycast)
	- Audição (Detecção de som)
	- Memória (Retenção temporal)
	- Validação de alvos
	
	NÃO FAZ:
	- Tomar decisões
	- Atacar
	- Mover
	- Mudar estado
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local NPCPerception = {}

-- ======================================================================
-- CONFIGURAÇÃO
-- ======================================================================

local DEBUG_VISION = true  -- Ativa/desativa visualização do raycast

local VisionConfig = {
	Range = 50,              -- Alcance máximo de visão (studs)
	FieldOfView = 120,       -- Ângulo de visão (graus)
	UpdateInterval = 0.2     -- Atualiza a cada 0.2s
}

local HearingConfig = {
	Range = 30,              -- Alcance de audição (studs)
	NoiseThreshold = 16      -- WalkSpeed mínima para emitir som
}

local MemoryConfig = {
	RetentionTime = 5,       -- Tempo que lembra do alvo (segundos)
	SuspectDuration = 12     -- Tempo que mantém suspeita auditiva (segundos)
}

-- ======================================================================
-- DADOS DE PERCEPÇÃO (por NPC)
-- ======================================================================

local PerceptionData = {}

function NPCPerception.InitializeNPC(npc)
	if not npc or not npc:IsA("Model") then
		warn("[Perception] NPC inválido:", npc)
		return
	end
	
	PerceptionData[npc] = {
		-- Visão (confirmação real)
		HasVisual = false,
		LastSeenPosition = nil,
		LastSeenTime = 0,
		DistanceToTarget = math.huge,
		
		-- Audição (suspeita)
		HasSuspicion = false,
		SuspectPosition = nil,
		SuspectTime = 0,
		
		-- Alvo Atual
		CurrentTarget = nil
	}
	
	print("✅ [Perception] Inicializado para:", npc.Name)
end

-- ======================================================================
-- VALIDAÇÃO DE ALVO
-- ======================================================================

local function IsValidTarget(player)
	-- Player existe e tem Character?
	if not player or not player.Character then return false end
	
	-- Humanoid vivo?
	local humanoid = player.Character:FindFirstChild("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return false end
	
	-- TODO: Adicionar checagens de equipe/invisibilidade se necessário
	
	return true
end

-- ======================================================================
-- VISÃO (Vision)
-- ======================================================================

local function CheckVision(npc, target)
	local npcRoot = npc:FindFirstChild("HumanoidRootPart")
	local targetRoot = target.Character:FindFirstChild("HumanoidRootPart")
	
	if not npcRoot or not targetRoot then
		return false, math.huge
	end
	
	-- 1. Verificação de Alcance
	local distance = (npcRoot.Position - targetRoot.Position).Magnitude
	if distance > VisionConfig.Range then
		return false, distance
	end
	
	-- 2. Campo de Visão (FOV)
	local lookVector = npcRoot.CFrame.LookVector
	local directionToTarget = (targetRoot.Position - npcRoot.Position).Unit
	local dotProduct = lookVector:Dot(directionToTarget)
	local angle = math.deg(math.acos(dotProduct))
	
	if angle > (VisionConfig.FieldOfView / 2) then
		return false, distance
	end
	
	-- 3. Raycast de Obstrução
	local raycastParams = RaycastParams.new()
	raycastParams.FilterDescendantsInstances = {npc, target.Character}
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	
	local rayDirection = targetRoot.Position - npcRoot.Position
	local rayResult = workspace:Raycast(
		npcRoot.Position,
		rayDirection,
		raycastParams
	)
	
	-- DEBUG: Visualiza raycast
	if DEBUG_VISION then
		local rayColor = rayResult and Color3.fromRGB(255, 0, 0) or Color3.fromRGB(0, 255, 0)
		local rayPart = Instance.new("Part")
		rayPart.Anchored = true
		rayPart.CanCollide = false
		rayPart.Size = Vector3.new(0.1, 0.1, rayDirection.Magnitude)
		rayPart.CFrame = CFrame.new(npcRoot.Position, targetRoot.Position) * CFrame.new(0, 0, -rayDirection.Magnitude / 2)
		rayPart.Color = rayColor
		rayPart.Material = Enum.Material.Neon
		rayPart.Parent = workspace
		game:GetService("Debris"):AddItem(rayPart, 0.2)
	end
	
	-- Se raycast acertou algo, visão bloqueada
	if rayResult then
		return false, distance
	end
	
	-- Passou em todas as checagens
	return true, distance
end

-- ======================================================================
-- AUDIÇÃO (Hearing)
-- ======================================================================

local function CheckHearing(npc, target)
	local npcRoot = npc:FindFirstChild("HumanoidRootPart")
	local targetRoot = target.Character:FindFirstChild("HumanoidRootPart")
	local targetHumanoid = target.Character:FindFirstChild("Humanoid")
	
	if not npcRoot or not targetRoot or not targetHumanoid then
		return false, nil
	end
	
	-- 1. Distância (LIMITE RÍGIDO: 30 studs)
	local distance = (npcRoot.Position - targetRoot.Position).Magnitude
	if distance > HearingConfig.Range then
		return false, nil
	end
	
	-- 2. Player está se movendo rápido o suficiente?
	-- Precisamos checar a velocidade REAL (Velocity), não o WalkSpeed (Capacidade)
	local velocity = targetRoot.AssemblyLinearVelocity * Vector3.new(1, 0, 1) -- Ignora eixo Y (pulo/queda)
	if velocity.Magnitude < HearingConfig.NoiseThreshold then
		return false, nil
	end
	
	-- 3. Posição aproximada (±5 studs de offset aleatório)
	local offset = Vector3.new(
		math.random(-5, 5),
		0,
		math.random(-5, 5)
	)
	local approximatePosition = targetRoot.Position + offset
	
	return true, approximatePosition
end

-- ======================================================================
-- MEMÓRIA (Memory) - Só para Visão
-- ======================================================================

local function UpdateMemory(data, currentTime)
	-- Memória visual
	if data.LastSeenTime > 0 then
		local memoryAge = currentTime - data.LastSeenTime
		
		-- Ainda dentro do tempo de retenção?
		if memoryAge <= MemoryConfig.RetentionTime then
			-- Mantém LastSeenPosition válida
		else
			-- Esqueceu
			data.LastSeenPosition = nil
		end
	end
	
	-- Suspeita auditiva
	if data.SuspectTime > 0 then
		local suspectAge = currentTime - data.SuspectTime
		
		-- Ainda dentro do tempo de suspeita?
		if suspectAge <= MemoryConfig.SuspectDuration then
			data.HasSuspicion = true
		else
			-- Suspeita expirou
			data.HasSuspicion = false
			data.SuspectPosition = nil
		end
	else
		data.HasSuspicion = false
	end
end

-- ======================================================================
-- ATUALIZAÇÃO PRINCIPAL
-- ======================================================================

function NPCPerception.Update(npc)
	local data = PerceptionData[npc]
	if not data then
		warn("[Perception] NPC não inicializado:", npc.Name)
		return
	end
	
	local currentTime = tick()
	
	-- Encontra alvo mais próximo (por enquanto, primeiro player vivo)
	local closestPlayer = nil
	local closestDistance = math.huge
	
	for _, player in ipairs(Players:GetPlayers()) do
		if IsValidTarget(player) then
			local npcRoot = npc:FindFirstChild("HumanoidRootPart")
			local targetRoot = player.Character:FindFirstChild("HumanoidRootPart")
			
			if npcRoot and targetRoot then
				local dist = (npcRoot.Position - targetRoot.Position).Magnitude
				if dist < closestDistance then
					closestDistance = dist
					closestPlayer = player
				end
			end
		end
	end
	
	-- Se não tem alvo válido, limpa dados
	if not closestPlayer then
		data.CurrentTarget = nil
		data.HasVisual = false
		data.HasSuspicion = false
		UpdateMemory(data, currentTime)
		return
	end
	
	-- Atualiza alvo atual
	data.CurrentTarget = closestPlayer
	
	-- Atualiza Visão (confirmação real)
	local canSee, distance = CheckVision(npc, closestPlayer)
	data.HasVisual = canSee
	data.DistanceToTarget = distance
	
	if canSee then
		-- Visão atualiza LastSeen*
		data.LastSeenPosition = closestPlayer.Character.HumanoidRootPart.Position
		data.LastSeenTime = currentTime
	end
	
	-- Atualiza Audição (suspeita)
	local heardNoise, suspectPos = CheckHearing(npc, closestPlayer)
	
	if heardNoise then
		-- Audição atualiza Suspect*
		data.SuspectPosition = suspectPos
		data.SuspectTime = currentTime
		data.HasSuspicion = true
	end
	
	-- Atualiza Memória (visual e suspeita)
	UpdateMemory(data, currentTime)
end

-- ======================================================================
-- API PÚBLICA
-- ======================================================================

function NPCPerception.GetData(npc)
	return PerceptionData[npc]
end

function NPCPerception.Cleanup(npc)
	PerceptionData[npc] = nil
	print("🗑️ [Perception] Removido:", npc.Name)
end

return NPCPerception
