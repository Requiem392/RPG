local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local Lighting = game:GetService("Lighting")

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

local DataFolder = ReplicatedStorage:WaitForChild("Data")
local ItemData = require(DataFolder:WaitForChild("ItemData"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local UpdateInvEvent = Remotes:WaitForChild("UpdateInventory")
local EquipEvent = Remotes:WaitForChild("EquipItem")
local MoveItemEvent = Remotes:WaitForChild("MoveItem")

-- Referências de UI
local InventoryScreenGUI = script.Parent
local MainBackground = InventoryScreenGUI:WaitForChild("InventoryBackground")
local BackpackFrame = MainBackground:WaitForChild("ScrollingFrame")
local BackpackTemplate = BackpackFrame:WaitForChild("ItemTemplate")

local HotbarGui = InventoryScreenGUI:WaitForChild("Hotbar")
local HotbarTemplate = HotbarGui:WaitForChild("ItemTemplate")
local SlotFixoTemplate = HotbarGui:WaitForChild("SlotFixo") 

local BackgroundContainer = InventoryScreenGUI:WaitForChild("Background")

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
local UpdateHotbarUI, UpdateBackpackUI 

-- Setup Inicial
BackpackTemplate.Visible = false
HotbarTemplate.Visible = false
SlotFixoTemplate.Visible = false 
MainBackground.Position = HiddenPos 
MainBackground.Visible = false 

BackgroundContainer.Visible = false
for _, child in pairs(BackgroundContainer:GetChildren()) do
	if child:IsA("ImageLabel") or child:IsA("ImageButton") then
		child.ImageTransparency = 1
	end
end

for _, child in pairs(InventoryScreenGUI:GetChildren()) do
	if child:IsA("GuiObject") and child ~= MainBackground and child ~= HotbarGui and child ~= BackgroundContainer then
		child.Visible = false
	end
end

-- Variáveis de Estado
local CurrentInventoryData = { Backpack = {}, Hotbar = {}, EquippedSlot = nil }
local draggingItemName, draggingSourceIndex, draggingSourceType, dragGhost = nil, nil, nil, nil
local lastDragTime = 0 
local inventoryOpen = false
local isAnimating = false 

-- ============================================================================
-- FUNÇÕES ÚTEIS
-- ============================================================================

local function ClearUI(container)
	for _, child in pairs(container:GetChildren()) do
		if child:IsA("GuiObject") and child ~= BackpackTemplate and child ~= HotbarTemplate and child ~= SlotFixoTemplate and child.Name ~= "DragGhost" then
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
			for _, child in pairs(itemFrame:GetChildren()) do 
				if child:IsA("GuiObject") then child.Visible = true end 
			end

			-- >>> CORREÇÃO: Usando .Get() para achar os dados na categoria
			local data = ItemData.Get(itemName)
			if data then ApplyIconData(itemFrame, data) end
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

		if foundHotbarSlot then
			SimularMovimentoLocal(draggingItemName, foundHotbarSlot, draggingSourceType, draggingSourceIndex)
			UpdateBackpackUI()
			UpdateHotbarUI()
			MoveItemEvent:FireServer(draggingItemName, foundHotbarSlot, draggingSourceType, draggingSourceIndex) 
		elseif droppedOnBackpack then
			if targetBackpackIndex then
				local swapCommand = "SwapBackpack_"..targetBackpackIndex
				SimularMovimentoLocal(draggingItemName, swapCommand, draggingSourceType, draggingSourceIndex)
				UpdateBackpackUI()
				UpdateHotbarUI()
				MoveItemEvent:FireServer(draggingItemName, swapCommand, draggingSourceType, draggingSourceIndex)
			else
				if draggingSourceType == "Hotbar" then
					SimularMovimentoLocal(draggingItemName, "Backpack", "Hotbar", draggingSourceIndex)
					UpdateBackpackUI()
					UpdateHotbarUI()
					MoveItemEvent:FireServer(draggingItemName, "Backpack", "Hotbar", draggingSourceIndex)
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
		local itemName = CurrentInventoryData.Hotbar[tostring(i)] or CurrentInventoryData.Hotbar[i]
		local isEquipped = (tostring(CurrentInventoryData.EquippedSlot) == tostring(i))

		if itemName then
			-- >>> CORREÇÃO: Usando .Get() aqui também
			local itemInfo = ItemData.Get(itemName)

			if itemInfo then
				local newItem = HotbarTemplate:Clone()
				newItem.Name = "Slot_" .. i 
				newItem.LayoutOrder = i
				newItem.Visible = true
				ApplyIconData(newItem, itemInfo)
				if newItem:FindFirstChild("ItemName") then newItem.ItemName.Text = itemInfo.Name end
				if newItem:FindFirstChild("Hotkey") then newItem.Hotkey.Text = tostring(i % 10) end
				if newItem:FindFirstChild("Qtd") then newItem.Qtd.Text = "1" end 

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
				SetupDrag(newItem, itemName, "Hotbar", i)
			end
		elseif inventoryOpen then
			local emptySlot = SlotFixoTemplate:Clone()
			emptySlot.Name = "Slot_" .. i 
			emptySlot.LayoutOrder = i
			emptySlot.Visible = true
			if emptySlot:FindFirstChild("Hotkey") then emptySlot.Hotkey.Text = tostring(i % 10) end

			if isEquipped then
				emptySlot.Size = SIZE_EQUIPPED
				emptySlot.ZIndex = 10
				for _, v in pairs(emptySlot:GetChildren()) do 
					if v:IsA("GuiObject") then v.ZIndex = 11 end 
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
					if (tick() - lastDragTime > 0.2) and (not dragGhost) then
						EquipEvent:FireServer(i)
					end
				end
			end)

			emptySlot.Parent = HotbarGui
		end
	end
end

function UpdateBackpackUI()
	ClearUI(BackpackFrame)
	local gridLayout = BackpackFrame:FindFirstChildOfClass("UIGridLayout")
	if gridLayout then gridLayout.SortOrder = Enum.SortOrder.LayoutOrder end
	for i, itemName in ipairs(CurrentInventoryData.Backpack) do
		-- >>> CORREÇÃO: Usando .Get() aqui também
		local data = ItemData.Get(itemName)
		if data then
			local newItem = BackpackTemplate:Clone()
			newItem.Name = data.Name
			newItem:SetAttribute("Index", i)
			newItem.Visible = true
			newItem.LayoutOrder = i
			ApplyIconData(newItem, data)
			if newItem:FindFirstChild("ItemName") then newItem.ItemName.Text = data.Name end
			newItem.Parent = BackpackFrame
			SetupDrag(newItem, itemName, "Backpack", i)
		end
	end
end

UpdateInvEvent.OnClientEvent:Connect(function(newData)
	CurrentInventoryData = newData
	UpdateBackpackUI()
	UpdateHotbarUI() 
end)

-- ============================================================================
-- TOGGLE INVENTÁRIO
-- ============================================================================

local function ToggleInventory()
	if isAnimating then return end
	isAnimating = true
	inventoryOpen = not inventoryOpen

	UpdateHotbarUI()
	SetDragEnabled(inventoryOpen)

	local slideInfo = TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	local fadeInfo = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	for _, child in pairs(InventoryScreenGUI:GetChildren()) do
		if child:IsA("GuiObject") and child ~= MainBackground and child ~= HotbarGui and child ~= BackgroundContainer then
			child.Visible = inventoryOpen
		end
	end

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
	local keyMap = {[Enum.KeyCode.One]=1, [Enum.KeyCode.Two]=2, [Enum.KeyCode.Three]=3, [Enum.KeyCode.Four]=4, [Enum.KeyCode.Five]=5, [Enum.KeyCode.Six]=6, [Enum.KeyCode.Seven]=7, [Enum.KeyCode.Eight]=8, [Enum.KeyCode.Nine]=9, [Enum.KeyCode.Zero]=10}
	if not gpe and keyMap[input.KeyCode] then EquipEvent:FireServer(keyMap[input.KeyCode]) end
end)