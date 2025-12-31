local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

print(">>> SERVER: InventoryHandler (Lógico - Puro) Iniciado")

-- Módulos
local DataFolder = ReplicatedStorage:WaitForChild("Data")
local ItemData = require(DataFolder:WaitForChild("ItemData"))

-- Remotes (Comunicação com Cliente)
local Remotes = ReplicatedStorage:FindFirstChild("Remotes") or Instance.new("Folder", ReplicatedStorage)
Remotes.Name = "Remotes"

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

-- COMUNICAÇÃO INTERNA (BindableEvent)
local ServerEvents = ServerStorage:FindFirstChild("ServerEvents") or Instance.new("Folder", ServerStorage)
ServerEvents.Name = "ServerEvents"
local CombatEvent = ServerEvents:FindFirstChild("CombatSystem") or Instance.new("BindableEvent", ServerEvents)
CombatEvent.Name = "CombatSystem"

-- Dados dos Jogadores
local PlayerInventories = {} 
local PlayerHotbars = {}    
local PlayerEquipped = {} 
local MAX_HOTBAR_SLOTS = 10

-- ============================================================================
-- FUNÇÕES AUXILIARES
-- ============================================================================
local function SendUpdate(player)
	UpdateInvEvent:FireClient(player, {
		Backpack = PlayerInventories[player.UserId] or {},
		Hotbar = PlayerHotbars[player.UserId] or {},
		EquippedSlot = PlayerEquipped[player.UserId] 
	})
end

-- ============================================================================
-- SETUP DO JOGADOR
-- ============================================================================
local function SetupPlayer(player)
	if PlayerInventories[player.UserId] then return end

	print(">>> Configurando dados de: " .. player.Name)

	-- Inventário Inicial (Caladbolg inclusa)
	PlayerInventories[player.UserId] = {
		"Caladbolg", 
		"Poção de Cura", 
		"Poção de Cura"
	} 

	PlayerHotbars[player.UserId] = {}
	PlayerEquipped[player.UserId] = nil

	task.wait(1)
	SendUpdate(player)
end

Players.PlayerAdded:Connect(SetupPlayer)
for _, player in ipairs(Players:GetPlayers()) do SetupPlayer(player) end

Players.PlayerRemoving:Connect(function(player)
	-- Se sair com algo equipado, avisa o sistema de combate para limpar
	local currentSlot = PlayerEquipped[player.UserId]
	if currentSlot then
		local itemName = PlayerHotbars[player.UserId][currentSlot]
		if itemName then
			CombatEvent:Fire("Unequip", player, itemName)
		end
	end

	PlayerInventories[player.UserId] = nil
	PlayerHotbars[player.UserId] = nil
	PlayerEquipped[player.UserId] = nil
end)

-- ============================================================================
-- MOVIMENTAÇÃO (Lógica Pura)
-- ============================================================================
MoveItemEvent.OnServerEvent:Connect(function(player, itemName, targetSlot, sourceType, sourceIndex)
	local backpack = PlayerInventories[player.UserId]
	local hotbar = PlayerHotbars[player.UserId]
	if not backpack then return end

	targetSlot = tostring(targetSlot)
	sourceIndex = (sourceType == "Hotbar") and tostring(sourceIndex) or tonumber(sourceIndex)

	local currentEquipped = PlayerEquipped[player.UserId]

	-- Helper: Se mexer no item equipado, avisa pra tirar da mão
	local function CheckUnequip(slotMexido)
		if tostring(currentEquipped) == tostring(slotMexido) then
			PlayerEquipped[player.UserId] = nil
			CombatEvent:Fire("Unequip", player, itemName)
		end
	end

	if sourceType == "Backpack" and targetSlot ~= "Backpack" then
		-- Mochila -> Hotbar
		if backpack[sourceIndex] == itemName then
			CheckUnequip(targetSlot) 

			local oldItem = hotbar[targetSlot]
			hotbar[targetSlot] = itemName
			table.remove(backpack, sourceIndex)

			if oldItem then table.insert(backpack, oldItem) end
		end

	elseif sourceType == "Hotbar" and targetSlot ~= "Backpack" then
		-- Hotbar -> Hotbar
		local temp = hotbar[targetSlot]
		hotbar[targetSlot] = hotbar[sourceIndex]
		hotbar[sourceIndex] = temp

		if tostring(currentEquipped) == sourceIndex then
			PlayerEquipped[player.UserId] = targetSlot
		elseif tostring(currentEquipped) == targetSlot then
			PlayerEquipped[player.UserId] = sourceIndex
		end

	elseif sourceType == "Hotbar" and targetSlot == "Backpack" then
		-- Hotbar -> Mochila
		CheckUnequip(sourceIndex)

		local item = hotbar[sourceIndex]
		if item then
			hotbar[sourceIndex] = nil
			table.insert(backpack, item)
		end
	end

	SendUpdate(player)
end)

-- ============================================================================
-- EQUIPAR (Lógica Pura)
-- ============================================================================
EquipEvent.OnServerEvent:Connect(function(player, slotNumber)
	local hotbar = PlayerHotbars[player.UserId]
	local slotString = tostring(slotNumber)
	local itemName = hotbar[slotString] 

	-- Caso 1: Toggle Off (Desequipar)
	if PlayerEquipped[player.UserId] == slotString then
		PlayerEquipped[player.UserId] = nil

		if itemName then
			CombatEvent:Fire("Unequip", player, itemName)
		end

	else
		-- Caso 2: Equipar novo item
		if not itemName then return end

		-- Se já tinha outro item na mão, tira ele primeiro
		local oldSlot = PlayerEquipped[player.UserId]
		if oldSlot then
			local oldItem = hotbar[oldSlot]
			if oldItem then
				CombatEvent:Fire("Unequip", player, oldItem)
			end
		end

		PlayerEquipped[player.UserId] = slotString
		CombatEvent:Fire("Equip", player, itemName)
	end

	SendUpdate(player)
end)

-- ============================================================================
-- USAR ITEM (Corrigido: Delega o efeito)
-- ============================================================================
UseItemEvent.OnServerEvent:Connect(function(player)
	local equippedSlot = PlayerEquipped[player.UserId]
	if not equippedSlot then return end 

	local hotbar = PlayerHotbars[player.UserId]
	local itemName = hotbar[equippedSlot]
	if not itemName then return end

	-- Usa a busca por categoria
	local data = ItemData.Get(itemName)
	if not data then return end

	-- Lógica de Consumível
	if data.Type == "Consumable" then
		-- 1. O Inventário gerencia o CUSTO (Remove o item)
		hotbar[equippedSlot] = nil
		PlayerEquipped[player.UserId] = nil 

		-- 2. O Inventário avisa: "O item foi usado, apliquem os efeitos!"
		-- Note que mandamos "UseItem" em vez de "Unequip"
		CombatEvent:Fire("UseItem", player, itemName)

		SendUpdate(player) 

	elseif data.Type == "Weapon" then
		-- Arma atacando (Futuro)
		print(player.Name .. " tentou atacar com " .. itemName)
	end
end)