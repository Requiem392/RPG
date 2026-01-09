--[[
    PostureBar.client.luau
    
    Gerencia a barra de Postura - BARRA VERTICAL
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

-- Referências UI
local gui = script.Parent -- Resources.screengui
local postureFrame = gui:WaitForChild("POSTURE")
local fillFrame = postureFrame:WaitForChild("Fill")

-- Cria a barra de "lag" (amarela)
local lagBar = fillFrame:FindFirstChild("LagBar")
if not lagBar then
	lagBar = Instance.new("Frame")
	lagBar.Name = "LagBar"
	lagBar.Size = UDim2.new(1, 0, 1, 0)
	lagBar.Position = UDim2.new(0, 0, 0, 0)
	lagBar.AnchorPoint = Vector2.new(0, 1)
	lagBar.BackgroundColor3 = Color3.fromRGB(255, 200, 0)
	lagBar.BorderSizePixel = 0
	lagBar.ZIndex = fillFrame.ZIndex - 1
	lagBar.Parent = postureFrame
end

-- Remotes
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local PostureUpdate = Remotes:WaitForChild("PostureUpdate")

-- ======================================================================
-- CONFIGURAÇÃO (ESTILO ELDEN RING)
-- ======================================================================

local VELOCIDADE_PRINCIPAL = 0.4  -- LERP da barra (visual)
local DELAY_ANTES_DESCER = 1.0    -- Delay fixo (1s)
local VELOCIDADE_DESCIDA = 80     -- Velocidade de queda LINEAR (unidades/segundo)

local MAX_POSTURE = 100

-- Estado
local CurrentPosture = MAX_POSTURE
local PostureVisual = CurrentPosture
local PostureLag = CurrentPosture
local LagStartTime = 0

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
	PostureVisual = PostureVisual + (CurrentPosture - PostureVisual) * VELOCIDADE_PRINCIPAL

	-- Snap final para evitar micro-movimentos infinitos quando estiver muito perto
	if math.abs(PostureVisual - CurrentPosture) < 0.1 then
		PostureVisual = CurrentPosture
	end

	-- 2. Barra de Lag (Amarela)

	-- CASO 1: RECUPERAÇÃO (Postura subindo)
	-- Correção: Forçamos a lag bar a ser igual à visual durante a subida.
	-- Isso impede que ela ultrapasse a verde e cause a "piscada" na borda.
	if CurrentPosture > PostureLag then
		PostureLag = PostureVisual 
		LagStartTime = 0 -- Reseta timer

		-- CASO 2: DANO (Postura descendo)
	elseif CurrentPosture < PostureLag then

		local damageAmount = PostureLag - CurrentPosture

		-- Pequenos danos contínuos (block) vs Grandes danos (ataque)
		-- Se o dano for pequeno E não estivermos no meio de um delay, atualiza junto
		if damageAmount < 3 and LagStartTime == 0 then
			PostureLag = CurrentPosture

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
				PostureLag = math.max(PostureLag - dropAmount, CurrentPosture)
			else
				-- Aguardando... (Congelado)
			end
		end
	else
		-- Valores iguais e estáveis
		LagStartTime = 0
	end

	-- Atualiza Tamanhos dos Frames
	local percentPrincipal = math.clamp(PostureVisual / MAX_POSTURE, 0, 1)
	local percentLag = math.clamp(PostureLag / MAX_POSTURE, 0, 1)

	fillFrame.Size = UDim2.new(fillFrame.Size.X.Scale, 0, percentPrincipal, 0)
	lagBar.Size = UDim2.new(lagBar.Size.X.Scale, 0, percentLag, 0)

	-- Visibilidade Otimizada
	-- Removemos a lógica complexa. A barra amarela só some se estiver vazia.
	-- O ZIndex (configurado lá em cima) garante que a verde cubra ela.
	lagBar.Visible = (percentLag > 0)
end

RunService.RenderStepped:Connect(atualizarBarra)

-- ======================================================================
-- EVENTOS DO SERVIDOR
-- ======================================================================

PostureUpdate.OnClientEvent:Connect(function(action, data)
	if action == "Init" then
		CurrentPosture = data.Posture or MAX_POSTURE
		PostureVisual = CurrentPosture
		PostureLag = CurrentPosture
		LagStartTime = 0
		print("⚖️ [PostureBar] Inicializada -", CurrentPosture)
		
	elseif action == "Update" then
		if data.Posture then
			CurrentPosture = data.Posture
		end
		
	elseif action == "Break" then
		-- Posture Break! Reseta
		CurrentPosture = data.Posture or MAX_POSTURE
		PostureVisual = CurrentPosture
		PostureLag = CurrentPosture
		LagStartTime = 0
		print("💥 [PostureBar] POSTURE BREAK! Resetada")
	end
end)

print("✅ PostureBar (Fixed) iniciada")
