local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

-- [[ MÓDULOS E DADOS ]] --
local DataFolder = ReplicatedStorage:WaitForChild("Data")
local ItemData = require(DataFolder:WaitForChild("ItemData"))

local ServerEvents = ServerStorage:WaitForChild("ServerEvents")
local CombatEvent = ServerEvents:WaitForChild("CombatSystem")

-- [[ ESTADO DO SERVIDOR ]] --
local ActiveWeapons = {}   -- Armazena o modelo da arma atual de cada jogador

-- ============================================================================
-- 1. FUNÇÕES UTILITÁRIAS
-- ============================================================================

-- Destrói qualquer Motor existente e cria um novo "limpo" (Reset Absoluto)
local function ForceNewMotor(weaponModel, targetPart, cframeValue)
	local handle = weaponModel:FindFirstChild("Handle")
	if not handle then return nil end

	-- Limpeza total
	local oldMotor = handle:FindFirstChild("MainMotor")
	if oldMotor then oldMotor:Destroy() end

	-- Criação limpa
	local newMotor = Instance.new("Motor6D")
	newMotor.Name = "MainMotor"
	newMotor.Part0 = targetPart
	newMotor.Part1 = handle
	newMotor.C0 = CFrame.new() -- Pivô zerado
	newMotor.C1 = cframeValue  -- Offset definido pela Tool (Posição + Rotação)
	newMotor.Parent = handle

	return newMotor
end

-- Toca uma animação no Humanoid
local function PlayAnimation(character, animId)
	if not animId then return nil end

	local humanoid = character:FindFirstChild("Humanoid")
	if not humanoid then return nil end

	local animator = humanoid:FindFirstChild("Animator") or Instance.new("Animator", humanoid)
	local animation = Instance.new("Animation")
	animation.AnimationId = animId

	-- Para animações antigas se existirem (evita bugs de sobreposição)
	for _, track in pairs(animator:GetPlayingAnimationTracks()) do
		if track.Animation.AnimationId == animId then
			track:Stop()
		end
	end

	local track = animator:LoadAnimation(animation)
	track:Play()
	return track
end

-- ============================================================================
-- 2. LÓGICA DE VISUALIZAÇÃO
-- ============================================================================

local function EquipVisual(player, itemName)
	-- OBS: Não verificamos cooldown aqui. O InventoryHandler já fez isso.
	local character = player.Character
	if not character then return end

	local itemInfo = ItemData.Get(itemName)
	if not itemInfo or not itemInfo.Model then return end

	-- Limpa arma anterior visualmente (Garante que só tem 1 arma)
	if ActiveWeapons[player.UserId] then
		ActiveWeapons[player.UserId]:Destroy()
		ActiveWeapons[player.UserId] = nil
	end

	-- Setup da Nova Arma
	local weaponModel = itemInfo.Model:Clone()
	weaponModel.Name = "Equipped_" .. itemName
	weaponModel.Parent = character
	ActiveWeapons[player.UserId] = weaponModel

	-- Referências
	local sheathPart = character:FindFirstChild(itemInfo.SheathPart or "Torso")
	local rightArm = character:FindFirstChild("Right Arm")

	-- Valores de CFrame (Posição/Rotação) salvos na Tool
	local backCF = weaponModel:FindFirstChild("Back") and weaponModel.Back.Value
	local handCF = weaponModel:FindFirstChild("Hand") and weaponModel.Hand.Value

	-- Passo 1: Prende nas Costas (Sheath)
	if sheathPart and backCF then
		ForceNewMotor(weaponModel, sheathPart, backCF)
	end

	-- Passo 2: Animação e Transição
	if itemInfo.Animations and itemInfo.Animations.Equip then
		local track = PlayAnimation(character, itemInfo.Animations.Equip)

		if track then
			track:GetMarkerReachedSignal("Reach"):Connect(function()
				-- Momento exato da troca: Deleta motor das costas -> Cria motor na mão
				-- Verifica se a arma ainda existe (Player pode ter desequipado no meio da animação)
				if weaponModel and weaponModel.Parent and rightArm and handCF then
					ForceNewMotor(weaponModel, rightArm, handCF)
				end
			end)
		end
	end
end

local function UnequipVisual(player, itemName)
	local character = player.Character
	if not character then return end

	local weaponModel = ActiveWeapons[player.UserId]
	if not weaponModel then return end 

	local itemInfo = ItemData.Get(itemName)
	if not itemInfo then return end

	local sheathPart = character:FindFirstChild(itemInfo.SheathPart or "Torso")
	local backCF = weaponModel:FindFirstChild("Back") and weaponModel.Back.Value

	-- Função interna para garantir a volta às costas
	local function SwapToBack()
		if not weaponModel or not weaponModel.Parent then return end

		if sheathPart and backCF then
			ForceNewMotor(weaponModel, sheathPart, backCF)
		end
	end

	-- Passo 1: Animação de Guardar
	if itemInfo.Animations and itemInfo.Animations.Unequip then
		local track = PlayAnimation(character, itemInfo.Animations.Unequip)

		if track then
			local moved = false

			-- Tenta trocar no momento exato (Mais suave)
			track:GetMarkerReachedSignal("Reach"):Connect(function()
				SwapToBack()
				moved = true
			end)

			-- Segurança: Se o evento falhar ou animação acabar, troca mesmo assim
			track.Stopped:Connect(function()
				if not moved then SwapToBack() end
			end)
		else
			SwapToBack() -- Falha ao carregar animação
		end
	else
		SwapToBack() -- Sem animação configurada
	end
end

-- ============================================================================
-- 3. GERENCIAMENTO DE EVENTOS
-- ============================================================================

CombatEvent.Event:Connect(function(action, player, itemName)
	if action == "Equip" then
		EquipVisual(player, itemName)
	elseif action == "Unequip" then
		UnequipVisual(player, itemName)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	ActiveWeapons[player.UserId] = nil
end)