--[[
	EnergyUI.client.luau
	
	Gerencia a UI de energia (barra vertical)
	- Atualiza visualmente a barra
	- Animações smooth
	- Cores dinâmicas
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

-- Módulos
local ResourceManager = require(ReplicatedStorage:WaitForChild("ResourceManager"))
local CONFIG = ResourceManager.GetConfig()

-- UI
local ResourcesGui = PlayerGui:WaitForChild("Resources")
local EnergyFrame = ResourcesGui:WaitForChild("Energy")

-- Procura pela barra de preenchimento (ajuste conforme sua estrutura)
local EnergyFill = EnergyFrame:FindFirstChild("Fill") or EnergyFrame:FindFirstChild("Bar") or EnergyFrame

-- Remotes
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local ResourceEvent = Remotes:WaitForChild("ResourceUpdate")

-- Estado local
local CurrentStamina = 100
local MaxStamina = CONFIG.Stamina.Max

-- ============================================================================
-- FUNÇÕES DE UI
-- ============================================================================

-- Atualiza a barra verticalmente (de baixo para cima)
local function UpdateEnergyBar(value, animate)
	local percent = math.clamp(value / MaxStamina, 0, 1)

	-- Calcula cor baseada na porcentagem
	local color
	if percent > 0.5 then
		color = Color3.fromRGB(0, 255, 0) -- Verde
	elseif percent > 0.25 then
		color = Color3.fromRGB(255, 255, 0) -- Amarelo
	else
		color = Color3.fromRGB(255, 0, 0) -- Vermelho
	end

	if animate then
		-- Anima tamanho (vertical - de baixo para cima)
		local sizeTween = TweenService:Create(EnergyFill, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = UDim2.new(EnergyFill.Size.X.Scale, 0, percent, 0),
			BackgroundColor3 = color
		})
		sizeTween:Play()
	else
		-- Atualiza instantaneamente
		EnergyFill.Size = UDim2.new(EnergyFill.Size.X.Scale, 0, percent, 0)
		EnergyFill.BackgroundColor3 = color
	end
end

-- Animação de "sem energia" (pisca vermelho)
local function FlashLowEnergy()
	local originalColor = EnergyFill.BackgroundColor3

	local flash = TweenService:Create(EnergyFill, TweenInfo.new(0.1, Enum.EasingStyle.Linear), {
		BackgroundColor3 = Color3.fromRGB(255, 100, 100)
	})

	local flashBack = TweenService:Create(EnergyFill, TweenInfo.new(0.1, Enum.EasingStyle.Linear), {
		BackgroundColor3 = originalColor
	})

	flash:Play()
	flash.Completed:Connect(function()
		flashBack:Play()
	end)
end

-- ============================================================================
-- EVENTOS
-- ============================================================================

-- Escuta atualizações do servidor
ResourceEvent.OnClientEvent:Connect(function(action, data)
	if action == "Init" then
		-- Inicialização
		CurrentStamina = data.Stamina
		UpdateEnergyBar(CurrentStamina, false)

	elseif action == "Update" then
		-- Atualização
		if data.Stamina then
			local oldStamina = CurrentStamina
			CurrentStamina = data.Stamina

			-- Anima mudança
			UpdateEnergyBar(CurrentStamina, true)

			-- Se tentou usar mas não tinha, pisca
			if oldStamina == CurrentStamina and CurrentStamina < 10 then
				FlashLowEnergy()
			end
		end
	end
end)

-- ============================================================================
-- CONFIGURAÇÃO INICIAL DA BARRA
-- ============================================================================

-- Garante que a barra cresce de baixo para cima
EnergyFill.AnchorPoint = Vector2.new(0, 1) -- Ancora no canto inferior esquerdo
EnergyFill.Position = UDim2.new(0, 0, 1, 0) -- Posiciona no fundo do frame

-- Atualiza barra inicial
UpdateEnergyBar(CurrentStamina, false)

print(" EnergyUI iniciado")
