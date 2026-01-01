local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

print(">>> SERVER: EquipmentHandler (Instantâneo - Teste de Solda) Iniciado")

local DataFolder = ReplicatedStorage:WaitForChild("Data")
local ItemData = require(DataFolder:WaitForChild("ItemData"))

local ServerEvents = ServerStorage:FindFirstChild("ServerEvents") or Instance.new("Folder", ServerStorage)
local CombatEvent = ServerEvents:FindFirstChild("CombatSystem") or Instance.new("BindableEvent", ServerEvents)

-- Tabelas de Controle Visual
local ActiveModels = {} -- [Player] = Model
local ActiveNames = {}  -- [Player] = "NomeDoItem"
local ActiveTracks = {} -- [Player] = {Idle}

-- ============================================================================
-- FUNÇÕES AUXILIARES
-- ============================================================================
local function CreateAnim(id)
	local anim = Instance.new("Animation")
	anim.AnimationId = id
	return anim
end

local function GetBodyPart(character, partName)
	if partName == "RightHand" then
		return character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
	elseif partName == "Torso" then
		return character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")
	end
	return character:FindFirstChild(partName)
end

-- Solda Inteligente
local function WeldItem(character, itemModel, targetPartName, offsetMode)
	local bodyPart = GetBodyPart(character, targetPartName)
	local handle = itemModel:FindFirstChild("Handle") or itemModel.PrimaryPart

	if not bodyPart or not handle then return end

	-- Limpa solda antiga
	local oldWeld = handle:FindFirstChild("ItemWeld")
	if oldWeld then oldWeld:Destroy() end

	local weld = Instance.new("Motor6D")
	weld.Name = "ItemWeld"
	weld.Part0 = bodyPart
	weld.Part1 = handle

	local targetCFrame = CFrame.new()
	local valueObj = nil

	-- Busca o valor de ajuste (CFrameValue) dentro do modelo
	if offsetMode == "Sheath" then
		valueObj = itemModel:FindFirstChild("Back") or handle:FindFirstChild("Back")
	elseif offsetMode == "Hand" then
		valueObj = itemModel:FindFirstChild("Hand") or handle:FindFirstChild("Hand")
	end

	if valueObj and valueObj:IsA("CFrameValue") then
		targetCFrame = valueObj.Value
	end

	weld.C0 = CFrame.new()
	weld.C1 = targetCFrame
	weld.Parent = handle
end

-- ============================================================================
-- AÇÕES DO SISTEMA (Simplificado: Só Equipar e Desequipar)
-- ============================================================================

local function HandleEquip(player, itemName)
	local character = player.Character
	if not character then return end
	local animator = character:FindFirstChild("Humanoid") and character.Humanoid:FindFirstChild("Animator")

	local data = ItemData.Get(itemName)
	if not data then return end 

	if not data.Model then return end

	-- 1. LIMPEZA: Remove qualquer modelo anterior (inclusive se tiver nas costas)
	if ActiveModels[player] then 
		ActiveModels[player]:Destroy() 
	end

	-- 2. CRIAÇÃO: Clona o modelo novo
	local itemVisual = data.Model:Clone()
	itemVisual.Name = "EquippedItemVisual"
	itemVisual.Parent = character
	
	ActiveModels[player] = itemVisual
	ActiveNames[player] = itemName

	-- 3. SOLDA: Cola DIRETO na mão (Sem bainha, sem transição)
	WeldItem(character, itemVisual, "RightHand", "Hand")

	-- 4. ANIMAÇÃO: Toca apenas o IDLE (Postura de segurar)
	if animator and data.Animations and data.Animations.Idle then
		local idle = animator:LoadAnimation(CreateAnim(data.Animations.Idle))
		idle.Looped = true
		idle:Play()
		ActiveTracks[player] = {Idle = idle}
	end
end

local function HandleUnequip(player, itemName)
	-- 1. ANIMAÇÃO: Para o Idle
	if ActiveTracks[player] and ActiveTracks[player].Idle then
		ActiveTracks[player].Idle:Stop()
	end
	ActiveTracks[player] = nil

	-- 2. MODELO: Destroi o modelo (Não guarda nas costas, apenas some)
	local model = ActiveModels[player]
	if model then 
		model:Destroy() 
	end
	
	ActiveModels[player] = nil
	ActiveNames[player] = nil
end

local function HandleUseItem(player, itemName)
	local data = ItemData.Get(itemName)
	if not data then return end

	if data.Type == "Consumable" and data.HealAmount then
		print("EFEITO: " .. player.Name .. " curou " .. data.HealAmount .. " de vida!")
	end
end

-- ============================================================================
-- CONEXÕES
-- ============================================================================

CombatEvent.Event:Connect(function(action, player, itemName)
	if action == "Equip" then HandleEquip(player, itemName)
	elseif action == "Unequip" then HandleUnequip(player, itemName)
	elseif action == "UseItem" then HandleUseItem(player, itemName) end
end)

Players.PlayerRemoving:Connect(function(player)
	if ActiveModels[player] then ActiveModels[player]:Destroy() end
	ActiveModels[player] = nil
	ActiveNames[player] = nil
	ActiveTracks[player] = nil
end)