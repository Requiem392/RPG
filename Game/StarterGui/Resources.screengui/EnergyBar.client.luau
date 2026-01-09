--[[
    EnergyBar.client.luau
    
    Gerencia a barra de Energia (Stamina) - BARRA VERTICAL
    - LERP suave (sem Tweens)
    - Efeito "Delayed Damage" (igual Elden Ring)
    - Correções aplicadas:
        1. Flash ao atacar removido (lógica de ZIndex).
        2. Piscada amarela ao regenerar removida (Sync Visual).
]]

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

-- Módulos
local ResourceManager = require(ReplicatedStorage:WaitForChild("ResourceManager"))
local CONFIG = ResourceManager.GetConfig()

-- Referências UI
local gui = script.Parent -- Resources.screengui
local energyFrame = gui:WaitForChild("ENERGY")
local fillFrame = energyFrame:WaitForChild("Fill") -- Barra principal (verde)

-- Cria a barra de "lag" (amarela) se não existir
local lagBar = fillFrame:FindFirstChild("LagBar")
if not lagBar then
	lagBar = Instance.new("Frame")
	lagBar.Name = "LagBar"
	lagBar.Size = UDim2.new(1, 0, 1, 0)
	lagBar.Position = UDim2.new(0, 0, 0, 0)
	lagBar.AnchorPoint = Vector2.new(0, 1)
	lagBar.BackgroundColor3 = Color3.fromRGB(255, 200, 0) -- Amarelo/Laranja
	lagBar.BorderSizePixel = 0
	lagBar.ZIndex = fillFrame.ZIndex - 1 -- Fica atrás da barra principal
	lagBar.Parent = energyFrame -- Mesmo pai que Fill
end

-- Remotes
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local ResourceEvent = Remotes:WaitForChild("ResourceUpdate")

-- ======================================================================
-- CONFIGURAÇÃO (ESTILO ELDEN RING)
-- ======================================================================

local VELOCIDADE_PRINCIPAL = 0.25  -- LERP da barra verde (visual)
local DELAY_ANTES_DESCER = 1.0     -- Delay fixo (1s) antes de cair
local VELOCIDADE_DESCIDA = 80      -- Velocidade de queda LINEAR (80 unidades/segundo)

-- Estado
local MaxStamina = CONFIG.Stamina.Max
local CurrentStamina = MaxStamina
local StaminaVisual = CurrentStamina      -- Barra principal (rápida)
local StaminaLag = CurrentStamina         -- Barra atrasada
local LagStartTime = 0                    -- Quando a barra lag começou a esperar

-- ======================================================================
-- SETUP INICIAL
-- ======================================================================

fillFrame.AnchorPoint = Vector2.new(0, 1)
fillFrame.Position = UDim2.new(0, 0, 1, 0)

lagBar.AnchorPoint = Vector2.new(0, 1)
lagBar.Position = UDim2.new(0, 0, 1, 0)

-- ======================================================================
-- ATUALIZAÇÃO
-- ======================================================================

local function atualizarBarra(dt)
	dt = dt or 0.016 -- Proteção contra dt nil

	-- 1. Barra Visual (Principal/Verde) - LERP suave
	StaminaVisual = StaminaVisual + (CurrentStamina - StaminaVisual) * VELOCIDADE_PRINCIPAL

	-- Snap final para evitar micro-movimentos infinitos quando estiver muito perto
	if math.abs(StaminaVisual - CurrentStamina) < 0.1 then
		StaminaVisual = CurrentStamina
	end

	-- 2. Barra de Lag (Amarela)

	-- CASO 1: RECUPERAÇÃO (Stamina subindo)
	-- Correção: Forçamos a lag bar a ser igual à visual durante a subida.
	-- Isso impede que ela ultrapasse a verde e cause a "piscada" na borda.
	if CurrentStamina > StaminaLag then
		StaminaLag = StaminaVisual 
		LagStartTime = 0 -- Reseta timer

		-- CASO 2: DANO (Stamina descendo)
	elseif CurrentStamina < StaminaLag then

		local damageAmount = StaminaLag - CurrentStamina

		-- Pequenos danos contínuos (block) vs Grandes danos (ataque)
		-- Se o dano for pequeno E não estivermos no meio de um delay, atualiza junto
		if damageAmount < 3 and LagStartTime == 0 then
			StaminaLag = CurrentStamina

		else
			-- Dano significativo ou já estamos esperando

			-- Inicia timer se não estiver rodando
			if LagStartTime == 0 then
				LagStartTime = tick()
			end

			-- Verifica delay
			local tempoEsperando = tick() - LagStartTime

			if tempoEsperando >= DELAY_ANTES_DESCER then
				-- Queda Linear
				local dropAmount = VELOCIDADE_DESCIDA * dt
				StaminaLag = math.max(StaminaLag - dropAmount, CurrentStamina)
			else
				-- Aguardando... (Congelado)
			end
		end
	else
		-- Valores iguais e estáveis
		LagStartTime = 0
	end

	-- Atualiza Tamanhos dos Frames
	local percentPrincipal = math.clamp(StaminaVisual / MaxStamina, 0, 1)
	local percentLag = math.clamp(StaminaLag / MaxStamina, 0, 1)

	fillFrame.Size = UDim2.new(fillFrame.Size.X.Scale, 0, percentPrincipal, 0)
	lagBar.Size = UDim2.new(lagBar.Size.X.Scale, 0, percentLag, 0)

	-- Visibilidade Otimizada
	-- Removemos a lógica complexa. A barra amarela só some se estiver vazia.
	-- O ZIndex (configurado lá em cima) garante que a verde cubra ela.
	lagBar.Visible = (percentLag > 0)
end

-- Roda a cada frame
RunService.RenderStepped:Connect(atualizarBarra)

-- ======================================================================
-- EVENTOS DO SERVIDOR
-- ======================================================================

ResourceEvent.OnClientEvent:Connect(function(action, data)
	if action == "Init" then
		CurrentStamina = data.Stamina or MaxStamina
		StaminaVisual = CurrentStamina
		StaminaLag = CurrentStamina
		LagStartTime = 0

	elseif action == "Update" then
		if data.Stamina then
			CurrentStamina = data.Stamina
		end
	end
end)

print("✅ EnergyBar (Fixed) iniciada")