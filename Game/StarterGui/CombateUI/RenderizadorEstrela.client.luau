local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local CombateMath = require(ReplicatedStorage:WaitForChild("CombateMath"))
local pastaUI = ReplicatedStorage:WaitForChild("AssetsUI")
local prefabUI = pastaUI:WaitForChild("IndicadorPostura") 

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- === CONFIGURAÇÕES VISUAIS ===
local SENSIBILIDADE = 2
local RAIO_VIRTUAL = 100

-- Cores
local COR_ATIVA = Color3.fromRGB(255, 0, 0)     -- Vermelho (Quando seleciona)
local COR_INATIVA = Color3.fromRGB(200, 200, 200) -- Cinza Claro/Branco (Quando tá parado)

-- Transparência
local TRANSP_ATIVA = 0   -- Totalmente visível
local TRANSP_INATIVA = 0 -- Meio transparente pra não poluir (mude pra 0 se quiser sólido)

local mouseVirtual = Vector2.new(0, 0)
local posturaAtual = "Ponta1"
local uiAtual = nil
local alvoAtual = nil

-- === FUNÇÃO: PINTAR A UI ===
local function atualizarVisualUI(postura)
	if not uiAtual then return end

	local nomesPontas = {"Ponta1", "Ponta2", "Ponta3", "Ponta4", "Ponta5", "Bolinha"}

	for _, nome in pairs(nomesPontas) do
		local imagem = uiAtual:FindFirstChild(nome)

		if imagem and imagem:IsA("ImageLabel") then
			if nome == postura then
				-- === ATIVO (VERMELHO) ===
				imagem.ImageColor3 = COR_ATIVA
				imagem.ImageTransparency = TRANSP_ATIVA
				imagem.ZIndex = 2 -- Joga pra frente
			else
				-- === INATIVO (BRANCO/CINZA - AGORA VISÍVEL) ===
				imagem.ImageColor3 = COR_INATIVA
				imagem.ImageTransparency = TRANSP_INATIVA
				imagem.ZIndex = 1
			end
		end
	end
end

RunService.RenderStepped:Connect(function()
	-- 1. CÁLCULOS (Igual antes)
	local novaPostura = nil
	local mouseTravado = UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter

	if mouseTravado then
		local delta = UserInputService:GetMouseDelta()
		mouseVirtual = mouseVirtual + (delta * SENSIBILIDADE)
		if mouseVirtual.Magnitude > RAIO_VIRTUAL then mouseVirtual = mouseVirtual.Unit * RAIO_VIRTUAL end
		novaPostura = CombateMath.CalcularPostura(mouseVirtual, Vector2.new(0,0))
	else
		local centro = camera.ViewportSize / 2
		local mousePos = UserInputService:GetMouseLocation()
		mouseVirtual = mousePos - centro
		novaPostura = CombateMath.CalcularPostura(mousePos, centro)
	end

	if novaPostura then posturaAtual = novaPostura end

	-- 2. SISTEMA DE TRAVA (Comunicação com ObjectValue)
	local caixaAlvo = player:FindFirstChild("AlvoTravaObj")
	local alvoTrava = caixaAlvo and caixaAlvo.Value 

	if alvoTrava and alvoTrava:IsA("Model") and alvoTrava:FindFirstChild("Head") then
		if alvoAtual ~= alvoTrava then
			if uiAtual then uiAtual:Destroy() end
			alvoAtual = alvoTrava

			-- Clona a UI na cabeça do inimigo
			uiAtual = prefabUI:Clone()
			uiAtual.Parent = player.PlayerGui
			uiAtual.Adornee = alvoAtual.Head 
		end

		atualizarVisualUI(posturaAtual)
	else
		if uiAtual then uiAtual:Destroy(); uiAtual = nil end
		alvoAtual = nil
	end
end)

-- FLASH AO ATACAR
UserInputService.InputBegan:Connect(function(input, gp)
	if gp then return end
	if not uiAtual then return end 

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		local imagemAlvo = uiAtual:FindFirstChild(posturaAtual)
		if imagemAlvo then
			-- Flash Branco Rápido
			local tween = TweenService:Create(imagemAlvo, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true), {ImageColor3 = Color3.new(1, 1, 1)}) 
			tween:Play()
		end
	end
end)