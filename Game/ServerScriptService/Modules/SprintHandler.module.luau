local SprintHandler = {}
SprintHandler.__index = SprintHandler
SprintHandler.Registry = {}

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

-- Configurações
local SPRINT_COST_PER_SEC = 5
local ACCEL = 8   -- Velocidade de interpolação para subir
local DECEL = 20  -- Velocidade de interpolação para descer

-- Referências
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local SprintEvent = Remotes:FindFirstChild("SprintAction")
if not SprintEvent then
	SprintEvent = Instance.new("RemoteEvent")
	SprintEvent.Name = "SprintAction"
	SprintEvent.Parent = Remotes
end

local ServerEvents = ServerStorage:WaitForChild("ServerEvents")
local ResourceBindable = ServerEvents:WaitForChild("ResourceBindable")

-- ============================================================================
-- CONSTRUTOR
-- ============================================================================

function SprintHandler.new(entity)
	local self = setmetatable({}, SprintHandler)
	
	-- Suporta Player ou Model (NPC)
	if entity:IsA("Player") then
		self.Player = entity
		-- Se for Player, precisamos esperar o Character
		if entity.Character then
			self:SetupCharacter(entity.Character)
		end
		self.CharacterAddedConn = entity.CharacterAdded:Connect(function(char)
			self:SetupCharacter(char)
		end)
		SprintHandler.Registry[entity] = self
	elseif entity:IsA("Model") then
		-- NPC (Direto)
		self:SetupCharacter(entity)
		-- Para NPC, a registry pode ser pelo Model
		SprintHandler.Registry[entity] = self
	end
	
	print("🏃 SprintHandler criado para:", entity.Name)
	return self
end

function SprintHandler:Destroy()
	if self.CharacterAddedConn then
		self.CharacterAddedConn:Disconnect()
	end
	if self.Player then
		SprintHandler.Registry[self.Player] = nil
	elseif self.Character then
		SprintHandler.Registry[self.Character] = nil
	end
	self.Player = nil
	self.Character = nil
end

-- ============================================================================
-- LÓGICA
-- ============================================================================

function SprintHandler:SetupCharacter(character)
	self.Character = character
	self.Humanoid = character:FindFirstChild("Humanoid")
	
	character:SetAttribute("IsSprinting", false)
	character:SetAttribute("WalkSpeed_Base", 10)
	character:SetAttribute("WalkSpeed_Sprint", 16)
	character:SetAttribute("CurrentSpeed", 10) -- Começa na base
end

function SprintHandler:CanSprint()
	if not self.Character then return false end
	
	-- 1. Verifica Estados Bloqueantes
	if self.Character:GetAttribute("IsAttacking") then return false end
	if self.Character:GetAttribute("IsBlocking") then return false end
	-- if self.Character:GetAttribute("IsStunned") then return false end 
	
	-- 2. Verifica Movimento (NOVO)
	-- Se não estiver se movendo, não pode INICIAR sprint (e se parar, corta)
	if self.Humanoid and self.Humanoid.MoveDirection.Magnitude <= 0.1 then
		return false
	end
	
	-- 3. Verifica Stamina Inicial (Player Only)
	if self.Player then
		local canAfford = ResourceBindable:Invoke("CanAffordStamina", self.Player, SPRINT_COST_PER_SEC * 0.1)
		if not canAfford then return false end
	end
	
	return true
end

function SprintHandler:SetSprint(wantToSprint)
	if not self.Character then return end
	
	local isSprinting = self.Character:GetAttribute("IsSprinting")
	
	if wantToSprint then
		if not isSprinting and self:CanSprint() then
			self.Character:SetAttribute("IsSprinting", true)
		end
	else
		if isSprinting then
			self.Character:SetAttribute("IsSprinting", false)
		end
	end
end

function SprintHandler:Update(dt)
	if not self.Character or not self.Humanoid then return end
	
	-- --
	-- 1. Gerencia Estado e Stamina
	-- --
	local isSprinting = self.Character:GetAttribute("IsSprinting")
	local isMoving = self.Humanoid.MoveDirection.Magnitude > 0.1
	
	if isSprinting then
		-- Verifica Validade Contínua (Movimento e Bloqueios)
		if not self:CanSprint() then
			self.Character:SetAttribute("IsSprinting", false)
			isSprinting = false -- Atualiza local
		else
			-- Consome Stamina (Só se for Player e estiver se movendo de fato)
			if self.Player and isMoving then
				local cost = SPRINT_COST_PER_SEC * dt
				local success = ResourceBindable:Invoke("UseStamina", self.Player, cost)
				
				if not success then
					self.Character:SetAttribute("IsSprinting", false)
					isSprinting = false
				end
			end
		end
	end
	
	-- --
	-- 2. Interpola Velocidade (Physics Refinement)
	-- --
	local currentSpeed = self.Character:GetAttribute("CurrentSpeed") or 10
	local baseSpeed = self.Character:GetAttribute("WalkSpeed_Base") or 10
	local sprintSpeed = self.Character:GetAttribute("WalkSpeed_Sprint") or 16
	
	local targetSpeed = baseSpeed
	
	if isSprinting and isMoving then
		targetSpeed = sprintSpeed
	end
	
	-- Escolhe aceleração baseada na direção (subindo ou descendo)
	local interpSpeed = (targetSpeed > currentSpeed) and ACCEL or DECEL
	
	-- Lerp simples: New = Old + (Target - Old) * Alpha * dt
	-- Ou move_toward logic linear para ter controle absoluto de ACCEL
	if currentSpeed < targetSpeed then
		currentSpeed = math.min(targetSpeed, currentSpeed + (interpSpeed * dt))
	elseif currentSpeed > targetSpeed then
		currentSpeed = math.max(targetSpeed, currentSpeed - (interpSpeed * dt))
	end
	
	-- Aplica
	if math.abs(currentSpeed - (self.Character:GetAttribute("CurrentSpeed") or 0)) > 0.01 then
		self.Character:SetAttribute("CurrentSpeed", currentSpeed)
	end
end

-- ============================================================================
-- EVENTOS GLOBAIS
-- ============================================================================

SprintEvent.OnServerEvent:Connect(function(player, action)
	local handler = SprintHandler.Registry[player]
	if not handler then return end
	
	if action == "Start" then
		handler:SetSprint(true)
	elseif action == "Stop" then
		handler:SetSprint(false)
	end
end)

RunService.Heartbeat:Connect(function(dt)
	for _, handler in pairs(SprintHandler.Registry) do
		handler:Update(dt)
	end
end)

function SprintHandler.Init()
	print("🏃 SprintHandler Init")
end

return SprintHandler
