local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Player = Players.LocalPlayer
local Character = Player.Character or Player.CharacterAdded:Wait()
local Humanoid = Character:WaitForChild("Humanoid")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local SprintEvent = Remotes:WaitForChild("SprintAction")

-- ============================================================================
-- FUNÇÕES
-- ============================================================================

local SPRINT_ANIM_ID = "rbxassetid://128596693500077"
local CurrentSprintTrack = nil

local function UpdateState()
	if not Character then return end
	local humanoid = Character:FindFirstChild("Humanoid")
	if not humanoid then return end
	
	-- Leitura Autoritativa
	local isSprinting = Character:GetAttribute("IsSprinting")
	local currentSpeed = Character:GetAttribute("CurrentSpeed") or 10
	
	-- Aplica Velocidade Interpolada pelo Server
	humanoid.WalkSpeed = currentSpeed
	
	-- Aplica Animação
	if isSprinting then
		if CurrentSprintTrack and not CurrentSprintTrack.IsPlaying then
			-- Garante que não está tocando duplicado
			CurrentSprintTrack:Play()
		end
	else
		if CurrentSprintTrack and CurrentSprintTrack.IsPlaying then
			CurrentSprintTrack:Stop()
		end
	end
end

local function OnAttributeChanged(attribute)
	if attribute == "IsSprinting" or attribute == "CurrentSpeed" then
		UpdateState()
	end
end

local function SetupCharacter(char)
	Character = char
	Humanoid = char:WaitForChild("Humanoid")
	local animator = Humanoid:WaitForChild("Animator")
	
	-- Prepara Animação
	if CurrentSprintTrack then
		CurrentSprintTrack:Stop()
		CurrentSprintTrack = nil
	end
	
	local anim = Instance.new("Animation")
	anim.AnimationId = SPRINT_ANIM_ID
	CurrentSprintTrack = animator:LoadAnimation(anim)
	CurrentSprintTrack.Priority = Enum.AnimationPriority.Movement
	
	-- Escuta mudanças de atributo
	char.AttributeChanged:Connect(OnAttributeChanged)
	
	-- Garante estado inicial
	UpdateState()
end

-- ============================================================================
-- INPUT
-- ============================================================================

local function HandleSprintInput(actionName, inputState, inputObject)
	if inputState == Enum.UserInputState.Begin then
		SprintEvent:FireServer("Start")
	elseif inputState == Enum.UserInputState.End then
		SprintEvent:FireServer("Stop")
	end
	return Enum.ContextActionResult.Pass
end

-- ============================================================================
-- INICIALIZAÇÃO
-- ============================================================================

Player.CharacterAdded:Connect(SetupCharacter)
if Character then
	SetupCharacter(Character)
end

ContextActionService:BindAction("Sprint", HandleSprintInput, false, Enum.KeyCode.LeftShift)

print("🏃 SprintController iniciado (Reactive Mode)")
