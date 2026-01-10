local InventoryService = {}

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

-- Módulos
local DataFolder = ReplicatedStorage:WaitForChild("Data")
local ItemData = require(DataFolder:WaitForChild("ItemData"))

-- Remotes
local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
if not Remotes then
    Remotes = Instance.new("Folder")
    Remotes.Name = "Remotes"
    Remotes.Parent = ReplicatedStorage
end

local function GetRemote(name, class)
	local remote = Remotes:FindFirstChild(name)
	if not remote then
		remote = Instance.new(class)
		remote.Name = name
		remote.Parent = Remotes
	end
	return remote
end

local EquipEvent = GetRemote("EquipItem", "RemoteEvent")
local MoveItemEvent = GetRemote("MoveItem", "RemoteEvent")
local UpdateInvEvent = GetRemote("UpdateInventory", "RemoteEvent")
local UseItemEvent = GetRemote("UseItem", "RemoteEvent")

-- Eventos Internos
local ServerEvents = ServerStorage:FindFirstChild("ServerEvents")
if not ServerEvents then
    ServerEvents = Instance.new("Folder")
    ServerEvents.Name = "ServerEvents"
    ServerEvents.Parent = ServerStorage
end

local CombatEvent = ServerEvents:FindFirstChild("CombatSystem")
if not CombatEvent then
    CombatEvent = Instance.new("BindableEvent")
    CombatEvent.Name = "CombatSystem"
    CombatEvent.Parent = ServerEvents
end

-- Evento de Atualização de Equipamento (Para StatsService)
local GearUpdateEvent = ServerEvents:FindFirstChild("GearUpdate")
if not GearUpdateEvent then
    GearUpdateEvent = Instance.new("BindableEvent")
    GearUpdateEvent.Name = "GearUpdate"
    GearUpdateEvent.Parent = ServerEvents
end

-- Dados dos Jogadores
local PlayerInventories = {} 
local PlayerHotbars = {}    
local PlayerEquipped = {} -- Slot da HOTBAR atualmente "selecionado"
local PlayerGear = {}     -- Slots de equipamento: { ["Weapon"] = "Caladbolg", ["Armor"] = "..." }  

-- Debounces Simples
local ActionDebounce = {} 

local function CheckDebounce(player, duration)
	local last = ActionDebounce[player.UserId] or 0
	local now = os.clock()
	if (now - last) < duration then return false end
	ActionDebounce[player.UserId] = now
	return true
end

-- ============================================================================
-- FUNÇÕES AUXILIARES
-- ============================================================================

local function CalculateWeight(backpack, hotbar, gear)
	local total = 0

	local function sumItem(item)
		if not item then return end
		local data = ItemData.Get(item.Name)
		if data and data.Weight then
			total += data.Weight * (item.Amount or 1)
		end
	end

	for _, item in pairs(backpack) do sumItem(item) end
	for _, item in pairs(hotbar) do sumItem(item) end
	if gear then for _, item in pairs(gear) do sumItem(item) end end

	return total
end

local function SendUpdate(player)
	local backpack = PlayerInventories[player.UserId] or {}
	local hotbar = PlayerHotbars[player.UserId] or {}
	local gear = PlayerGear[player.UserId] or {}

	local currentWeight = CalculateWeight(backpack, hotbar, gear)
	local maxWeight = 100 -- Valor fixo por enquanto, futuramente pode vir de status (Força)

	UpdateInvEvent:FireClient(player, {
		Backpack = backpack,
		Hotbar = hotbar,
		EquippedSlot = PlayerEquipped[player.UserId],
		Gear = gear, 
		CurrentWeight = currentWeight,
		MaxWeight = maxWeight
	})

	-- Notifica StatsService
	if GearUpdateEvent then
		GearUpdateEvent:Fire(player, gear)
	end
end

-- ============================================================================
-- API
-- ============================================================================

function InventoryService.AddItem(player, itemName, quantity)
	quantity = quantity or 1

	local backpack = PlayerInventories[player.UserId]
	if not backpack then return false end

	local itemData = ItemData.Get(itemName)
	if not itemData then 
		warn("[InventoryService] Item não existe:", itemName)
		return false
	end

	-- Se for stackable, tenta adicionar a stack existente
	if itemData.Stackable then
		for _, item in ipairs(backpack) do
			if item.Name == itemName then
				local maxStack = itemData.MaxStack or 99
				local space = maxStack - item.Amount

				if space > 0 then
					local toAdd = math.min(quantity, space)
					item.Amount = item.Amount + toAdd
					quantity = quantity - toAdd

					if quantity <= 0 then
						SendUpdate(player)
						return true
					end
				end
			end
		end
	end

	-- Adiciona novo slot pro resto (ou item não-stackable)
	while quantity > 0 do
		local toAdd = itemData.Stackable and math.min(quantity, itemData.MaxStack or 99) or 1
		table.insert(backpack, {Name = itemName, Amount = toAdd})
		quantity = quantity - toAdd
	end

	SendUpdate(player)
	return true
end

function InventoryService.GetPlayerGear(player)
    return PlayerGear[player.UserId]
end

-- ============================================================================
-- INITIALIZATION & EVENTS
-- ============================================================================

function InventoryService.Init()
    print("🎒 Inicializando InventoryService...")
    
	local function SetupPlayer(player)
		if PlayerInventories[player.UserId] then return end

		PlayerInventories[player.UserId] = {
			{Name = "Caladbolg", Amount = 1}, 
			{Name = "Sword", Amount = 1},
			{Name = "Dagger", Amount = 1},
			{Name = "Poção de Cura", Amount = 1},
			{Name = "Poção de Cura", Amount = 1},
			{Name = "Espada de Ferro", Amount = 1}
		} 

		PlayerHotbars[player.UserId] = {}
		PlayerGear[player.UserId] = {}
		PlayerEquipped[player.UserId] = nil

		task.wait(1)
		SendUpdate(player)
	end

	Players.PlayerAdded:Connect(SetupPlayer)
	for _, player in ipairs(Players:GetPlayers()) do SetupPlayer(player) end

	Players.PlayerRemoving:Connect(function(player)
		local currentSlot = PlayerEquipped[player.UserId]
		if currentSlot then
			local item = PlayerHotbars[player.UserId][currentSlot]
			if item then 
				CombatEvent:Fire("Unequip", player, item.Name)
			end
		end
		PlayerInventories[player.UserId] = nil
		PlayerHotbars[player.UserId] = nil
		PlayerGear[player.UserId] = nil
		PlayerEquipped[player.UserId] = nil
		ActionDebounce[player.UserId] = nil
	end)

    -- MoveItemEvent
    MoveItemEvent.OnServerEvent:Connect(function(player, itemName, targetSlot, sourceType, sourceIndex)
        -- ... (Include the full logic from MoveItemEvent handler here) ...
        -- To avoid massive duplication in the tool call, I will paste the logic here.
        
        local backpack = PlayerInventories[player.UserId]
        local hotbar = PlayerHotbars[player.UserId]
        local gear = PlayerGear[player.UserId]
    
        if not backpack then return end
    
        targetSlot = tostring(targetSlot)
        sourceIndex = (sourceType == "Hotbar") and tostring(sourceIndex) or sourceIndex 
    
        local function GetSourceItem()
            if sourceType == "Backpack" then return backpack[tonumber(sourceIndex)] end
            if sourceType == "Hotbar" then return hotbar[tostring(sourceIndex)] end
            if sourceType == "Gear" then return gear[tostring(sourceIndex)] end
            return nil
        end
    
        local function SetSourceItem(newItem) 
            if sourceType == "Backpack" then 
                if newItem then backpack[tonumber(sourceIndex)] = newItem else table.remove(backpack, tonumber(sourceIndex)) end
            elseif sourceType == "Hotbar" then 
                hotbar[tostring(sourceIndex)] = newItem 
            elseif sourceType == "Gear" then
                gear[tostring(sourceIndex)] = newItem
                if not newItem then CombatEvent:Fire("Unequip", player, itemName) end 
            end
        end
    
        local itemMoved = GetSourceItem()
        if not itemMoved or itemMoved.Name ~= itemName then return end 
    
        -- 1. GEAR
        if ItemData.Get(targetSlot) == nil and (targetSlot == "Weapon" or targetSlot == "Armor" or targetSlot == "Helm" or targetSlot == "OffHand" or string.find(targetSlot, "Ring")) then
            if sourceType == "Gear" and tostring(sourceIndex) == tostring(targetSlot) then return end
    
            local itemInfo = ItemData.Get(itemName)
            if not itemInfo or itemInfo.SlotType ~= targetSlot then return end
    
            local oldItemInSlot = gear[targetSlot] 
    
            -- Verifica se tinha arma sacada (pelo modelo no personagem)
            local wasDrawn = false
            if oldItemInSlot and player.Character then
                local equippedModel = player.Character:FindFirstChild("Equipped_" .. oldItemInSlot.Name)
                if equippedModel then
                    local handle = equippedModel:FindFirstChild("Handle")
                    if handle and handle:FindFirstChild("RightArmMotor") then
                        wasDrawn = true
                    end
                end
            end
    
            gear[targetSlot] = itemMoved
            SetSourceItem(oldItemInSlot)
    
            CombatEvent:Fire("Equip", player, itemMoved.Name)
    
            if wasDrawn then
                task.wait(0.3) 
                CombatEvent:Fire("DrawWeapon", player, itemMoved.Name)
            end
    
            -- 2. BACKPACK
        elseif targetSlot == "Backpack" then
            SetSourceItem(nil)
            table.insert(backpack, itemMoved)
    
            -- 3. SWAP / MERGE BACKPACK
        elseif string.sub(targetSlot, 1, 13) == "SwapBackpack_" then
            local targetIdx = tonumber(string.sub(targetSlot, 14))
            if targetIdx then
                if sourceType == "Backpack" then
                    local sourceIdx = tonumber(sourceIndex)
                    local itemAtTarget = backpack[targetIdx]
    
                    if itemAtTarget and itemAtTarget.Name == itemMoved.Name then
                        local data = ItemData.Get(itemMoved.Name)
                        if data and data.Stackable then
                            local space = (data.MaxStack or 99) - itemAtTarget.Amount
                            if space > 0 then
                                if itemMoved.Amount <= space then
                                    itemAtTarget.Amount += itemMoved.Amount
                                    SetSourceItem(nil)
                                    SendUpdate(player)
                                    return 
                                else
                                    itemAtTarget.Amount += space
                                    itemMoved.Amount -= space
                                    backpack[sourceIdx] = itemMoved 
                                    SendUpdate(player)
                                    return
                                end
                            end
                        end
                    end
    
                    backpack[sourceIdx] = itemAtTarget
                    backpack[targetIdx] = itemMoved
                else
                    local itemAtTarget = backpack[targetIdx]
    
                    if itemAtTarget and itemAtTarget.Name == itemMoved.Name then
                        local data = ItemData.Get(itemMoved.Name)
                        if data and data.Stackable then
                            local space = (data.MaxStack or 99) - itemAtTarget.Amount
                            if space > 0 then
                                if itemMoved.Amount <= space then
                                    itemAtTarget.Amount += itemMoved.Amount
                                    SetSourceItem(nil)
                                    SendUpdate(player)
                                    return
                                else
                                    itemAtTarget.Amount += space
                                    itemMoved.Amount -= space
                                    SetSourceItem(itemMoved) 
                                    SendUpdate(player)
                                    return
                                end
                            end
                        end
                    end
    
                    if sourceType == "Gear" then
                    local wasDrawn = false
                    if player.Character then
                        local equippedModel = player.Character:FindFirstChild("Equipped_" .. itemMoved.Name)
                        if equippedModel then
                            local handle = equippedModel:FindFirstChild("Handle")
                            if handle and handle:FindFirstChild("RightArmMotor") then
                                wasDrawn = true
                            end
                        end
                    end
                    
                    local canSwap = false
                    if not itemAtTarget then canSwap = true else
                        local dataTarget = ItemData.Get(itemAtTarget.Name)
                        if dataTarget and dataTarget.SlotType == sourceIndex then canSwap = true end
                    end
                    if canSwap then
                        SetSourceItem(itemAtTarget)
                        CombatEvent:Fire("Equip", player, itemAtTarget and itemAtTarget.Name)
                        if not itemAtTarget then 
                            CombatEvent:Fire("Unequip", player, itemMoved.Name) 
                        else
                            if wasDrawn then
                                task.wait(0.3)
                                CombatEvent:Fire("DrawWeapon", player, itemAtTarget.Name)
                            end
                        end
                    else
                        backpack[targetIdx] = itemAtTarget 
                        return 
                    end
                    elseif sourceType == "Hotbar" then
                        SetSourceItem(itemAtTarget)
                    end
                    backpack[targetIdx] = itemMoved
                end
            end
    
            -- 4. HOTBAR (Com Merge também)
        elseif tonumber(targetSlot) then 
            local targetKey = tostring(targetSlot)
            local oldItemOrSwap = hotbar[targetKey]
    
            if oldItemOrSwap and oldItemOrSwap.Name == itemMoved.Name then
                local data = ItemData.Get(itemMoved.Name)
                if data and data.Stackable then
                    local space = (data.MaxStack or 99) - oldItemOrSwap.Amount
                    if space > 0 then
                        if itemMoved.Amount <= space then
                            oldItemOrSwap.Amount += itemMoved.Amount
                            SetSourceItem(nil)
                            SendUpdate(player)
                            return
                        else
                            oldItemOrSwap.Amount += space
                            itemMoved.Amount -= space
                            SetSourceItem(itemMoved)
                            SendUpdate(player)
                            return
                        end
                    end
                end
            end
    
            hotbar[targetKey] = itemMoved
            SetSourceItem(oldItemOrSwap)
        end
    
        SendUpdate(player)
    end)
    
    -- EquipEvent
    EquipEvent.OnServerEvent:Connect(function(player, slotNumber)
        local slotString = tostring(slotNumber)
        if PlayerEquipped[player.UserId] == slotString then
            PlayerEquipped[player.UserId] = nil
        else
            PlayerEquipped[player.UserId] = slotString
        end
        SendUpdate(player)
    end)
    
    -- UseItemEvent
    UseItemEvent.OnServerEvent:Connect(function(player)
        local equippedSlot = PlayerEquipped[player.UserId]
        if not equippedSlot then return end 
    
        local hotbar = PlayerHotbars[player.UserId]
        local item = hotbar[equippedSlot] 
        if not item then return end
    
        local data = ItemData.Get(item.Name)
        if not data then return end
    
        if data.Type == "Weapon" or data.Type == "Equipment" then
            local targetSlot = data.SlotType
            if targetSlot then
                local gear = PlayerGear[player.UserId]
                local oldItem = gear[targetSlot]
    
                local wasDrawn = false
                if oldItem and player.Character then
                    local equippedModel = player.Character:FindFirstChild("Equipped_" .. oldItem.Name)
                    if equippedModel then
                        local handle = equippedModel:FindFirstChild("Handle")
                        if handle and handle:FindFirstChild("RightArmMotor") then
                            wasDrawn = true
                        end
                    end
                end
    
                gear[targetSlot] = item
                hotbar[equippedSlot] = oldItem 
    
                CombatEvent:Fire("Equip", player, item.Name)
                if oldItem then CombatEvent:Fire("Unequip", player, oldItem.Name) end
    
                if wasDrawn then
                    task.wait(0.3)
                    CombatEvent:Fire("DrawWeapon", player, item.Name)
                end
    
                SendUpdate(player)
            end
    
        elseif data.Type == "Consumable" then
            if not CheckDebounce(player, 0.2) then return end 
    
            CombatEvent:Fire("UseItem", player, item.Name)
    
            if data.Stackable then
                item.Amount -= 1
                if item.Amount <= 0 then
                    hotbar[equippedSlot] = nil
                    PlayerEquipped[player.UserId] = nil 
                end
            else
                hotbar[equippedSlot] = nil
                PlayerEquipped[player.UserId] = nil 
            end
    
            SendUpdate(player) 
        end
    end)

    print("✅ InventoryService iniciado")
end

return InventoryService
