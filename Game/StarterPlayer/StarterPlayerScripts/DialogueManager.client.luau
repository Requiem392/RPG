local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

-- ============================================================================
-- ⚙️ CONFIGURAÇÃO
-- ============================================================================
local USAR_CAMERA = true 
local FOCAR_PLAYER_NAS_OPCOES = true 
local TEMPO_TRANSICAO_CAM = 0.8 
local FOV_CINEMA = 50 
local FOV_PADRAO = 70

local CAMERA_OFFSET_NPC = Vector3.new(-4, 2, -6) 
local CAMERA_OFFSET_PLAYER = Vector3.new(3, 2, -5) 

-- ============================================================================
-- REFERÊNCIAS
-- ============================================================================
local DialogoRF = ReplicatedStorage:WaitForChild("DialogoRF")
local eventoStart = ReplicatedStorage:WaitForChild("RequestDialogoStart")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local playerGui = player:WaitForChild("PlayerGui")

local gui = playerGui:WaitForChild("DialogoGui")
local frame = gui:WaitForChild("CaixaDialogo")
local labelTexto = frame:WaitForChild("TextoFala")
local containerRespostas = frame:WaitForChild("ContainerRespostas")

-- [[ CORREÇÃO 1: Nome exato que está no seu Print ]]
local templateBotao = containerRespostas:FindFirstChild("RespostaTemplate") 

local barraCima = gui:WaitForChild("BarraCima")
local barraBaixo = gui:WaitForChild("BarraBaixo")

-- CONTROLE GERAL
local estaEscrevendo = false
local npcAtualModel = nil 
local emDialogo = false 
local tweenCameraAtual = nil 
local conexaoMorte = nil 

-- CONTROLE DE MÍDIA
local somAtual = nil
local trackBody = nil 
local trackFace = nil 

-- ============================================================================
-- 1. SISTEMA DE SEGURANÇA E CÂMERA
-- ============================================================================

local function CancelarTweenCamera()
	if tweenCameraAtual then
		tweenCameraAtual:Cancel()
		tweenCameraAtual = nil
	end
end

local function PararAnimacoes()
	if trackBody then trackBody:Stop(); trackBody = nil end
	if trackFace then trackFace:Stop(); trackFace = nil end
end

local function PararTudo()
	if somAtual then
		somAtual:Stop()
		somAtual:Destroy()
		somAtual = nil
	end
	PararAnimacoes()
end

local function RestaurarGameplay()
	CancelarTweenCamera()

	local char = player.Character
	local hum = char and char:FindFirstChild("Humanoid")
	if hum then
		hum.WalkSpeed = 16
		hum.JumpPower = 50
		hum.AutoRotate = true
		camera.CameraSubject = hum 
	end

	task.wait(0.1) 

	camera.CameraType = Enum.CameraType.Custom
	camera.FieldOfView = FOV_PADRAO

	if conexaoMorte then conexaoMorte:Disconnect(); conexaoMorte = nil end
	npcAtualModel = nil
end

local function ForcarSaidaDialogo()
	emDialogo = false
	estaEscrevendo = false

	PararTudo() 

	gui.Enabled = false
	frame.Visible = false

	barraCima.Position = UDim2.new(0.5, 0, -0.3, 0)
	barraBaixo.Position = UDim2.new(0.5, 0, 1.3, 0)

	RestaurarGameplay()
end

local function MoverCameraPara(alvoPart, offset)
	if not USAR_CAMERA or not alvoPart then return end

	CancelarTweenCamera()
	camera.CameraType = Enum.CameraType.Scriptable

	local posicaoFinal = alvoPart.CFrame:ToWorldSpace(CFrame.new(offset)).Position
	local olharPara = alvoPart.Position
	local novaCFrame = CFrame.lookAt(posicaoFinal, olharPara)

	local tweenInfo = TweenInfo.new(TEMPO_TRANSICAO_CAM, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	tweenCameraAtual = TweenService:Create(camera, tweenInfo, {CFrame = novaCFrame, FieldOfView = FOV_CINEMA})
	tweenCameraAtual:Play()
end

local function CongelarJogador()
	local char = player.Character
	local humanoid = char and char:FindFirstChild("Humanoid")

	if humanoid then
		if conexaoMorte then conexaoMorte:Disconnect() end
		conexaoMorte = humanoid.Died:Connect(function() ForcarSaidaDialogo() end)

		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
		humanoid.AutoRotate = false 
	end
end

-- ============================================================================
-- 2. EXECUTAR MÍDIA
-- ============================================================================
local function ExecutarMidia(dados, modeloNPC)
	PararTudo() 

	if not modeloNPC then return end

	-- SOM
	if dados.SoundId then
		local root = modeloNPC:FindFirstChild("HumanoidRootPart") or modeloNPC:FindFirstChild("Head")
		if root then
			local som = Instance.new("Sound")
			som.SoundId = "rbxassetid://" .. tostring(dados.SoundId)
			som.Volume = 1
			som.Parent = root
			som:Play()
			somAtual = som
		end
	end

	-- ANIMAÇÕES
	local humanoid = modeloNPC:FindFirstChild("Humanoid")
	local animator = humanoid and humanoid:FindFirstChild("Animator")

	if humanoid and not animator then animator = Instance.new("Animator", humanoid) end
	if not animator then return end

	if dados.BodyAnimId then
		local anim = Instance.new("Animation")
		anim.AnimationId = "rbxassetid://" .. tostring(dados.BodyAnimId)
		trackBody = animator:LoadAnimation(anim)
		trackBody.Priority = Enum.AnimationPriority.Movement 
		trackBody:Play()
	end

	if dados.FaceAnimId then
		local anim = Instance.new("Animation")
		anim.AnimationId = "rbxassetid://" .. tostring(dados.FaceAnimId)
		trackFace = animator:LoadAnimation(anim)
		trackFace.Priority = Enum.AnimationPriority.Action 
		trackFace:Play()
	end
end

local function AnimarBarras(entrando)
	local infoTween = TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	if entrando then
		TweenService:Create(barraCima, infoTween, {Position = UDim2.new(0.5, 0, 0, 0)}):Play()
		TweenService:Create(barraBaixo, infoTween, {Position = UDim2.new(0.5, 0, 1, 0)}):Play()
	else
		TweenService:Create(barraCima, infoTween, {Position = UDim2.new(0.5, 0, -0.3, 0)}):Play()
		TweenService:Create(barraBaixo, infoTween, {Position = UDim2.new(0.5, 0, 1.3, 0)}):Play()
	end
end

local function EscreverTexto(texto)
	estaEscrevendo = true
	labelTexto.Text = texto
	labelTexto.MaxVisibleGraphemes = 0

	for i = 1, utf8.len(texto) do
		if not estaEscrevendo then break end 
		labelTexto.MaxVisibleGraphemes = i
		task.wait(0.02)
	end
	labelTexto.MaxVisibleGraphemes = -1
	estaEscrevendo = false
end

-- ============================================================================
-- 4. LOOP PRINCIPAL
-- ============================================================================
local function CarregarDialogo(idDialogo, modeloNPC)

	if modeloNPC then npcAtualModel = modeloNPC end

	local sucesso, dados = pcall(function()
		return DialogoRF:InvokeServer("PegarDialogo", idDialogo)
	end)

	if sucesso and dados then
		gui.Enabled = true
		frame.Visible = true

		CongelarJogador()
		AnimarBarras(true)

		if npcAtualModel and npcAtualModel:FindFirstChild("Head") then
			MoverCameraPara(npcAtualModel.Head, CAMERA_OFFSET_NPC)
		end

		ExecutarMidia(dados, npcAtualModel)
		EscreverTexto(dados.Text)

		if not emDialogo then return end

		-- Espera som ou tempo padrão
		if somAtual and somAtual.IsPlaying then
			while somAtual and somAtual.IsPlaying and emDialogo do task.wait(0.1) end
			task.wait(0.2) 
		else
			task.wait(1) 
		end

		if not emDialogo then return end

		PararAnimacoes() 

		-- [[ CORREÇÃO 2: Limpa botões velhos sem apagar o UIListLayout ou o Template ]]
		for _, v in pairs(containerRespostas:GetChildren()) do
			-- Só apaga se for Botão e NÃO for o template
			if v:IsA("GuiButton") and v ~= templateBotao then 
				v:Destroy() 
			end
		end

		if dados.Responses then
			containerRespostas.Visible = true

			if FOCAR_PLAYER_NAS_OPCOES and player.Character and player.Character:FindFirstChild("Head") then
				MoverCameraPara(player.Character.Head, CAMERA_OFFSET_PLAYER)
			end

			for _, resposta in pairs(dados.Responses) do
				local btn = nil

				-- [[ CORREÇÃO 3: Lógica para usar seu RespostaTemplate ]]
				if templateBotao then
					btn = templateBotao:Clone()
					btn.Visible = true

					-- Verifica se tem o objeto "Text" dentro (baseado no seu print)
					local textoInterno = btn:FindFirstChild("Text")
					if textoInterno then
						textoInterno.Text = resposta.Text
						if btn:IsA("TextButton") then btn.Text = "" end -- Limpa texto do botão pai se houver
					else
						-- Se não achar o objeto Text, tenta por direto no botão
						if btn:IsA("TextButton") then btn.Text = resposta.Text end
					end

					btn.Parent = containerRespostas
				else
					-- Cria botão feio de emergência se não achar o template
					btn = Instance.new("TextButton", containerRespostas)
					btn.Size = UDim2.new(1, 0, 0, 30)
					btn.Text = resposta.Text
				end

				btn.MouseButton1Click:Connect(function()
					if not emDialogo then return end 

					if resposta.Action then 
						pcall(function() DialogoRF:InvokeServer("EscolherOpcao", resposta.Action) end)
					end

					if resposta.NextID and resposta.NextID ~= "EXIT" then
						CarregarDialogo(resposta.NextID, nil)
					else
						frame.Visible = false
						AnimarBarras(false)
						PararTudo() 
						RestaurarGameplay()

						task.delay(0.8, function()
							gui.Enabled = false
							emDialogo = false
						end)
					end
				end)
			end
		else
			containerRespostas.Visible = false
		end
	else
		warn("❌ Erro ao carregar diálogo.")
		ForcarSaidaDialogo() 
	end
end

eventoStart.OnClientEvent:Connect(function(id, npc)
	if emDialogo then return end
	emDialogo = true
	CarregarDialogo(id, npc)
end)

player.CharacterRemoving:Connect(function()
	ForcarSaidaDialogo()
end)