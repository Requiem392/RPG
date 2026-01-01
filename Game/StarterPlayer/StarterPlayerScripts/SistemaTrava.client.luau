local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace") -- Pegamos o Workspace pra organizar filtros

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- ==============================================================================
-- ⚙️ CONFIGURAÇÕES
-- ==============================================================================

local TECLA = Enum.KeyCode.F
local ALCANCE_MAX = 60

-- [POSIÇÃO]
local OFFSET_X_LADO = 3.5      
local OFFSET_Y_ALTURA = 5.0    
local OFFSET_Z_DISTANCIA = 8.0 

-- [SUAVIDADE GERAL]
local SUAVIDADE_GERAL = 1 

-- [ESTABILIZADOR DE PULO]
-- Quer tirar? Coloque 1.0 (Fica instantâneo igual antes)
-- Quer manter? Deixe 0.1 (Suave)
local SUAVIDADE_VERTICAL = 1.0  -- <--- MUDEI PRA 1.0 PRA DESATIVAR POR PADRÃO

-- ==============================================================================

local alvo = nil
local highlight = nil
local travado = false
local alturaAtualCam = 0 

local function buscarInimigo()
	local char = player.Character
	if not char or not char:FindFirstChild("HumanoidRootPart") then return nil end
	local root = char.HumanoidRootPart

	local melhorAlvo = nil
	local menorDist = ALCANCE_MAX

	for _, v in pairs(workspace:GetDescendants()) do
		if v:IsA("Model") and v ~= char and v:FindFirstChild("Humanoid") and v:FindFirstChild("HumanoidRootPart") then
			local tRoot = v.HumanoidRootPart
			local dist = (tRoot.Position - root.Position).Magnitude
			if dist < menorDist and v.Humanoid.Health > 0 then
				local _, naTela = camera:WorldToViewportPoint(tRoot.Position)
				if naTela then
					menorDist = dist
					melhorAlvo = tRoot
				end
			end
		end
	end
	return melhorAlvo
end

local function atualizarCamera()
	if not alvo or not alvo.Parent or not player.Character then
		alternar(false)
		return
	end

	local char = player.Character
	local root = char:FindFirstChild("HumanoidRootPart")
	local hum = char:FindFirstChild("Humanoid")

	if not root or not hum or hum.Health <= 0 then return end

	-- 1. CÁLCULO DE ALTURA (Se SUAVIDADE_VERTICAL for 1, isso aqui não faz diferença nenhuma)
	local yAlvo = root.Position.Y
	if math.abs(yAlvo - alturaAtualCam) > 10 then
		alturaAtualCam = yAlvo
	else
		alturaAtualCam = alturaAtualCam + (yAlvo - alturaAtualCam) * SUAVIDADE_VERTICAL
	end

	local minhaPosEstavel = Vector3.new(root.Position.X, alturaAtualCam, root.Position.Z)
	local alvoPos = alvo.Position

	-- 2. MOVIMENTO DO PERSONAGEM
	local olharReto = Vector3.new(alvoPos.X, root.Position.Y, alvoPos.Z)
	local cframeBoneco = CFrame.lookAt(root.Position, olharReto)
	root.CFrame = root.CFrame:Lerp(cframeBoneco, SUAVIDADE_GERAL)

	-- 3. CÁLCULO DA CÂMERA
	local cframeFocoTotal = CFrame.lookAt(minhaPosEstavel, alvoPos)
	local posicaoIdeal = cframeFocoTotal * CFrame.new(OFFSET_X_LADO, OFFSET_Y_ALTURA, OFFSET_Z_DISTANCIA)

	-- === [CORREÇÃO DO BUG DO SOCO] ===
	-- O problema é o Raycast batendo na Hitbox. Vamos melhorar o filtro.
	local params = RaycastParams.new()

	-- Lista do que a câmera vai IGNORAR:
	local ignorar = {char, alvo.Parent}

	-- Se você tiver uma pasta de "Effects" ou "Hitboxes" no workspace, adicione ela aqui:
	if workspace:FindFirstChild("Effects") then table.insert(ignorar, workspace.Effects) end
	if workspace:FindFirstChild("Debris") then table.insert(ignorar, workspace.Debris) end
	-- (Se sua hitbox for criada solta no workspace, ela pode atrapalhar se não estiver numa pasta)

	params.FilterDescendantsInstances = ignorar
	params.FilterType = Enum.RaycastFilterType.Exclude

	local origemRaio = root.Position + Vector3.new(0, 2, 0)
	local direcaoCam = posicaoIdeal.Position - origemRaio

	-- Raio da câmera (Colisão)
	local raio = workspace:Raycast(origemRaio, direcaoCam, params)

	local posicaoFinal = posicaoIdeal.Position
	if raio then
		-- Verifica se bateu em algo que é "CanCollide false" (como hitboxes costumam ser)
		-- Se a hitbox tiver CanQuery = true, o raio pega ela.
		if raio.Instance.CanCollide == true then
			posicaoFinal = raio.Position - (direcaoCam.Unit * 0.5)
		end
	end

	-- 4. APLICAÇÃO FINAL
	local pontoDeFoco = alvoPos + Vector3.new(0, -1, 0)
	local cframeFinal = CFrame.lookAt(posicaoFinal, pontoDeFoco)

	camera.CFrame = camera.CFrame:Lerp(cframeFinal, SUAVIDADE_GERAL)
end

function alternar(forcarOff)
	-- Garante que existe a caixinha pra guardar o alvo
	local caixaAlvo = player:FindFirstChild("AlvoTravaObj")
	if not caixaAlvo then
		caixaAlvo = Instance.new("ObjectValue")
		caixaAlvo.Name = "AlvoTravaObj"
		caixaAlvo.Parent = player
	end

	if forcarOff == false or travado then
		-- DESLIGANDO A TRAVA
		travado = false
		alvo = nil

		-- === CORREÇÃO: Limpa o valor da caixinha ===
		caixaAlvo.Value = nil 
		-- ===========================================

		if highlight then highlight:Destroy() end
		highlight = nil
		RunService:UnbindFromRenderStep("TravaManual")
		camera.CameraType = Enum.CameraType.Custom
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		if player.Character then player.Character.Humanoid.AutoRotate = true end
	else
		-- LIGANDO A TRAVA
		local achou = buscarInimigo() 
		if achou then
			alvo = achou
			travado = true

			-- === CORREÇÃO: Guarda o inimigo na caixinha ===
			caixaAlvo.Value = alvo.Parent 
			-- ==============================================

			if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
				alturaAtualCam = player.Character.HumanoidRootPart.Position.Y
			end

			highlight = Instance.new("Highlight")
			highlight.Parent = alvo.Parent
			highlight.FillTransparency = 1
			highlight.OutlineColor = Color3.fromRGB(255, 255, 255)

			if player.Character then player.Character.Humanoid.AutoRotate = false end
			camera.CameraType = Enum.CameraType.Scriptable
			RunService:BindToRenderStep("TravaManual", Enum.RenderPriority.Camera.Value + 1, atualizarCamera)
		end
	end
end

UserInputService.InputBegan:Connect(function(input, gp)
	if gp then return end
	if input.KeyCode == TECLA then alternar() end
end)