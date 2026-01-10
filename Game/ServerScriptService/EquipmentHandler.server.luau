local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- [[ MÓDULOS E DADOS ]] --
local DataFolder = ReplicatedStorage:WaitForChild("Data")
local ItemData = require(DataFolder:WaitForChild("ItemData"))

local Modules = ServerScriptService:WaitForChild("Modules")
local InventoryHandler = require(Modules:WaitForChild("InventoryHandler"))

local ServerEvents = ServerStorage:WaitForChild("ServerEvents")
local CombatEvent = ServerEvents:WaitForChild("CombatSystem")

-- Remotes
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
local CombatStateEvent = GetRemote("CombatState", "RemoteEvent") -- Mantido para receber inputs do client e refletir em atributos

-- [[ ESTADO DO SERVIDOR (CACHE VISUAL APENAS)]] --
-- OBS: O estado de GAMEPLAY agora reside nos Attributes do Character.
-- ActiveWeapons é mantido APENAS para referência de limpeza visual (Destroy models).
local ActiveWeapons = {} 

-- Debounce
local ToggleDebounce = {}

-- ============================================================================
-- 1. FUNÇÕES UTILITÁRIAS
-- ============================================================================

local function ClearAllMotors(handle)
	local motors = {"MainMotor", "RightArmMotor", "LeftArmMotor"}
	for _, name in pairs(motors) do
		local motor = handle:FindFirstChild(name)
		if motor then motor:Destroy() end
	end
end

local function ForceNewMotor(weaponModel, targetPart, cframeValue)
	local handle = weaponModel:FindFirstChild("Handle")
	if not handle then return nil end
	ClearAllMotors(handle)
	local newMotor = Instance.new("Motor6D")
	newMotor.Name = "MainMotor"
	newMotor.Part0 = targetPart
	newMotor.Part1 = handle
	newMotor.C0 = CFrame.new() 
	newMotor.C1 = cframeValue  
	newMotor.Parent = handle
	return newMotor
end

local function PlayAnimation(character, animId)
	if not animId then return nil end
	local humanoid = character:FindFirstChild("Humanoid")
	if not humanoid then return nil end
	local animator = humanoid:FindFirstChild("Animator") or Instance.new("Animator", humanoid)
	local animation = Instance.new("Animation")
	animation.AnimationId = animId
	-- Stop same anims
	for _, track in pairs(animator:GetPlayingAnimationTracks()) do
		if track.Animation.AnimationId == animId then track:Stop() end
	end
	local track = animator:LoadAnimation(animation)
	track:Play()
	return track
end

local function GetAnimationId(itemInfo, animName)
	if itemInfo.Animations and itemInfo.Animations[animName] then
		return itemInfo.Animations[animName]
	end
	if itemInfo.WeaponCategory then
		local categoryData = ItemData.GetCategory(itemInfo.WeaponCategory)
		if categoryData and categoryData.Animations and categoryData.Animations[animName] then
			return categoryData.Animations[animName]
		end
	end
	return nil
end

-- ============================================================================
-- 2. LÓGICA DE ATRIBUTOS (Helpers)
-- ============================================================================

local function UpdateCombatState(character, inCombat, equippedWeaponName)
    if not character then return end
    character:SetAttribute("InCombat", inCombat)
    character:SetAttribute("EquippedWeapon", equippedWeaponName or "")
    if not inCombat then
        character:SetAttribute("IsAttacking", false)
        character:SetAttribute("IsBlocking", false)
    end
end

-- ============================================================================
-- 3. LÓGICA DE VISUALIZAÇÃO
-- ============================================================================

local function EquipVisual(player, itemName)
	local character = player.Character
	if not character then return end

	local itemInfo = ItemData.Get(itemName)
	if not itemInfo or not itemInfo.Model then return end

	if itemInfo.SlotType and itemInfo.SlotType ~= "Weapon" then return end

	-- Limpa Visual Anterior
	if ActiveWeapons[player.UserId] then
		ActiveWeapons[player.UserId]:Destroy()
		ActiveWeapons[player.UserId] = nil
	end

	-- Cria Novo Visual
	local weaponModel = itemInfo.Model:Clone()
	weaponModel.Name = "Equipped_" .. itemName
	weaponModel.Parent = character
	ActiveWeapons[player.UserId] = weaponModel

	-- Sheath (Costas)
	local sheathPart = character:FindFirstChild(itemInfo.SheathPart or "Torso")
	local backCF = weaponModel:FindFirstChild("Back") and weaponModel.Back.Value

	if sheathPart and backCF then
		ForceNewMotor(weaponModel, sheathPart, backCF)
	end
    
    -- Atualiza Atributo (Equipou, mas ainda não sacou -> InCombat=false por padrão aqui, ou mantem anterior?)
    -- EquipItem geralmente guarda nas costas.
    UpdateCombatState(character, false, itemName)
end

local function DrawWeapon(player, itemName)
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

	local function CreateBothMotors()
		ClearAllMotors(handle)
		local rightMotor = Instance.new("Motor6D")
		rightMotor.Name = "RightArmMotor"
		rightMotor.Part0 = rightArm
		rightMotor.Part1 = handle
		rightMotor.C0 = CFrame.new()
		rightMotor.C1 = handCF
		rightMotor.Enabled = true
		rightMotor.Parent = handle
	end

	local equipAnimId = GetAnimationId(itemInfo, "Equip")
	if equipAnimId then
		local track = PlayAnimation(character, equipAnimId)
		if track then
			track:GetMarkerReachedSignal("Reach"):Connect(function()
				if weaponModel and weaponModel.Parent then CreateBothMotors() end
			end)
		end
	else
		CreateBothMotors()
	end
    
    -- Atualiza Atributo
    UpdateCombatState(character, true, itemName)
end

local function SheathWeapon(player, itemName)
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
			track:GetMarkerReachedSignal("Reach"):Connect(SwapToBack)
			track.Stopped:Connect(SwapToBack)
		else
			SwapToBack()
		end
	else
		SwapToBack()
	end
    
    -- Atualiza Atributo
    UpdateCombatState(character, false, itemName)
end

local function UnequipVisual(player, itemName)
	local weaponModel = ActiveWeapons[player.UserId]
	if weaponModel then 
		weaponModel:Destroy() 
		ActiveWeapons[player.UserId] = nil
	end
    
    -- Atualiza Atributo
    if player.Character then
        UpdateCombatState(player.Character, false, "")
    end
end

-- ============================================================================
-- 4. EVENTOS & ORQUESTRAÇÃO
-- ============================================================================

-- ============================================================================
-- 5. REATIVIDADE (Visual System)
-- ============================================================================

-- Função para conectar sinais de um personagem
local function ConnectCharacterVisuals(player, character)
    if not character then return end
    
    -- Listener para EquippedWeapon (Visual de Equipamento)
    character:GetAttributeChangedSignal("EquippedWeapon"):Connect(function()
        local weaponName = character:GetAttribute("EquippedWeapon")
        local inCombat = character:GetAttribute("InCombat")
        
        -- Se weaponName for vazio, removemos tudo
        if not weaponName or weaponName == "" then
             UnequipVisual(player, nil) -- nil pois activeWeapons usa player index
             return
        end
        
        -- Se estiver em combate vs pacifico
        if inCombat then
            DrawWeapon(player, weaponName)
        else
            -- Se tiver arma, mas inCombat=false, bota nas costas
            -- Verifica se já temos o modelo (EquipVisual logic)
            if not ActiveWeapons[player.UserId] or ActiveWeapons[player.UserId].Name ~= "Equipped_"..weaponName then
                 EquipVisual(player, weaponName)
            else
                 SheathWeapon(player, weaponName)
            end
        end
    end)
    
    -- Listener para InCombat (Saca/Guarda)
    character:GetAttributeChangedSignal("InCombat"):Connect(function()
        local inCombat = character:GetAttribute("InCombat")
        local weaponName = character:GetAttribute("EquippedWeapon")
        
        if not weaponName or weaponName == "" then return end
        
        if inCombat then
            DrawWeapon(player, weaponName)
        else
            SheathWeapon(player, weaponName)
        end
    end)
end

Players.PlayerAdded:Connect(function(player)
    player.CharacterAdded:Connect(function(char)
        ConnectCharacterVisuals(player, char)
    end)
    if player.Character then
        ConnectCharacterVisuals(player, player.Character)
    end
end)

-- Mantemos Events para acionar a mudança de ATRIBUTO (Input -> Remote -> SetAttribute -> Visual)
CombatEvent.Event:Connect(function(action, player, itemName)
    -- Traduz Ações Imperativas para Mudança de Estado (Atributos)
    local char = player.Character
    if not char then return end
    
	if action == "Equip" then
        -- Define atributo (Trigger listener)
		UpdateCombatState(char, false, itemName)
        
	elseif action == "Unequip" then
        UpdateCombatState(char, false, "")
        
	elseif action == "DrawWeapon" then
        UpdateCombatState(char, true, itemName)
        
	elseif action == "SheathWeapon" then
        UpdateCombatState(char, false, itemName)
	end
end)

-- Sincronia de Estado Client -> Server Attributes
CombatStateEvent.OnServerEvent:Connect(function(player, stateType, value)
    local char = player.Character
    if not char then return end
    
	if stateType == "Attacking" then
		char:SetAttribute("IsAttacking", value or false)
	elseif stateType == "Blocking" then
		char:SetAttribute("IsBlocking", value or false)
	end
end)

-- Toggle Combat ('T')
ToggleCombatEvent.OnServerEvent:Connect(function(player)
	local now = tick()
	local lastToggle = ToggleDebounce[player.UserId] or 0
	if (now - lastToggle) < 0.8 then return end
	ToggleDebounce[player.UserId] = now

    local char = player.Character
    if not char then return end

	-- VALIDAÇÃO VIA ATRIBUTOS
	if char:GetAttribute("IsAttacking") then
		print("⚠️ Bloqueado: Atacando")
		return
	end

	if char:GetAttribute("IsBlocking") then
		print("⚠️ Bloqueado: Bloqueando")
		return
	end

	-- Busca arma equipada no handler
	local weaponItem = nil
    local handler = InventoryHandler.Registry[player]
	if handler then
		local gear = handler:GetGear()
		weaponItem = gear and gear["Weapon"]
	end

	if not weaponItem then 
		print("⚠️ Sem arma equipada")
		return 
	end

	-- Toggle via Atributo
	local inCombat = not char:GetAttribute("InCombat")
    -- O visual atualiza o atributo, mas aqui decidimos a ação
    
	if inCombat then
		CombatEvent:Fire("DrawWeapon", player, weaponItem.Name) 
	else
		CombatEvent:Fire("SheathWeapon", player, weaponItem.Name) 
	end
end)

Players.PlayerRemoving:Connect(function(player)
	ActiveWeapons[player.UserId] = nil
	ToggleDebounce[player.UserId] = nil
end)

print("✅ EquipmentHandler Stateless (Attributes) Iniciado")