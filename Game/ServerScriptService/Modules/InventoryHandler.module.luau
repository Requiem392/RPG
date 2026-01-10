local InventoryHandler = {}
InventoryHandler.__index = InventoryHandler
InventoryHandler.Registry = {}

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

local GearUpdateEvent = ServerEvents:FindFirstChild("GearUpdate")
if not GearUpdateEvent then
    GearUpdateEvent = Instance.new("BindableEvent")
    GearUpdateEvent.Name = "GearUpdate"
    GearUpdateEvent.Parent = ServerEvents
end

-- ============================================================================
-- HELPER
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

-- ============================================================================
-- CLASS
-- ============================================================================

function InventoryHandler.new(owner)
    local self = setmetatable({}, InventoryHandler)
    self.Owner = owner
    
    self.Backpack = {}
    self.Hotbar = {}
    self.Gear = {}
    self.EquippedSlot = nil -- SlotKey (string) na Hotbar
    self.LastActionTime = 0
    
    InventoryHandler.Registry[owner] = self
    
    -- Itens Iniciais (Teste)
    -- TODO: Isso poderia vir de um DataStoreService separado que carrega e popula
    -- Mas por enquanto vamos manter a lógica hardcoded do original para compatibilidade.
    if owner:IsA("Player") then
        self.Backpack = {
			{Name = "Caladbolg", Amount = 1}, 
			{Name = "Sword", Amount = 1},
			{Name = "Dagger", Amount = 1},
			{Name = "Poção de Cura", Amount = 1},
			{Name = "Poção de Cura", Amount = 1},
			{Name = "Espada de Ferro", Amount = 1}
        }
    end
    
    task.wait(1)
    self:SendUpdate() -- Sincroniza inicial
    
    return self
end

function InventoryHandler:Destroy()
    -- Unequip current Weapon logic?
    if self.EquippedSlot then
        local item = self.Hotbar[self.EquippedSlot]
        if item then 
             CombatEvent:Fire("Unequip", self.Owner, item.Name)
        end
    end
    
    InventoryHandler.Registry[self.Owner] = nil
    self.Owner = nil
end

function InventoryHandler:SendUpdate()
    if not self.Owner:IsA("Player") then return end
    
    local currentWeight = CalculateWeight(self.Backpack, self.Hotbar, self.Gear)
	local maxWeight = 100 

	UpdateInvEvent:FireClient(self.Owner, {
		Backpack = self.Backpack,
		Hotbar = self.Hotbar,
		EquippedSlot = self.EquippedSlot,
		Gear = self.Gear, 
		CurrentWeight = currentWeight,
		MaxWeight = maxWeight
	})
    
    -- Notifica StatsHandler via Evento
    if GearUpdateEvent then
		GearUpdateEvent:Fire(self.Owner, self.Gear)
	end
end

-- API

function InventoryHandler:AddItem(itemName, quantity)
    quantity = quantity or 1
	local itemData = ItemData.Get(itemName)
	if not itemData then 
		warn("[InventoryHandler] Item não existe:", itemName)
		return false
	end

	-- Stack logic
	if itemData.Stackable then
		for _, item in ipairs(self.Backpack) do
			if item.Name == itemName then
				local maxStack = itemData.MaxStack or 99
				local space = maxStack - item.Amount

				if space > 0 then
					local toAdd = math.min(quantity, space)
					item.Amount = item.Amount + toAdd
					quantity = quantity - toAdd

					if quantity <= 0 then
						self:SendUpdate()
						return true
					end
				end
			end
		end
	end

	while quantity > 0 do
		local toAdd = itemData.Stackable and math.min(quantity, itemData.MaxStack or 99) or 1
		table.insert(self.Backpack, {Name = itemName, Amount = toAdd})
		quantity = quantity - toAdd
	end

	self:SendUpdate()
	return true
end

function InventoryHandler:GetGear()
    return self.Gear
end

function InventoryHandler:CheckDebounce(duration)
    local now = os.clock()
    if (now - self.LastActionTime) < duration then return false end
    self.LastActionTime = now
    return true
end

-- ============================================================================
-- LOGICA COMPLEXA DE MOVIMENTAÇÃO (Migrada do Evento Global para Método)
-- ============================================================================

function InventoryHandler:HandleMoveItem(itemName, targetSlot, sourceType, sourceIndex)
    local backpack = self.Backpack
    local hotbar = self.Hotbar
    local gear = self.Gear
    local player = self.Owner -- Só funciona direito se for Player por causa dos calls de CombatEvent?

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
        local wasDrawn = self:CheckWeaponDrawn(oldItemInSlot)

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
                                self:SendUpdate()
                                return 
                            else
                                itemAtTarget.Amount += space
                                itemMoved.Amount -= space
                                backpack[sourceIdx] = itemMoved 
                                self:SendUpdate()
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
                                self:SendUpdate()
                                return
                            else
                                itemAtTarget.Amount += space
                                itemMoved.Amount -= space
                                SetSourceItem(itemMoved) 
                                self:SendUpdate()
                                return
                            end
                        end
                    end
                end

                if sourceType == "Gear" then
                    local wasDrawn = self:CheckWeaponDrawn(itemMoved)
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

    -- 4. HOTBAR
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
                        self:SendUpdate()
                        return
                    else
                        oldItemOrSwap.Amount += space
                        itemMoved.Amount -= space
                        SetSourceItem(itemMoved)
                        self:SendUpdate()
                        return
                    end
                end
            end
        end

        hotbar[targetKey] = itemMoved
        SetSourceItem(oldItemOrSwap)
    end

    self:SendUpdate()
end

function InventoryHandler:CheckWeaponDrawn(item)
    if not item then return false end
    if not self.Owner then return false end
    local equippedModel = self.Owner.Character and self.Owner.Character:FindFirstChild("Equipped_" .. item.Name)
    if equippedModel then
        local handle = equippedModel:FindFirstChild("Handle")
        if handle and handle:FindFirstChild("RightArmMotor") then
            return true
        end
    end
    return false
end

function InventoryHandler:HandleUseItem()
    local equippedSlot = self.EquippedSlot
    if not equippedSlot then return end 

    local item = self.Hotbar[equippedSlot] 
    if not item then return end

    local data = ItemData.Get(item.Name)
    if not data then return end

    local player = self.Owner

    if data.Type == "Weapon" or data.Type == "Equipment" then
        local targetSlot = data.SlotType
        if targetSlot then
            local oldItem = self.Gear[targetSlot]
            local wasDrawn = self:CheckWeaponDrawn(oldItem)

            self.Gear[targetSlot] = item
            self.Hotbar[equippedSlot] = oldItem 

            CombatEvent:Fire("Equip", player, item.Name)
            if oldItem then CombatEvent:Fire("Unequip", player, oldItem.Name) end

            if wasDrawn then
                task.wait(0.3)
                CombatEvent:Fire("DrawWeapon", player, item.Name)
            end

            self:SendUpdate()
        end

    elseif data.Type == "Consumable" then
        if not self:CheckDebounce(0.2) then return end 

        CombatEvent:Fire("UseItem", player, item.Name)

        if data.Stackable then
            item.Amount -= 1
            if item.Amount <= 0 then
                self.Hotbar[equippedSlot] = nil
                self.EquippedSlot = nil 
            end
        else
            self.Hotbar[equippedSlot] = nil
            self.EquippedSlot = nil 
        end

        self:SendUpdate() 
    end
end


-- ============================================================================
-- INITIALIZAÇÃO ESTÁTICA
-- ============================================================================

local Initialized = false
function InventoryHandler.Init()
    if Initialized then return end
    Initialized = true
    print("🎒 Inicializando InventoryHandler (Static)...")
    
    -- MoveItem
    MoveItemEvent.OnServerEvent:Connect(function(player, itemName, targetSlot, sourceType, sourceIndex)
        local handler = InventoryHandler.Registry[player]
        if handler then
            handler:HandleMoveItem(itemName, targetSlot, sourceType, sourceIndex)
        end
    end)
    
    -- EquipEvent (Select Hotbar Slot)
    EquipEvent.OnServerEvent:Connect(function(player, slotNumber)
        local handler = InventoryHandler.Registry[player]
        if handler then
            local slotString = tostring(slotNumber)
            if handler.EquippedSlot == slotString then
                handler.EquippedSlot = nil
            else
                handler.EquippedSlot = slotString
            end
            handler:SendUpdate()
        end
    end)
    
    -- UseItemEvent
    UseItemEvent.OnServerEvent:Connect(function(player)
        local handler = InventoryHandler.Registry[player]
        if handler then
            handler:HandleUseItem()
        end
    end)
    
    print("✅ InventoryHandler Events Iniciados")
end

return InventoryHandler
