local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- [[ MÓDULOS E DADOS ]] --
local DataFolder = ReplicatedStorage:WaitForChild("Data")
local ItemData = require(DataFolder:WaitForChild("ItemData"))

local Modules = ServerScriptService:WaitForChild("Modules")
local InventoryService = require(Modules:WaitForChild("InventoryService"))

local ServerEvents = ServerStorage:WaitForChild("ServerEvents")
local CombatEvent = ServerEvents:WaitForChild("CombatSystem")

-- Remotes (cria se não existir para evitar infinite yield)
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local function GetRemote(name, class)
	local remote = Remotes:FindFirstChild(name)
	if not remote then
		remote = Instance.new(class)
		remote.Name = name
		remote.Parent = Remotes
		print("🔧 [EquipmentHandler] Criou remote:", name)
	end
	return remote
end

local ToggleCombatEvent = GetRemote("ToggleCombat", "RemoteEvent")
local CombatStateEvent = GetRemote("CombatState", "RemoteEvent")

-- [[ ESTADO DO SERVIDOR ]] --
local ActiveWeapons = {}   -- Armazena o modelo da arma atual de cada jogador
local PlayerInCombat = {}  -- Estado: arma sacada (true) ou guardada (false)
local PlayerAttackState = {} -- Rastreia se está atacando
local PlayerBlockState = {} -- Rastreia se está bloqueando

-- Debounce
local ToggleDebounce = {}

-- ============================================================================
-- 1. FUNÇÕES UTILITÁRIAS
-- ============================================================================

-- Limpa todos os motores de handle
local function ClearAllMotors(handle)
	local motors = {"MainMotor", "RightArmMotor", "LeftArmMotor"}
	for _, name in pairs(motors) do
		local motor = handle:FindFirstChild(name)
		if motor then motor:Destroy() end
	end
end

-- Destrói qualquer Motor existente e cria um novo "limpo" (Reset Absoluto)
local function ForceNewMotor(weaponModel, targetPart, cframeValue)
	local handle = weaponModel:FindFirstChild("Handle")
	if not handle then return nil end

	-- Limpeza total
	ClearAllMotors(handle)

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

-- Busca ID de animação (arma específica ou categoria)
local function GetAnimationId(itemInfo, animName)
	-- 1. Tenta pegar da arma específica
	if itemInfo.Animations and itemInfo.Animations[animName] then
		return itemInfo.Animations[animName]
	end

	-- 2. Se não tem, pega da categoria
	if itemInfo.WeaponCategory then
		local categoryData = ItemData.GetCategory(itemInfo.WeaponCategory)
		if categoryData and categoryData.Animations and categoryData.Animations[animName] then
			return categoryData.Animations[animName]
		end
	end

	return nil
end

-- ============================================================================
-- 2. LÓGICA DE VISUALIZAÇÃO
-- ============================================================================

-- ============================================================================
-- 2. LÓGICA DE VISUALIZAÇÃO
-- ============================================================================

local function EquipVisual(player, itemName)
	-- Apenas cria o modelo e coloca nas costas (SHEATH)
	local character = player.Character
	if not character then return end

	local itemInfo = ItemData.Get(itemName)
	if not itemInfo or not itemInfo.Model then return end

	-- Se for equipamento de armadura, prende no corpo (Lógica simplificada para armadura)
	if itemInfo.SlotType and itemInfo.SlotType ~= "Weapon" then
		-- Lógica de armadura (Por enquanto apenas ignora ou solda no Character)
		-- Futuramente implementar Weld no BodyPart correto
		return 
	end

	-- Limpa arma anterior visualmente
	if ActiveWeapons[player.UserId] then
		ActiveWeapons[player.UserId]:Destroy()
		ActiveWeapons[player.UserId] = nil
	end

	-- Setup da Nova Arma
	local weaponModel = itemInfo.Model:Clone()
	weaponModel.Name = "Equipped_" .. itemName
	weaponModel.Parent = character
	ActiveWeapons[player.UserId] = weaponModel

	local sheathPart = character:FindFirstChild(itemInfo.SheathPart or "Torso")
	local backCF = weaponModel:FindFirstChild("Back") and weaponModel.Back.Value

	-- Prende nas Costas (Sheath) imediatamente, sem animação
	if sheathPart and backCF then
		ForceNewMotor(weaponModel, sheathPart, backCF)
	end
end

local function DrawWeapon(player, itemName)
	-- Tira das costas -> Mão (Com Animação)
	local character = player.Character
	local weaponModel = ActiveWeapons[player.UserId]
	if not character or not weaponModel then return end

	local itemInfo = ItemData.Get(itemName)
	if not itemInfo then return end

	local rightArm = character:FindFirstChild("Right Arm")
	local leftArm = character:FindFirstChild("Left Arm")
	local handle = weaponModel:FindFirstChild("Handle")
	local handCF = weaponModel:FindFirstChild("Hand") and weaponModel.Hand.Value

	if not handle or not handCF then return end

	-- Função para criar os dois Motor6D
	local function CreateBothMotors()
		-- Limpa TODOS os motores antigos
		ClearAllMotors(handle)

		-- Cria Motor6D para Right Arm (único motor usado)
		local rightMotor = Instance.new("Motor6D")
		rightMotor.Name = "RightArmMotor"
		rightMotor.Part0 = rightArm
		rightMotor.Part1 = handle
		rightMotor.C0 = CFrame.new()
		rightMotor.C1 = handCF
		rightMotor.Enabled = true
		rightMotor.Parent = handle

		print("⚔️ [EquipmentHandler] Criado RightArmMotor")
	end

	local equipAnimId = GetAnimationId(itemInfo, "Equip")

	if equipAnimId then
		local track = PlayAnimation(character, equipAnimId)
		if track then
			track:GetMarkerReachedSignal("Reach"):Connect(function()
				if weaponModel and weaponModel.Parent and rightArm and leftArm then
					CreateBothMotors()
				end
			end)
		end
	else
		-- Se não tem animação, cria direto
		CreateBothMotors()
	end
end

local function SheathWeapon(player, itemName)
	-- Tira da Mão -> Costas (Com Animação)
	local character = player.Character
	local weaponModel = ActiveWeapons[player.UserId]
	if not character or not weaponModel then return end

	local itemInfo = ItemData.Get(itemName)
	if not itemInfo then return end

	local sheathPart = character:FindFirstChild(itemInfo.SheathPart or "Torso")
	local backCF = weaponModel:FindFirstChild("Back") and weaponModel.Back.Value

	local function SwapToBack()
		if not weaponModel or not weaponModel.Parent then return end
		if sheathPart and backCF then
			ForceNewMotor(weaponModel, sheathPart, backCF)
		end
	end

	local unequipAnimId = GetAnimationId(itemInfo, "Unequip")

	if unequipAnimId then
		local track = PlayAnimation(character, unequipAnimId)
		if track then
			track:GetMarkerReachedSignal("Reach"):Connect(function()
				SwapToBack()
			end)
			-- Fallback
			track.Stopped:Connect(function() SwapToBack() end)
		else
			SwapToBack()
		end
	else
		SwapToBack()
	end
end

local function UnequipVisual(player, itemName)
	-- Remove totalmente o modelo (do jogo)
	local weaponModel = ActiveWeapons[player.UserId]
	if weaponModel then 
		weaponModel:Destroy() 
		ActiveWeapons[player.UserId] = nil
	end

	-- RESETA ESTADO DE COMBATE NO SERVIDOR (sincroniza com cliente)
	PlayerInCombat[player.UserId] = false
	print("🕊️ [UnequipVisual] PlayerInCombat resetado para:", player.Name)
end

-- ============================================================================
-- 3. GERENCIAMENTO DE EVENTOS
-- ============================================================================

CombatEvent.Event:Connect(function(action, player, itemName)
	print("🛡️ [EquipmentHandler] Ação Recebida:", action, "| Item:", itemName)

	if action == "Equip" then
		EquipVisual(player, itemName)
	elseif action == "Unequip" then
		UnequipVisual(player, itemName)
	elseif action == "DrawWeapon" then
		DrawWeapon(player, itemName)
	elseif action == "SheathWeapon" then
		SheathWeapon(player, itemName)
	end
end)

-- ============================================================================
-- RECEBE ESTADO DE COMBATE DO CLIENTE
-- ============================================================================
CombatStateEvent.OnServerEvent:Connect(function(player, stateType, value)
	if stateType == "Attacking" then
		PlayerAttackState[player.UserId] = value or false
	elseif stateType == "Blocking" then
		PlayerBlockState[player.UserId] = value or false
	end
end)

-- ============================================================================
-- TOGGLE COMBAT ('T') - SACAR/GUARDAR ARMA
-- ============================================================================
ToggleCombatEvent.OnServerEvent:Connect(function(player)
	-- Debounce
	local now = tick()
	local lastToggle = ToggleDebounce[player.UserId] or 0
	if (now - lastToggle) < 0.8 then return end
	ToggleDebounce[player.UserId] = now

	-- VALIDAÇÃO: Bloqueia toggle durante ataque ou bloqueio
	if PlayerAttackState[player.UserId] then
		print("⚠️ [EquipmentHandler] Bloqueado: Player", player.Name, "está atacando!")
		return
	end

	if PlayerBlockState[player.UserId] then
		print("⚠️ [EquipmentHandler] Bloqueado: Player", player.Name, "está bloqueando!")
		return
	end

	-- Verifica se tem arma equipada no slot Weapon do inventário
	-- (Essa informação vem do InventoryHandler/InventoryService)
	local weaponItem = nil
	if InventoryService.GetPlayerGear then
		local gear = InventoryService.GetPlayerGear(player)
		weaponItem = gear and gear["Weapon"]
	end

	if not weaponItem then 
		print("⚠️ [EquipmentHandler] Player", player.Name, "não tem arma equipada")
		return 
	end

	-- Toggle state
	local inCombat = not (PlayerInCombat[player.UserId] or false)
	PlayerInCombat[player.UserId] = inCombat

	if inCombat then
		CombatEvent:Fire("DrawWeapon", player, weaponItem.Name) 
	else
		CombatEvent:Fire("SheathWeapon", player, weaponItem.Name) 
	end
end)

-- Cleanup
Players.PlayerRemoving:Connect(function(player)
	ActiveWeapons[player.UserId] = nil
	PlayerInCombat[player.UserId] = nil
	PlayerAttackState[player.UserId] = nil
	PlayerBlockState[player.UserId] = nil
	ToggleDebounce[player.UserId] = nil
end)

print("✅ EquipmentHandler Iniciado")