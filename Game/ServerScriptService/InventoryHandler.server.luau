local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

print(">>> SERVER: InventoryHandler (Hybrid System) Iniciado")

-- Módulos
local DataFolder = ReplicatedStorage:WaitForChild("Data")
local ItemData = require(DataFolder:WaitForChild("ItemData"))

-- Remotes
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

-- Eventos Internos
local ServerEvents = ServerStorage:FindFirstChild("ServerEvents") or Instance.new("Folder", ServerStorage)
ServerEvents.Name = "ServerEvents"
local CombatEvent = ServerEvents:FindFirstChild("CombatSystem") or Instance.new("BindableEvent", ServerEvents)
CombatEvent.Name = "CombatSystem"

-- Dados dos Jogadores
local PlayerInventories = {} 
local PlayerHotbars = {}    
local PlayerEquipped = {} 

-- CONTROLE DE ESTADO
local PlayerBusy = {} -- Bloqueio RÍGIDO (Task.wait)
local PlayerSpamCheck = {} -- Bloqueio LEVE (Timestamp) para não crashar a rede

-- Configuração
local HEAVY_WAIT = 0.8 -- Tempo travado para armas
local SPAM_LIMIT = 0.05 -- Limite técnico de rede (20 cliques/segundo máx)

-- ============================================================================
-- FUNÇÕES AUXILIARES
-- ============================================================================

local function IsHeavyItem(itemName)
	if not itemName then return false end
	local data = ItemData.Get(itemName)
	return (data and data.Type == "Weapon") 
end

local function SendUpdate(player)
	UpdateInvEvent:FireClient(player, {
		Backpack = PlayerInventories[player.UserId] or {},
		Hotbar = PlayerHotbars[player.UserId] or {},
		EquippedSlot = PlayerEquipped[player.UserId] 
	})
end

-- ============================================================================
-- SETUP
-- ============================================================================
local function SetupPlayer(player)
	if PlayerInventories[player.UserId] then return end

	PlayerInventories[player.UserId] = {
		"Caladbolg", 
		"Poção de Cura", 
		"Poção de Cura",
		"Espada de Ferro"
	} 

	PlayerHotbars[player.UserId] = {}
	PlayerEquipped[player.UserId] = nil
	PlayerBusy[player.UserId] = false
	PlayerSpamCheck[player.UserId] = 0

	task.wait(1)
	SendUpdate(player)
end

Players.PlayerAdded:Connect(SetupPlayer)
for _, player in ipairs(Players:GetPlayers()) do SetupPlayer(player) end

Players.PlayerRemoving:Connect(function(player)
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
	PlayerBusy[player.UserId] = nil
	PlayerSpamCheck[player.UserId] = nil
end)

-- ============================================================================
-- MOVIMENTAÇÃO
-- ============================================================================
MoveItemEvent.OnServerEvent:Connect(function(player, itemName, targetSlot, sourceType, sourceIndex)
	if PlayerBusy[player.UserId] then return end -- Não mexe se estiver travado em arma

	local backpack = PlayerInventories[player.UserId]
	local hotbar = PlayerHotbars[player.UserId]
	if not backpack then return end

	targetSlot = tostring(targetSlot)
	sourceIndex = (sourceType == "Hotbar") and tostring(sourceIndex) or tonumber(sourceIndex)
	local currentEquipped = PlayerEquipped[player.UserId]

	local function CheckUnequip(slotMexido)
		if tostring(currentEquipped) == tostring(slotMexido) then
			PlayerEquipped[player.UserId] = nil
			CombatEvent:Fire("Unequip", player, itemName)
		end
	end

	if sourceType == "Backpack" and targetSlot ~= "Backpack" then
		if backpack[sourceIndex] == itemName then
			CheckUnequip(targetSlot) 
			local oldItem = hotbar[targetSlot]
			hotbar[targetSlot] = itemName
			table.remove(backpack, sourceIndex)
			if oldItem then table.insert(backpack, oldItem) end
		end
	elseif sourceType == "Hotbar" and targetSlot ~= "Backpack" then
		local temp = hotbar[targetSlot]
		hotbar[targetSlot] = hotbar[sourceIndex]
		hotbar[sourceIndex] = temp
		if tostring(currentEquipped) == sourceIndex then
			PlayerEquipped[player.UserId] = targetSlot
		elseif tostring(currentEquipped) == targetSlot then
			PlayerEquipped[player.UserId] = sourceIndex
		end
	elseif sourceType == "Hotbar" and targetSlot == "Backpack" then
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
-- EQUIPAR (A Lógica Híbrida)
-- ============================================================================
EquipEvent.OnServerEvent:Connect(function(player, slotNumber)
	-- 1. CHECAGEM RÍGIDA: Se já estiver travado (por causa de uma arma), ignora TUDO.
	if PlayerBusy[player.UserId] then 
		return 
	end

	-- 2. CHECAGEM DE SPAM LEVE: Evita crash de rede, mas permite switch rápido
	local now = os.clock()
	local lastOp = PlayerSpamCheck[player.UserId] or 0
	if (now - lastOp) < SPAM_LIMIT then return end
	PlayerSpamCheck[player.UserId] = now

	-- Lógica padrão
	local hotbar = PlayerHotbars[player.UserId]
	local slotString = tostring(slotNumber)
	local targetItemName = hotbar[slotString] 

	if not targetItemName then return end

	local currentSlot = PlayerEquipped[player.UserId]
	local currentItemName = currentSlot and hotbar[currentSlot]

	-- 3. VERIFICA SE DEVEMOS TRAVAR O SERVIDOR
	-- Só travamos se uma ARMA estiver envolvida (saindo ou entrando)
	local needsLock = IsHeavyItem(currentItemName) or IsHeavyItem(targetItemName)

	-- Se precisar travar, ativamos a flag AGORA
	if needsLock then
		PlayerBusy[player.UserId] = true
	end

	-- Executa a Troca
	if currentSlot == slotString then
		-- Desequipar
		PlayerEquipped[player.UserId] = nil
		CombatEvent:Fire("Unequip", player, targetItemName)
	else
		-- Equipar
		if currentSlot then
			local oldItem = hotbar[currentSlot]
			if oldItem then
				CombatEvent:Fire("Unequip", player, oldItem)
			end
		end
		PlayerEquipped[player.UserId] = slotString
		CombatEvent:Fire("Equip", player, targetItemName)
	end

	SendUpdate(player)

	-- 4. APLICA A ESPERA (Task.Wait) SOMENTE SE NECESSÁRIO
	if needsLock then
		-- Se for arma, o script "dorme" aqui e ignora inputs no passo 1
		task.wait(HEAVY_WAIT)
		PlayerBusy[player.UserId] = false
	end

	-- Se não for arma (Poção -> Poção), o script termina aqui instantaneamente
	-- e libera o jogador para apertar outro botão no próximo frame.
end)

-- ============================================================================
-- USAR ITEM
-- ============================================================================
UseItemEvent.OnServerEvent:Connect(function(player)
	if PlayerBusy[player.UserId] then return end -- Não pode beber se estiver sacando espada

	local equippedSlot = PlayerEquipped[player.UserId]
	if not equippedSlot then return end 

	local hotbar = PlayerHotbars[player.UserId]
	local itemName = hotbar[equippedSlot]
	if not itemName then return end

	local data = ItemData.Get(itemName)
	if not data then return end

	if data.Type == "Consumable" then
		-- Trava mínima para consumo (não precisa de lock global pesado)
		local now = os.clock()
		local lastOp = PlayerSpamCheck[player.UserId] or 0
		if (now - lastOp) < 0.15 then return end
		PlayerSpamCheck[player.UserId] = now

		hotbar[equippedSlot] = nil
		PlayerEquipped[player.UserId] = nil 
		CombatEvent:Fire("UseItem", player, itemName)
		SendUpdate(player) 

	elseif data.Type == "Weapon" then
		print(player.Name .. " tentou atacar com " .. itemName)
	end
end)