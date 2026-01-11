--!strict
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

-- Configuração
local BASE_FOV = 70.0
local SPRINT_FOV = 76.0 -- máximo 78
local FOV_LERP_SPEED = 8.0

local SHAKE_SPEED = 12.0
local SHAKE_INTENSITY = 0.1 -- Intensidade muito baixa para ser sutil

local SMOOTH_SPEED = 6.0 -- Velocidade de interpolação
local TELEPORT_THRESHOLD = 15.0 -- Se afastar mais que isso, teleporta
local MAX_LAG_DISTANCE = 0.3 -- Distância máxima que o "fantasma" pode ficar do personagem

local shakeTime = 0.0
local ghostTarget: Part? = nil

-- Lean / Tilt Vars
local MAX_TILT = math.rad(8)
local TILT_SPEED = 10.0
local RETURN_SPEED = 4.0
local RETURN_DELAY = 0.15

local currentTilt = 0.0
local lastInputTime = 0.0

local function getCharacter(): Model?
	return player.Character
end

local function getHumanoid(character: Model): Humanoid?
	return character:FindFirstChildOfClass("Humanoid")
end

-- Cria ou recupera a 'peça fantasma' que a câmera vai seguir de verdade
local function getGhostTarget(): Part
	if ghostTarget and ghostTarget:IsDescendantOf(Workspace) then
		return ghostTarget
	end

	local part = Instance.new("Part")
	part.Name = "CameraGhostTarget"
	part.Transparency = 1
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Anchored = true
	part.Size = Vector3.new(1, 1, 1)
	part.Parent = Workspace
	ghostTarget = part

	return part
end

-- Calcula o ângulo de inclinação lateral
local function calculateLean(deltaTime: number, root: BasePart, humanoid: Humanoid): number
	local moveDir = humanoid.MoveDirection
	
	-- Se houver movimento significativo
	if moveDir.Magnitude > 0.1 then
		lastInputTime = os.clock()
		
		local right = root.CFrame.RightVector
		local side = right:Dot(moveDir)
		
		-- Alvo: inclina oposto à direção do movimento (strafe left -> tilt left (Z positivo? depende da convenção, testar -side))
		-- Convenção padrão: Tilt Esquerda = +Roll? Não, CFrame.Angles(0,0,z).
		-- Se eu vou para direita (RightVector), side é +1. Tilt deve ser para direita (-Z).
		-- Se eu vou para esquerda, side é -1. Tilt deve ser para esquerda (+Z).
		-- Então target = -side * MAX_TILT
		local targetTilt = -math.clamp(side, -1, 1) * MAX_TILT
		
		-- Se ainda estamos na janela de "movimento ativo" (sem delay expirado) ou temos input ativo
		-- Mas aqui o input é ativo agora. 
		local speed = (math.abs(targetTilt) > math.abs(currentTilt)) and TILT_SPEED or RETURN_SPEED
		currentTilt = currentTilt + (targetTilt - currentTilt) * math.clamp(deltaTime * speed, 0, 1)
		
	else
		-- Parado. Verifica delay.
		if (os.clock() - lastInputTime) > RETURN_DELAY then
			local targetTilt = 0
			local speed = RETURN_SPEED
			currentTilt = currentTilt + (targetTilt - currentTilt) * math.clamp(deltaTime * speed, 0, 1)
		else
			-- Mantém o tilt atual enquanto espera o delay (drift suave ou hold?)
			-- O usuário pediu delay de retorno. Então mantemos o valor atual ou alvo anterior?
			-- Mantemos o currentTilt onde está se for "hold".
			-- Mas se moveDir é 0, o target "lógico" parou. 
			-- Vamos manter o tilt até o delay passar, depois zerar.
		end
	end
	
	return currentTilt
end

-- Aplica rotação do personagem (ShiftLock + Lean)
local function applyCharacterRotation(character: Model, tiltAngle: number)
	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart
	if not hrp then return end

	-- Shift Lock Logic
	if UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter then
		local cameraLook = camera.CFrame.LookVector
		local lookDir = Vector3.new(cameraLook.X, 0, cameraLook.Z).Unit
		
		-- Recalcula a base limpa baseada no olhar
		local targetRotationBase = CFrame.lookAt(hrp.Position, hrp.Position + lookDir)
		
		-- Combina com o Tilt
		local finalCFrame = targetRotationBase * CFrame.Angles(0, 0, tiltAngle)
		
		-- Lerp suave para rotação Y, mas o Tilt queremos responsivo?
		-- Se lerparmos tudo, o tilt também suaviza (já suavizado no calculateLean).
		-- Porém, para Y queremos lerp 0.5 (como era antes).
		-- Vamos lerpar a BASE e aplicar o Tilt por cima.
		local currentBase = CFrame.lookAt(hrp.Position, hrp.Position + hrp.CFrame.LookVector)
		local lerpedBase = currentBase:Lerp(targetRotationBase, 0.5)
		
		hrp.CFrame = lerpedBase * CFrame.Angles(0, 0, tiltAngle)
		
	else
		-- Normal Logic (Não Shift Lock)
		-- Apenas aplica o Lean visualmente sobre a rotação atual da física
		local rx, ry, rz = hrp.CFrame:ToOrientation()
		
		-- Reconstrói preservando posição e Y-rotation, aplicando novo Roll
		hrp.CFrame = CFrame.new(hrp.Position) * CFrame.Angles(0, ry, tiltAngle)
	end
end

-- renderStep de Prioridade ALTA: Atualiza a posição do GhostTarget
local function onPreRender(deltaTime: number)
	local character = getCharacter()
	if not character then return end

	local hrp = character:FindFirstChild("HumanoidRootPart") :: BasePart
	if not hrp then return end

	local target = getGhostTarget()

	-- Posição alvo: HRP + Offset vertical
	local targetPosition = hrp.Position + Vector3.new(0, 1.5, 0)
	local currentPosition = target.Position

	local dist = (targetPosition - currentPosition).Magnitude

	if dist > TELEPORT_THRESHOLD then
		target.Position = targetPosition
	else
		-- Interpolação suave
		local alpha = math.clamp(deltaTime * SMOOTH_SPEED, 0, 1)
		local newPos = currentPosition:Lerp(targetPosition, alpha)

		-- "Leash" logic: Impede que o alvo fique muito longe do jogador
		local newDist = (targetPosition - newPos).Magnitude
		if newDist > MAX_LAG_DISTANCE then
			-- Puxa o 'newPos' para mais perto, respeitando o limite
			local dir = (newPos - targetPosition).Unit
			newPos = targetPosition + (dir * MAX_LAG_DISTANCE)
		end

		target.Position = newPos
	end

	if camera.CameraSubject ~= target then
		camera.CameraSubject = target
	end
end

-- renderStep de Prioridade BAIXA: Efeitos visuais e Shift Lock
local function onPostRender(deltaTime: number)
	if not camera then
		camera = Workspace.CurrentCamera
		return
	end

	local character = getCharacter()
	if not character then return end

	local humanoid = getHumanoid(character)
	if not humanoid then return end

	local root = character:WaitForChild("HumanoidRootPart")
	local tilt = calculateLean(deltaTime, root, humanoid)
	
	applyCharacterRotation(character, tilt)

	local isSprinting = character:GetAttribute("IsSprinting") == true

	-- FOV
	local targetFov = if isSprinting then SPRINT_FOV else BASE_FOV
	local alpha = math.min(deltaTime * FOV_LERP_SPEED, 1.0)
	camera.FieldOfView = camera.FieldOfView + (targetFov - camera.FieldOfView) * alpha

	-- Shake
	if isSprinting and humanoid.MoveDirection.Magnitude > 0.1 then
		shakeTime += deltaTime
		local bobY = math.sin(shakeTime * SHAKE_SPEED) * SHAKE_INTENSITY
		camera.CFrame = camera.CFrame * CFrame.new(0, bobY, 0)
	end
end

if camera then
	camera.FieldOfView = BASE_FOV
end

RunService:BindToRenderStep("SmoothCameraCore", Enum.RenderPriority.Camera.Value - 1, onPreRender)
RunService:BindToRenderStep("SprintVisualFeedback", Enum.RenderPriority.Camera.Value + 1, onPostRender)

local function onCharacterAdded(newChar: Model)
	camera = Workspace.CurrentCamera
	if camera then
		camera.FieldOfView = BASE_FOV
	end
	shakeTime = 0.0

	local hrp = newChar:WaitForChild("HumanoidRootPart", 5) :: BasePart
	if hrp then
		local target = getGhostTarget()
		target.Position = hrp.Position + Vector3.new(0, 1.5, 0)
	end
end

if player.Character then
	onCharacterAdded(player.Character)
end

player.CharacterAdded:Connect(onCharacterAdded)
