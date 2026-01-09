local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

local DataFolder = ReplicatedStorage:WaitForChild("Data")
local ItemData = require(DataFolder:WaitForChild("ItemData"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local UpdateInvEvent = Remotes:WaitForChild("UpdateInventory")
local EquipEvent = Remotes:WaitForChild("EquipItem")
local MoveItemEvent = Remotes:WaitForChild("MoveItem")
local ToggleCombatEvent = Remotes:WaitForChild("ToggleCombat")
local UpdateStatsEvent = Remotes:WaitForChild("UpdateStats") -- Novo

-- Referências de UI
local InventoryScreenGUI = script.Parent
local MainBackground = InventoryScreenGUI:WaitForChild("InventoryBackground")
local StatusFrame = InventoryScreenGUI:WaitForChild("Status") -- [FIX] Agora busca direto na GUI principal
local InfosFrame = StatusFrame:WaitForChild("Infos")
local PlayerNameLabel = StatusFrame:WaitForChild("Player")
local LevelLabel = InfosFrame:WaitForChild("Level"):WaitForChild("Value")
local XPLabel = InfosFrame:WaitForChild("XP"):WaitForChild("Value")
local DefenseLabel = InfosFrame:WaitForChild("Defense"):WaitForChild("Value")
local DamageLabel = InfosFrame:WaitForChild("Attack"):WaitForChild("Value")
local CritLabel = InfosFrame:WaitForChild("Crit"):WaitForChild("Value") -- Verifique se o nome é "Crit" ou "CritChance" na UI

UpdateStatsEvent.OnClientEvent:Connect(function(stats)
	PlayerNameLabel.Text = Players.LocalPlayer.Name
	LevelLabel.Text = "Lv. " .. tostring(stats.Level)
	if stats.MaxXP then
		XPLabel.Text = tostring(stats.XP) .. " / " .. tostring(stats.MaxXP)
	end

	DefenseLabel.Text = tostring(stats.Defense)
	DamageLabel.Text = tostring(stats.Damage)
	CritLabel.Text = tostring(stats.CritChance) .. "%"
end)
local BackpackFrame = MainBackground:WaitForChild("ScrollingFrame")
-- local BackpackTemplate = BackpackFrame:WaitForChild("ItemTemplate") -- Antigo
-- Agora usamos um template unificado (O da Hotbar é mais completo, pois tem Hotkey)

local HotbarGui = InventoryScreenGUI:WaitForChild("Hotbar")
local SharedItemTemplate = HotbarGui:WaitForChild("ItemTemplate") 
local SlotFixoTemplate = HotbarGui:WaitForChild("SlotFixo") 

-- Configuração Inicial: Garante que o template mestre esteja invisível
SharedItemTemplate.Visible = false
SlotFixoTemplate.Visible = false 

local BackgroundContainer = InventoryScreenGUI:WaitForChild("Background")
local SlotsItemsFrame = InventoryScreenGUI:WaitForChild("SlotsItems") 

-- Item Info UI References
local ItemInfoFrame = InventoryScreenGUI:WaitForChild("ItemInfo")
local InfoName = ItemInfoFrame:WaitForChild("Name")
local InfoDesc = ItemInfoFrame:WaitForChild("Desc")
local InfoRarity = ItemInfoFrame:WaitForChild("Rarity")
local Info3D = ItemInfoFrame:WaitForChild("Item3d")
local InfoStatsFrame = ItemInfoFrame:WaitForChild("Infos")
-- Captura o template de texto existente (se houver) para usar nos stats
local StatTemplate = InfoStatsFrame:FindFirstChildOfClass("TextLabel")
if StatTemplate then
	StatTemplate.Visible = false
	StatTemplate.Name = "StatTemplate"
end

-- [REMOVIDO] Usuário já ajustou no Explorer
-- ItemInfoFrame.Size = UDim2.fromOffset(250, 300)

-- Mapeamento dos Botões de Equipamento
local EquipmentSlots = {
	Weapon = SlotsItemsFrame:WaitForChild("Weapon"),
	Armor = SlotsItemsFrame:WaitForChild("Armor"),
	Helm = SlotsItemsFrame:WaitForChild("Helm"),
	OffHand = SlotsItemsFrame:WaitForChild("OffHand"),
	Ring1 = SlotsItemsFrame:WaitForChild("Ring1"),
	Ring2 = SlotsItemsFrame:WaitForChild("Ring2"),
	Neck = SlotsItemsFrame:WaitForChild("Neck"),
	Boots = SlotsItemsFrame:WaitForChild("Boots"),
	Gloves = SlotsItemsFrame:WaitForChild("Gloves"),
}

local InitialSlotImages = {}
for name, btn in pairs(EquipmentSlots) do
	if btn:IsA("ImageButton") or btn:IsA("ImageLabel") then
		InitialSlotImages[name] = btn.Image
	end
end

-- [SETUP DO BLUR]
local InventoryBlur = Lighting:FindFirstChild("InventoryBlur") or Instance.new("BlurEffect")
InventoryBlur.Name = "InventoryBlur"
InventoryBlur.Size = 0
InventoryBlur.Enabled = false
InventoryBlur.Parent = Lighting

-- Configurações de Animação
local OriginalPos = MainBackground.Position 
local HiddenPos = UDim2.new(-0.8, 0, OriginalPos.Y.Scale, OriginalPos.Y.Offset) 

-- Declaração Antecipada
local UpdateHotbarUI, UpdateBackpackUI, UpdateGearUI -- Novo UpdateGearUI 

-- Setup Inicial
SharedItemTemplate.Visible = false
SlotFixoTemplate.Visible = false 
MainBackground.Position = HiddenPos 
MainBackground.Visible = false 

BackgroundContainer.Visible = false
for _, child in pairs(BackgroundContainer:GetChildren()) do
	if child:IsA("ImageLabel") or child:IsA("ImageButton") then
		child.ImageTransparency = 1
	end
end

-- Esconde tudo exceto o background inicial (se houver)
for _, child in pairs(InventoryScreenGUI:GetChildren()) do
	if child:IsA("GuiObject") and child ~= MainBackground and child ~= HotbarGui and child ~= BackgroundContainer and child ~= SlotsItemsFrame and child ~= ItemInfoFrame then
		child.Visible = false
	end
end
SlotsItemsFrame.Visible = false -- Começa invisível junto com inventário

-- Variáveis de Estado
local CurrentInventoryData = { Backpack = {}, Hotbar = {}, EquippedSlot = nil, Gear = {} } -- Gear adicionado
local draggingItemName, draggingSourceIndex, draggingSourceType, dragGhost = nil, nil, nil, nil
local lastDragTime = 0 
local inventoryOpen = false
local isAnimating = false 

-- ============================================================================
-- FUNÇÕES ÚTEIS
-- ============================================================================

local function ClearUI(container)
	for _, child in pairs(container:GetChildren()) do
		-- Ignora o Template Compartilhado (se ele estiver dentro do container que estamos limpando, ex HotbarGui)
		-- E ignora templates antigos se ainda existirem lá
		if child:IsA("GuiObject") and child ~= SharedItemTemplate and child.Name ~= "ItemTemplate" and child ~= SlotFixoTemplate and child.Name ~= "DragGhost" then
			child:Destroy()
		end
	end
end

local function GetAdjustedMouseLocation()
	local mousePos = UserInputService:GetMouseLocation()
	if not InventoryScreenGUI.IgnoreGuiInset then
		local inset = GuiService:GetGuiInset()
		return Vector2.new(mousePos.X, mousePos.Y - inset.Y)
	end
	return mousePos
end

local function IsMouseOverFrame(frame)
	if not frame or not frame.Parent or not frame:IsA("GuiObject") then return false end
	local mousePos = UserInputService:GetMouseLocation()
	local inset = GuiService:GetGuiInset()
	local mouseX = mousePos.X
	local mouseY = mousePos.Y - inset.Y
	local absPos = frame.AbsolutePosition
	local absSize = frame.AbsoluteSize 
	return (mouseX >= absPos.X) and (mouseX <= absPos.X + absSize.X) and (mouseY >= absPos.Y) and (mouseY <= absPos.Y + absSize.Y)
end

-- ============================================================================
-- INFO DISPLAY SYSTEM
-- ============================================================================
-- Variável para guardar conexão de rotação do modelo 3D
local previewRotationConnection 

local function Setup3DPreview(model, viewport)
	viewport:ClearAllChildren()
	if previewRotationConnection then previewRotationConnection:Disconnect() end
	if not model then return end

	-- 1. CLONE & CENTER MODEL
	local clone = model:Clone()

	-- [USER REQUEST] "Zera position e orientation do item"
	-- Move para a origem absoluta (0,0,0) com rotação zerada (Identity)
	clone:PivotTo(CFrame.new(0, 0, 0))
	clone.Parent = viewport

	-- 2. SETUP CAMERA
	local camera = Instance.new("Camera")
	camera.FieldOfView = 40 
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	-- [USER REQUEST] "Position: -2.5, 0, 10 | Orientation: 0, 0, -45"
	-- Nota: Se os itens tiverem tamanhos muito diferentes, pode ser necessário multiplicar essa posição por um Fator de Escala (maxDim)
	-- Por enquanto, seguindo valores exatos do usuário.
	camera.CFrame = CFrame.new(-2.5, 0, 10) * CFrame.Angles(0, 0, math.rad(-45))

	-- 3. ILUMINAÇÃO
	local light = Instance.new("PointLight")
	light.Parent = viewport
	light.Brightness = 3
	light.Range = 20
	light.Position = camera.CFrame.Position -- Luz acompanha a câmera

	viewport.LightColor = Color3.new(1, 1, 1)
	viewport.Ambient = Color3.fromRGB(150, 150, 150)

	-- 4. ROTAÇÃO
	-- [USER REQUEST] "Zera orientation do item" (Implícito que não deve girar)
	-- Se quiser voltar a girar, descomente abaixo e considere girar A CÂMERA em vez do item para manter o ângulo relativo.
	-- previewRotationConnection = RunService.RenderStepped:Connect(function(dt) ... end)
end

local tooltipConnection 

local function UpdateItemInfo(itemData)
	-- Limpa conexão anterior se existir
	if tooltipConnection then 
		tooltipConnection:Disconnect() 
		tooltipConnection = nil
	end
	if previewRotationConnection then 
		previewRotationConnection:Disconnect() 
		previewRotationConnection = nil
	end

	if not itemData then
		ItemInfoFrame.Visible = false
		return
	end

	-- 1. POPULAR DADOS (Prepara o Layout)
	InfoName.Text = itemData.Name
	InfoDesc.Text = itemData.Description or "Sem descrição."

	local rarityColors = {
		Legendary = Color3.fromRGB(255, 170, 0),
		Rare = Color3.fromRGB(0, 170, 255),
		Common = Color3.fromRGB(200, 200, 200)
	}
	InfoRarity.BackgroundColor3 = rarityColors[itemData.Rarity] or rarityColors.Common

	InfoRarity.BackgroundColor3 = rarityColors[itemData.Rarity] or rarityColors.Common

	-- 3D Preview (Protected Call para não quebrar UI se o modelo falhar)
	task.spawn(function()
		pcall(function() Setup3DPreview(itemData.Model, Info3D) end)
	end)

	-- 2. SETUP STATS (Pode alterar o tamanho do frame se tiver AutomaticSize)
	if not InfoStatsFrame:FindFirstChildOfClass("UIListLayout") then
		local layout = Instance.new("UIListLayout")
		layout.Parent = InfoStatsFrame
		layout.SortOrder = Enum.SortOrder.LayoutOrder
	end

	for _, child in pairs(InfoStatsFrame:GetChildren()) do
		if child:IsA("TextLabel") and child ~= StatTemplate then child:Destroy() end
	end

	local function AddStat(label, value)
		local txt
		if StatTemplate then 
			txt = StatTemplate:Clone()
		else
			txt = Instance.new("TextLabel")
			txt.Size = UDim2.new(1, 0, 0, 20)
			txt.BackgroundTransparency = 1
			txt.TextColor3 = Color3.new(1, 1, 1)
			txt.Font = Enum.Font.SourceSans
			txt.TextSize = 14
			txt.TextXAlignment = Enum.TextXAlignment.Left
		end
		txt.Name = "Stat_" .. label
		txt.Text = label .. ": " .. tostring(value)
		txt.Parent = InfoStatsFrame
		txt.Visible = true
	end

	if itemData.Damage then AddStat("Dano", itemData.Damage) end
	if itemData.Defense then AddStat("Defesa", itemData.Defense) end
	if itemData.HealAmount then AddStat("Cura", itemData.HealAmount) end
	if itemData.Weight then AddStat("Peso", itemData.Weight) end

	-- 3. [CORREÇÃO] POSICIONAMENTO IMEDIATO
	-- Define a função de update para usar agora e no loop
	local function UpdatePos()
		local mousePos = GetAdjustedMouseLocation()
		local screenSize = InventoryScreenGUI.AbsoluteSize
		local frameSize = ItemInfoFrame.AbsoluteSize

		local x = mousePos.X + 15
		local y = mousePos.Y + 15
		if (x + frameSize.X) > screenSize.X then x = mousePos.X - frameSize.X - 5 end
		if (y + frameSize.Y) > screenSize.Y then y = mousePos.Y - frameSize.Y - 5 end
		ItemInfoFrame.Position = UDim2.fromOffset(x, y)
	end

	UpdatePos() -- Chama uma veZ ANTES de ficar visível (Evita piscar no lugar errado)

	-- 4. EXIBIR E INICIAR LOOP
	ItemInfoFrame.Visible = true
	tooltipConnection = RunService.RenderStepped:Connect(UpdatePos)
end

local function ApplyIconData(itemFrame, itemInfo)
	local icon = itemFrame:FindFirstChild("Icon") or itemFrame 
	if itemFrame:IsA("ImageButton") then icon = itemFrame end
	if icon:IsA("ImageButton") or icon:IsA("ImageLabel") then
		if itemInfo.Icon and itemInfo.Icon ~= "" then
			icon.Image = itemInfo.Icon
			icon.ImageTransparency = 0
			icon.BackgroundTransparency = 0
		else
			icon.Image = ""
			icon.ImageTransparency = 1
			icon.BackgroundTransparency = 1
		end
	end
end

-- ============================================================================
-- SIMULAÇÃO LOCAL (PREVISÃO)
-- ============================================================================
local function SimularMovimentoLocal(nomeItem, slotAlvo, tipoOrigem, idxOrigem)
	local hotbar = CurrentInventoryData.Hotbar
	local backpack = CurrentInventoryData.Backpack
	local targetKey = tostring(slotAlvo)
	local sourceKey = tostring(idxOrigem)

	if tipoOrigem == "Hotbar" and type(slotAlvo) == "number" then
		local itemAlvo = hotbar[targetKey]
		local itemOrigem = hotbar[sourceKey]
		hotbar[targetKey] = itemOrigem
		hotbar[sourceKey] = itemAlvo
	elseif tipoOrigem == "Backpack" and type(slotAlvo) == "number" then
		if backpack[tonumber(idxOrigem)] == nomeItem then
			local itemExistente = hotbar[targetKey]
			hotbar[targetKey] = nomeItem
			table.remove(backpack, tonumber(idxOrigem))
			if itemExistente then table.insert(backpack, itemExistente) end
		end
	elseif slotAlvo == "Backpack" and tipoOrigem == "Hotbar" then
		local itemRemover = hotbar[sourceKey]
		if itemRemover then
			hotbar[sourceKey] = nil
			table.insert(backpack, itemRemover)
		end
	elseif type(slotAlvo) == "string" and string.sub(slotAlvo, 1, 13) == "SwapBackpack_" then
		local targetIdx = tonumber(string.sub(slotAlvo, 14))
		if tipoOrigem == "Backpack" then
			local sourceIdx = tonumber(idxOrigem)
			local itemSource = backpack[sourceIdx]
			local itemTarget = backpack[targetIdx]
			if itemSource and itemTarget then
				backpack[sourceIdx] = itemTarget
				backpack[targetIdx] = itemSource
			end
		elseif tipoOrigem == "Hotbar" then
			local itemHotbar = hotbar[sourceKey]
			local itemBackpack = backpack[targetIdx]
			if itemHotbar then
				hotbar[sourceKey] = itemBackpack 
				backpack[targetIdx] = itemHotbar 
			end
		end
	end
end

-- ============================================================================
-- DRAG SYSTEM
-- ============================================================================
local function SetupDrag(itemFrame, itemName, sourceType, sourceIndex)
	local detector = itemFrame:FindFirstChild("DragDetector")
	if not detector then return end
	detector.DragStyle = Enum.UIDragDetectorDragStyle.Scriptable
	detector.Enabled = inventoryOpen 

	detector.DragStart:Connect(function()
		if not inventoryOpen then return end 

		if dragGhost then dragGhost:Destroy() end
		draggingItemName, draggingSourceType, draggingSourceIndex = itemName, sourceType, sourceIndex

		dragGhost = itemFrame:Clone()
		dragGhost.Name = "DragGhost"
		dragGhost.Size = UDim2.fromScale(0.1, 0.1) 
		dragGhost.AnchorPoint = Vector2.new(0.5, 0.5) 
		dragGhost.Active = false
		dragGhost.ZIndex = 300 

		for _, v in pairs(dragGhost:GetDescendants()) do
			if v:IsA("UIDragDetector") or v:IsA("Script") then v:Destroy() end
			if v:IsA("GuiObject") then v.ZIndex = 301 end 
		end
		if dragGhost:FindFirstChild("DragDetector") then dragGhost.DragDetector:Destroy() end

		local startPos = GetAdjustedMouseLocation()
		dragGhost.Position = UDim2.fromOffset(startPos.X, startPos.Y)
		dragGhost.Parent = InventoryScreenGUI
		dragGhost.Visible = true 

		itemFrame.BackgroundTransparency = 1
		if itemFrame:IsA("ImageButton") then itemFrame.ImageTransparency = 1 end

		for _, child in pairs(itemFrame:GetChildren()) do 
			if child:IsA("GuiObject") then child.Visible = false end 
		end

		if sourceType == "Hotbar" then
			local placeholder = SlotFixoTemplate:Clone()
			placeholder.Name = "TempPlaceholder"
			placeholder.AnchorPoint = Vector2.new(0, 0) 
			placeholder.Position = UDim2.new(0, 0, 0, 0)
			placeholder.Size = UDim2.new(1, 0, 1, 0) 
			placeholder.ZIndex = itemFrame.ZIndex 
			placeholder.Visible = true
			placeholder.Parent = itemFrame 

			for _, child in pairs(placeholder:GetChildren()) do
				if child:IsA("UIDragDetector") or child:IsA("Script") then child:Destroy() end
			end
		end
	end)

	detector.DragContinue:Connect(function()
		if dragGhost then
			local mousePos = GetAdjustedMouseLocation()
			dragGhost.Position = UDim2.fromOffset(mousePos.X, mousePos.Y)
		end
	end)

	detector.DragEnd:Connect(function()
		lastDragTime = tick()

		if itemFrame and itemFrame.Parent then 
			local placeholder = itemFrame:FindFirstChild("TempPlaceholder")
			if placeholder then placeholder:Destroy() end

			-- [CORREÇÃO] Em vez de restaurar cegamente (o que ativa frames errados),
			-- recarrega a UI da origem para garantir estado limpo.
			if sourceType == "Backpack" then UpdateBackpackUI()
			elseif sourceType == "Hotbar" then UpdateHotbarUI()
			elseif sourceType == "Gear" then UpdateGearUI()
			end
		end 

		if dragGhost then dragGhost:Destroy() dragGhost = nil end
		if not draggingItemName then return end

		local foundHotbarSlot = nil
		for _, child in pairs(HotbarGui:GetChildren()) do
			if child:IsA("GuiObject") and child.Visible and IsMouseOverFrame(child) then
				local slotNum = string.match(child.Name, "Slot_(%d+)")
				if slotNum then foundHotbarSlot = tonumber(slotNum) break end
			end
		end

		local droppedOnBackpack = IsMouseOverFrame(BackpackFrame) or IsMouseOverFrame(MainBackground)
		local targetBackpackIndex = nil
		if droppedOnBackpack then
			for _, child in pairs(BackpackFrame:GetChildren()) do
				if child:IsA("GuiObject") and child.Visible and IsMouseOverFrame(child) then
					local idx = child:GetAttribute("Index")
					if idx then targetBackpackIndex = idx break end
				end
			end
		end

		-- Checa Slots de Equipamento (GEAR)
		local foundGearSlot = nil
		if inventoryOpen then
			for slotName, slotFrame in pairs(EquipmentSlots) do
				if IsMouseOverFrame(slotFrame) then
					foundGearSlot = slotName
					break
				end
			end
		end

		if foundHotbarSlot then
			SimularMovimentoLocal(draggingItemName, foundHotbarSlot, draggingSourceType, draggingSourceIndex)
			UpdateBackpackUI()
			UpdateHotbarUI()
			MoveItemEvent:FireServer(draggingItemName, foundHotbarSlot, draggingSourceType, draggingSourceIndex) 
		elseif foundGearSlot then
			-- Dropou num slot de equipamento
			-- Verificação básica local (idealmente o servidor valida, mas aqui dá feedback imediato se der, ou espera)
			local itemData = ItemData.Get(draggingItemName)
			if itemData and itemData.SlotType == foundGearSlot then
				-- Move
				MoveItemEvent:FireServer(draggingItemName, foundGearSlot, draggingSourceType, draggingSourceIndex)
				-- Não simulamos Gear localmente complexo agora, esperamos resposta do servidor para atualizar visual Gear
			end
		elseif droppedOnBackpack then
			if targetBackpackIndex then
				-- Evita swap inútil (mesmo lugar)
				if draggingSourceType == "Backpack" and tonumber(targetBackpackIndex) == tonumber(draggingSourceIndex) then
					draggingItemName = nil
					-- Restaura visual
					if itemFrame then for _, c in pairs(itemFrame:GetChildren()) do if c:IsA("GuiObject") then c.Visible = true end end end
					return 
				end

				local swapCommand = "SwapBackpack_"..targetBackpackIndex
				SimularMovimentoLocal(draggingItemName, swapCommand, draggingSourceType, draggingSourceIndex)
				UpdateBackpackUI()
				UpdateHotbarUI()
				MoveItemEvent:FireServer(draggingItemName, swapCommand, draggingSourceType, draggingSourceIndex)
			else
				if draggingSourceType == "Hotbar" or draggingSourceType == "Gear" then
					SimularMovimentoLocal(draggingItemName, "Backpack", "Hotbar", draggingSourceIndex) -- Simula como Hotbar->Backpack genérico (funciona visualmente pra Gear tb se não tiver lógica específica, pois redesenha tudo)
					UpdateBackpackUI()
					UpdateHotbarUI()
					UpdateGearUI()
					MoveItemEvent:FireServer(draggingItemName, "Backpack", draggingSourceType, draggingSourceIndex)
				end
			end
		end
		draggingItemName = nil
	end)
end

local function SetDragEnabled(enabled)
	for _, child in pairs(HotbarGui:GetChildren()) do
		local detector = child:FindFirstChild("DragDetector")
		if detector then detector.Enabled = enabled end
	end
	for _, child in pairs(BackpackFrame:GetChildren()) do
		local detector = child:FindFirstChild("DragDetector")
		if detector then detector.Enabled = enabled end
	end
	-- Habilita drag nos slots de equipamento
	for slotName, slotBtn in pairs(EquipmentSlots) do
		-- O item visual é filho do slotBtn
		local visual = slotBtn:FindFirstChild("EquippedItemVisual")
		if visual then
			local detector = visual:FindFirstChild("DragDetector")
			if detector then detector.Enabled = enabled end
		end
	end
end

-- ============================================================================
-- ATUALIZAÇÃO DA UI (COM ZOOM + CLIQUE CORRIGIDO)
-- ============================================================================

function UpdateHotbarUI()
	ClearUI(HotbarGui)

	local listLayout = HotbarGui:FindFirstChildOfClass("UIListLayout")
	if listLayout then 
		listLayout.SortOrder = Enum.SortOrder.LayoutOrder 
		listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		listLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	end

	-- Configuração dos Tamanhos
	local SIZE_NORMAL = UDim2.fromOffset(50, 50)
	local SIZE_EQUIPPED = UDim2.fromOffset(60, 60)

	for i = 1, 10 do
		local item = CurrentInventoryData.Hotbar[tostring(i)] or CurrentInventoryData.Hotbar[i] -- item é {Name, Amount}
		local isEquipped = (tostring(CurrentInventoryData.EquippedSlot) == tostring(i))

		if item then
			-- >>> CORREÇÃO: Usando .Get() aqui também
			local itemInfo = ItemData.Get(item.Name)

			if itemInfo then
				local newItem = SharedItemTemplate:Clone()
				newItem.Name = "Slot_" .. i 
				newItem.LayoutOrder = i
				newItem.Visible = true
				ApplyIconData(newItem, itemInfo)
				if newItem:FindFirstChild("ItemName") then newItem.ItemName.Text = itemInfo.Name end

				-- HOTBAR: Mostra Hotkey
				if newItem:FindFirstChild("Hotkey") then 
					newItem.Hotkey.Text = tostring(i % 10) 
					newItem.Hotkey.Visible = true
				end

				if newItem:FindFirstChild("Qtd") then 
					if itemInfo.Stackable and item.Amount > 1 then
						newItem.Qtd.Text = "x"..tostring(item.Amount)
						newItem.Qtd.Visible = true
					else
						newItem.Qtd.Visible = false
					end
				end 

				if isEquipped then
					newItem.Size = SIZE_EQUIPPED
					newItem.ZIndex = 10 
					for _, v in pairs(newItem:GetChildren()) do 
						if v:IsA("GuiObject") then v.ZIndex = 11 end
					end
				else
					newItem.Size = SIZE_NORMAL
					newItem.ZIndex = 1
					for _, v in pairs(newItem:GetChildren()) do 
						if v:IsA("GuiObject") then v.ZIndex = 2 end
					end
				end

				newItem.InputEnded:Connect(function(input)
					if input.UserInputType == Enum.UserInputType.MouseButton1 then
						if (tick() - lastDragTime > 0.2) and (not dragGhost) then
							EquipEvent:FireServer(i)
						end
					end
				end)

				newItem.Parent = HotbarGui
				SetupDrag(newItem, item.Name, "Hotbar", i)

				-- Hover Events
				newItem.MouseEnter:Connect(function() UpdateItemInfo(itemInfo) end)
				newItem.MouseLeave:Connect(function() UpdateItemInfo(nil) end)
			end
		elseif inventoryOpen then
			local emptySlot = SlotFixoTemplate:Clone()
			emptySlot.Name = "Slot_" .. i 
			emptySlot.LayoutOrder = i
			emptySlot.Visible = true
			if emptySlot:FindFirstChild("Hotkey") then emptySlot.Hotkey.Text = tostring(i % 10) end

			if isEquipped then
				-- CORREÇÃO: Se estiver vazio mas marcado como equipado (erro de estado), reseta visual
				-- Mas idealmente não deve ser possível selecionar vazio.
				-- Vamos manter o tamanho normal se vazio para não "ficar grandinho" indevidamente
				emptySlot.Size = SIZE_NORMAL 
				emptySlot.ZIndex = 1
				for _, v in pairs(emptySlot:GetChildren()) do 
					if v:IsA("GuiObject") then v.ZIndex = 2 end 
				end
			else
				emptySlot.Size = SIZE_NORMAL
				emptySlot.ZIndex = 1
				for _, v in pairs(emptySlot:GetChildren()) do 
					if v:IsA("GuiObject") then v.ZIndex = 2 end 
				end
			end

			emptySlot.InputEnded:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1 then
					-- CORREÇÃO: Não faz nada se clicar em slot vazio
				end
			end)

			emptySlot.Parent = HotbarGui
		end
	end
end

-- ============================================================================
-- SEARCH SYSTEM
-- ============================================================================
local SearchFrame = MainBackground:WaitForChild("Search")
local SearchBox = SearchFrame:WaitForChild("TextBox")
local PLACEHOLDER = "Search"
currentSearchText = "" 

-- Setup Inicial do Texto
if SearchBox.Text == "" then SearchBox.Text = PLACEHOLDER end

SearchBox.Focused:Connect(function()
	if SearchBox.Text == PLACEHOLDER then
		SearchBox.Text = ""
	end
end)

SearchBox.FocusLost:Connect(function()
	if SearchBox.Text == "" then
		SearchBox.Text = PLACEHOLDER
	end
end)

SearchBox:GetPropertyChangedSignal("Text"):Connect(function()
	local text = SearchBox.Text
	-- Se o texto for o placeholder, consideramos busca vazia
	if text == PLACEHOLDER then
		currentSearchText = ""
	else
		currentSearchText = string.lower(text)
	end
	UpdateBackpackUI()
end)

function UpdateBackpackUI()
	ClearUI(BackpackFrame)
	local gridLayout = BackpackFrame:FindFirstChildOfClass("UIGridLayout")
	if gridLayout then gridLayout.SortOrder = Enum.SortOrder.LayoutOrder end
	for i, item in ipairs(CurrentInventoryData.Backpack) do
		local data = ItemData.Get(item.Name)
		if data then
			-- FILTRO DE CATEGORIA & BUSCA
			local showItem = false
			local cat = currentCategory or "All" 

			-- 1. Checa Categoria
			local matchesCategory = false
			if cat == "All" then matchesCategory = true
			elseif cat == "Weapons" and data.Type == "Weapon" then matchesCategory = true
			elseif cat == "Equipments" and data.Type == "Equipment" then matchesCategory = true
			elseif cat == "Consumables" and data.Type == "Consumable" then matchesCategory = true
			elseif cat == "Misc" then
				if data.Type ~= "Weapon" and data.Type ~= "Equipment" and data.Type ~= "Consumable" then
					matchesCategory = true
				end
			end

			-- 2. Checa Busca (Se passou na categoria)
			if matchesCategory then
				if currentSearchText == "" then
					showItem = true
				else
					-- Busca Case Insensitive no Nome
					if string.find(string.lower(data.Name), currentSearchText) then
						showItem = true
					end
				end
			end

			if showItem then
				local newItem = SharedItemTemplate:Clone()
				newItem.Name = data.Name
				newItem:SetAttribute("Index", i)
				newItem.Visible = true
				newItem.LayoutOrder = i
				ApplyIconData(newItem, data)
				if newItem:FindFirstChild("ItemName") then newItem.ItemName.Text = data.Name end

				-- BACKPACK: Esconde Hotkey
				if newItem:FindFirstChild("Hotkey") then newItem.Hotkey.Visible = false end

				if newItem:FindFirstChild("Qtd") then 
					if data.Stackable and item.Amount > 1 then
						newItem.Qtd.Text = "x"..tostring(item.Amount)
						newItem.Qtd.Visible = true
					else
						newItem.Qtd.Visible = false
					end
				end 

				newItem.Parent = BackpackFrame
				SetupDrag(newItem, item.Name, "Backpack", i)

				-- Hover Events
				newItem.MouseEnter:Connect(function() UpdateItemInfo(data) end)
				newItem.MouseLeave:Connect(function() UpdateItemInfo(nil) end)
			end -- Fim do if showItem
		end
	end
end

function UpdateGearUI()
	local gearData = CurrentInventoryData.Gear or {}

	for slotName, slotBtn in pairs(EquipmentSlots) do
		local item = gearData[slotName] -- item é {Name, Amount}
		local itemName = item and item.Name 

		-- Limpa item visual anterior (filho chamado "EquippedItemVisual")
		local oldVisual = slotBtn:FindFirstChild("EquippedItemVisual")
		if oldVisual then oldVisual:Destroy() end

		-- Limpa qualquer ItemIcon antigo da tentativa anterior
		local oldIcon = slotBtn:FindFirstChild("ItemIcon")
		if oldIcon then oldIcon:Destroy() end

		-- Restaura background do slot (silhueta)
		if slotBtn:IsA("ImageButton") then
			slotBtn.Image = InitialSlotImages[slotName] or ""
			slotBtn.ImageTransparency = 0
		end

		if itemName then
			local data = ItemData.Get(itemName)
			if data then
				-- Clona o Template único (Compartilhado)
				local newItemVisual = SharedItemTemplate:Clone()
				newItemVisual.Name = "EquippedItemVisual"
				newItemVisual.Size = UDim2.fromScale(1, 1) -- Ocupa todo o slot
				newItemVisual.Position = UDim2.fromScale(0.5, 0.5)
				newItemVisual.AnchorPoint = Vector2.new(0.5, 0.5)
				-- newItemVisual.ZIndex = slotBtn.ZIndex + 1 -- Opcional, mas padrão já serve se parent for 0
				newItemVisual.Visible = true

				-- Aplica dados (ícone, etc) usando a função padrão
				ApplyIconData(newItemVisual, data)

				-- Se o template tiver nome, atualiza
				if newItemVisual:FindFirstChild("ItemName") then 
					newItemVisual.ItemName.Text = data.Name
					newItemVisual.ItemName.Visible = true 
				end

				-- Garante que Qtd fique oculto em slots de equipamento
				if newItemVisual:FindFirstChild("Qtd") then
					newItemVisual.Qtd.Visible = false
				end

				-- Garante que Hotkey fique oculto em slots de equipamento
				if newItemVisual:FindFirstChild("Hotkey") then
					newItemVisual.Hotkey.Visible = false
				end

				newItemVisual.Parent = slotBtn

				-- Configure Drag
				SetupDrag(newItemVisual, itemName, "Gear", slotName)

				-- Hover Events (No Visual)
				newItemVisual.MouseEnter:Connect(function() UpdateItemInfo(data) end)
				newItemVisual.MouseLeave:Connect(function() UpdateItemInfo(nil) end)
			else
				-- Remove visual se dados invalidos
			end
		else
			-- VAZIO: Já restauramos a silhueta no inicio do loop
		end
	end
end

local WeightFrame = MainBackground:WaitForChild("Weight")
local WeightQtd = WeightFrame:WaitForChild("Qtd")
local WeightMax = WeightFrame:WaitForChild("Max")

-- ============================================================================
-- CATEGORY SYSTEM
-- ============================================================================
currentCategory = "All" -- Global neste escopo para UpdateBackpackUI ler

local CategoryFrame = MainBackground:WaitForChild("Category")

local function SetCategory(newCat)
	currentCategory = newCat

	-- [RESET] Limpa a busca ao trocar de categoria
	-- Volta para o texto "Search"
	if SearchBox.Text ~= PLACEHOLDER then
		SearchBox.Text = PLACEHOLDER 
		currentSearchText = ""
	end

	UpdateBackpackUI() -- Recarrega a lista com o filtro
	-- Efeito visual opcional:
	for _, btn in pairs(CategoryFrame:GetChildren()) do
		if btn:IsA("ImageButton") or btn:IsA("TextButton") then
			-- Se quiser mudar cor/transparência do ativo:
			-- if btn.Name == newCat then btn.ImageTransparency = 0 end
		end
	end
end

-- Conectar Botões
local categories = {"All", "Weapons", "Equipments", "Consumables", "Misc"}
for _, catName in pairs(categories) do
	local btn = CategoryFrame:FindFirstChild(catName)
	if btn then
		btn.MouseButton1Click:Connect(function()
			SetCategory(catName)
		end)
	end
end

UpdateInvEvent.OnClientEvent:Connect(function(newData) -- newData agora é uma tabela completa
	-- Support legacy structure or new structure
	if newData.Backpack then
		CurrentInventoryData = newData -- {Backpack, Hotbar, Gear, EquippedSlot, CurrentWeight, MaxWeight}
	else
		-- Fallback caso o server mande formato antigo (durante dev)
		CurrentInventoryData = { Backpack={}, Hotbar={}, Gear={} }
	end

	UpdateBackpackUI()
	UpdateHotbarUI() 
	UpdateGearUI()

	-- Atualiza Peso
	if CurrentInventoryData.CurrentWeight and CurrentInventoryData.MaxWeight then
		WeightQtd.Text = tostring(CurrentInventoryData.CurrentWeight)
		WeightMax.Text = tostring(CurrentInventoryData.MaxWeight)

		-- Opcional: Mudar cor se estiver sobrecarregado
		if CurrentInventoryData.CurrentWeight > CurrentInventoryData.MaxWeight then
			WeightQtd.TextColor3 = Color3.fromRGB(255, 50, 50) -- Vermelho
		else
			WeightQtd.TextColor3 = Color3.fromRGB(255, 255, 255) -- Branco
		end
	end
end)

-- ============================================================================
-- TOGGLE INVENTÁRIO
-- ============================================================================

local function ToggleInventory()
	if isAnimating then return end
	isAnimating = true
	inventoryOpen = not inventoryOpen

	-- [FIX] Garante que o tooltip feche ao trocar o estado do inventário
	-- Isso previne que ele fique "preso" se o item debaixo do mouse sumir
	UpdateItemInfo(nil) 

	-- [RESET] Reseta a busca ao abrir/fechar
	if SearchBox.Text ~= PLACEHOLDER then
		SearchBox.Text = PLACEHOLDER
		currentSearchText = ""
	end

	UpdateHotbarUI()
	SetDragEnabled(inventoryOpen)

	local slideInfo = TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	local fadeInfo = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	for _, child in pairs(InventoryScreenGUI:GetChildren()) do
		if child:IsA("GuiObject") and child ~= MainBackground and child ~= HotbarGui and child ~= BackgroundContainer and child ~= SlotsItemsFrame and child ~= ItemInfoFrame then
			child.Visible = inventoryOpen
		end
	end

	SlotsItemsFrame.Visible = inventoryOpen

	if inventoryOpen then
		InventoryBlur.Enabled = true
		TweenService:Create(InventoryBlur, fadeInfo, {Size = 24}):Play()

		BackgroundContainer.Visible = true
		for _, child in pairs(BackgroundContainer:GetChildren()) do
			if child:IsA("ImageLabel") or child:IsA("ImageButton") then
				child.ImageTransparency = 1 
				TweenService:Create(child, fadeInfo, {ImageTransparency = 0}):Play() 
			end
		end

		MainBackground.Visible = true
		local tween = TweenService:Create(MainBackground, slideInfo, {Position = OriginalPos})
		tween:Play()
		tween.Completed:Connect(function() isAnimating = false end)
	else
		TweenService:Create(InventoryBlur, fadeInfo, {Size = 0}):Play()

		for _, child in pairs(BackgroundContainer:GetChildren()) do
			if child:IsA("ImageLabel") or child:IsA("ImageButton") then
				TweenService:Create(child, fadeInfo, {ImageTransparency = 1}):Play()
			end
		end

		local tweenClose = TweenService:Create(MainBackground, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {Position = HiddenPos})
		tweenClose:Play()
		tweenClose.Completed:Connect(function()
			MainBackground.Visible = false
			BackgroundContainer.Visible = false 
			InventoryBlur.Enabled = false
			isAnimating = false 
		end)
	end
end

UserInputService.InputBegan:Connect(function(input, gpe)
	if input.KeyCode == Enum.KeyCode.Tab then ToggleInventory() end
	if not gpe and input.KeyCode == Enum.KeyCode.T then ToggleCombatEvent:FireServer() end -- Tecla T para combate

	local keyMap = {[Enum.KeyCode.One]=1, [Enum.KeyCode.Two]=2, [Enum.KeyCode.Three]=3, [Enum.KeyCode.Four]=4, [Enum.KeyCode.Five]=5, [Enum.KeyCode.Six]=6, [Enum.KeyCode.Seven]=7, [Enum.KeyCode.Eight]=8, [Enum.KeyCode.Nine]=9, [Enum.KeyCode.Zero]=10}
	if not gpe and keyMap[input.KeyCode] then EquipEvent:FireServer(keyMap[input.KeyCode]) end
end)