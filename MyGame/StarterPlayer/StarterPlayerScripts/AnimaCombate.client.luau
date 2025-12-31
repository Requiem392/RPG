local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContentProvider = game:GetService("ContentProvider") 
local Debris = game:GetService("Debris")

local CombateMath = require(ReplicatedStorage:WaitForChild("CombateMath"))
local eventoCombate = ReplicatedStorage:WaitForChild("EventoCombate")

local pastaAssets = ReplicatedStorage:WaitForChild("AssetsVFX")
local trailTemplate = pastaAssets:WaitForChild("RastroPunch") 

local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local rootPart = character:WaitForChild("HumanoidRootPart")
local animator = humanoid:WaitForChild("Animator")

-- === CONFIGURAÇÕES ===
local FORCA_IMPULSO = 20
local ALCANCE_VISUAL = 6
local LARGURA_LEQUE = 3
local QUANTIDADE_LINHAS = 5
local TEMPO_VISUAL = 0.3

local SENSIBILIDADE = 2
local RAIO_VIRTUAL = 100

-- === ⏳ CONFIGURAÇÃO DE COOLDOWN (NOVO) ===
local COOLDOWN_FORTE = 0.9  -- O Hook demora quase 1 seg pra recuperar
local COOLDOWN_JAB = 0.7   -- O Jab é rapidinho
local ultimoAtaque = 0      -- Guarda o tempo do último golpe

-- Hitbox Local (Para o som preciso)
local DURACAO_HITBOX = 0.4
local PONTOS_DE_RASTREIO = {
	CFrame.new(0, -1, 0),     -- Ponta
	CFrame.new(0.4, -1, 0),   -- Lados
	CFrame.new(-0.4, -1, 0),
	CFrame.new(0, -0.5, 0),   -- Meio
}

-- Áudio
local SONS_SWING = {
	"rbxassetid://74238153433253",
	"rbxassetid://101467914599270",
	"rbxassetid://121514852904179"
}

local SONS_HIT = {
	"rbxassetid://109316755832781",
	"rbxassetid://113828106042161",
	"rbxassetid://98330897555423"
}

local objetosDeSomSwing = {}
local objetosDeSomHit = {} 

local LISTA_ANIMS = {
	Idle = {
		["Cima"]     = "rbxassetid://126482891056522", 
		["Esquerda"] = "rbxassetid://128460161440253", 
		["Direita"]  = "rbxassetid://107639627598983", 
	},
	AtaqueForte = {
		["Cima"]     = "rbxassetid://71862221299248", 
		["Esquerda"] = "rbxassetid://105078068476566", 
		["Direita"]  = "rbxassetid://102891047100381", 
	},
	Jab = {
		["Cima"]     = "rbxassetid://100060013737086", 
		["Direita"]  = "rbxassetid://100060013737086", 
		["Esquerda"] = "rbxassetid://97672890714490", 
	}
}

local tracksIdle, tracksForte, tracksJab = {}, {}, {}
local posturaAtual = "Cima"
local mouseVirtual = Vector2.new(0, 0)
local ultimaAnimTocada = nil -- Variável de controle da guarda

-- === PRELOAD DE SOM ===
local function prepararSons()
	objetosDeSomSwing = {} 
	objetosDeSomHit = {}
	local sonsParaCarregar = {}

	for _, id in ipairs(SONS_SWING) do
		local som = Instance.new("Sound")
		som.SoundId = id; som.Volume = 0.5; som.Parent = rootPart 
		table.insert(objetosDeSomSwing, som); table.insert(sonsParaCarregar, som)
	end

	for _, id in ipairs(SONS_HIT) do
		local som = Instance.new("Sound")
		som.SoundId = id; som.Volume = 1; som.Parent = rootPart
		table.insert(objetosDeSomHit, som); table.insert(sonsParaCarregar, som)
	end

	task.spawn(function() pcall(function() ContentProvider:PreloadAsync(sonsParaCarregar) end) end)
end

local function tocarSomSwing()
	if #objetosDeSomSwing > 0 then objetosDeSomSwing[math.random(1, #objetosDeSomSwing)]:Play() end
end

local function tocarSomHit()
	if #objetosDeSomHit > 0 then objetosDeSomHit[math.random(1, #objetosDeSomHit)]:Play() end
end

-- === LINHAS INTELIGENTES & DASH ===
if workspace:FindFirstChild("VisualCombate") then workspace.VisualCombate:Destroy() end
local pastaVisual = Instance.new("Folder", workspace); pastaVisual.Name = "VisualCombate"

local function executarLinhasInteligentes()
	local centroChar = rootPart.CFrame
	local espacamento = LARGURA_LEQUE / (QUANTIDADE_LINHAS - 1)
	local inicioEsquerda = -LARGURA_LEQUE / 2

	local params = RaycastParams.new()
	params.FilterDescendantsInstances = {character, pastaVisual}
	params.FilterType = Enum.RaycastFilterType.Exclude

	local encontrouInimigo = false

	for i = 0, QUANTIDADE_LINHAS - 1 do
		local offsetX = inicioEsquerda + (espacamento * i)
		local origem = (centroChar * CFrame.new(offsetX, 0, 0)).Position
		local direcao = centroChar.LookVector * ALCANCE_VISUAL
		local resultado = workspace:Raycast(origem, direcao, params)

		local cor = Color3.fromRGB(255, 0, 0)
		local distanciaDesenho = ALCANCE_VISUAL

		if resultado then
			distanciaDesenho = resultado.Distance
			if resultado.Instance.Parent:FindFirstChild("Humanoid") then
				cor = Color3.fromRGB(0, 255, 0)
				encontrouInimigo = true
			end
		end

		local visual = Instance.new("Part")
		visual.Size = Vector3.new(0.05, 0.05, distanciaDesenho)
		visual.Anchored, visual.CanCollide, visual.Material = true, false, Enum.Material.Neon
		visual.Color = cor; visual.Transparency = 0.8
		visual.CFrame = CFrame.new(origem, origem + direcao.Unit * distanciaDesenho) * CFrame.new(0, 0, -distanciaDesenho / 2)
		visual.Parent = pastaVisual
		Debris:AddItem(visual, TEMPO_VISUAL)
	end

	if not encontrouInimigo then
		local empurrao = Instance.new("BodyVelocity")
		empurrao.Velocity = rootPart.CFrame.LookVector * FORCA_IMPULSO
		empurrao.MaxForce = Vector3.new(100000, 0, 100000)
		empurrao.Parent = rootPart
		Debris:AddItem(empurrao, 0.2)
	end
end

-- === DETECÇÃO DE HIT PRECISA ===
local function detectarHitSomPreciso(lado)
	local nomeBraco = (lado == "Esquerda") and "Left Arm" or "Right Arm"
	local mao = character:FindFirstChild(nomeBraco) or character:FindFirstChild(lado == "Esquerda" and "LeftHand" or "RightHand")

	if not mao then return end

	local tempoInicio = os.clock()
	local conexao
	local jaTocouSom = false

	local ultimasPosicoes = {}
	for i, offset in ipairs(PONTOS_DE_RASTREIO) do
		ultimasPosicoes[i] = (mao.CFrame * offset).Position
	end

	conexao = RunService.RenderStepped:Connect(function()
		if (os.clock() - tempoInicio) > DURACAO_HITBOX or jaTocouSom then
			conexao:Disconnect()
			return
		end

		for i, offset in ipairs(PONTOS_DE_RASTREIO) do
			local posicaoAtual = (mao.CFrame * offset).Position
			local ultimaPosicao = ultimasPosicoes[i]
			local direcaoRaio = posicaoAtual - ultimaPosicao
			local distancia = direcaoRaio.Magnitude

			if distancia > 0.01 then
				local params = RaycastParams.new()
				params.FilterDescendantsInstances = {character} 
				params.FilterType = Enum.RaycastFilterType.Exclude

				local resultado = workspace:Raycast(ultimaPosicao, direcaoRaio, params)

				if resultado then
					local hitModel = resultado.Instance.Parent
					if hitModel:FindFirstChild("Humanoid") then
						tocarSomHit() 
						jaTocouSom = true
						conexao:Disconnect()
						return
					end
				end
			end
			ultimasPosicoes[i] = posicaoAtual
		end
	end)
end

-- === TRAIL ===
local function instalarTrail(char)
	local bracos = {
		char:FindFirstChild("Right Arm") or char:FindFirstChild("RightHand"),
		char:FindFirstChild("Left Arm") or char:FindFirstChild("LeftHand")
	}
	for _, braco in pairs(bracos) do
		if braco and not braco:FindFirstChild("RastroInstalado") then
			local rastroPart = trailTemplate:Clone()
			rastroPart.Name = "RastroInstalado"
			rastroPart.CFrame = braco.CFrame
			rastroPart.Parent = braco
			rastroPart.Anchored = false 
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = braco; weld.Part1 = rastroPart; weld.Parent = rastroPart
			rastroPart.Transparency = 1; rastroPart.CanCollide = false; rastroPart.Massless = true
			for _, filho in pairs(rastroPart:GetChildren()) do
				if filho:IsA("Trail") then filho.Enabled = false end
			end
		end
	end
end

local function toggleTrail(lado, ligar)
	local nomeBraco = (lado == "Esquerda") and "Left Arm" or "Right Arm"
	local braco = character:FindFirstChild(nomeBraco) or character:FindFirstChild(nomeBraco == "Left Arm" and "LeftHand" or "RightHand")
	if braco then
		local rastroPart = braco:FindFirstChild("RastroInstalado")
		if rastroPart then
			for _, filho in pairs(rastroPart:GetChildren()) do
				if filho:IsA("Trail") then filho.Enabled = ligar end
			end
		end
	end
end

-- === CARREGAR ANIMAÇÕES ===
local function carregarAnimacoes()
	for direcao, id in pairs(LISTA_ANIMS.Idle) do
		local anim = Instance.new("Animation"); anim.AnimationId = id
		tracksIdle[direcao] = animator:LoadAnimation(anim); tracksIdle[direcao].Looped = true; tracksIdle[direcao].Priority = Enum.AnimationPriority.Movement
	end
	for direcao, id in pairs(LISTA_ANIMS.AtaqueForte) do
		local anim = Instance.new("Animation"); anim.AnimationId = id
		tracksForte[direcao] = animator:LoadAnimation(anim); tracksForte[direcao].Priority = Enum.AnimationPriority.Action
	end
	for direcao, id in pairs(LISTA_ANIMS.Jab) do
		local anim = Instance.new("Animation"); anim.AnimationId = id
		tracksJab[direcao] = animator:LoadAnimation(anim); tracksJab[direcao].Priority = Enum.AnimationPriority.Action
	end
end

-- === LOOP PRINCIPAL (POSTURA + GUARDA) ===
RunService.RenderStepped:Connect(function()
	local novaPosturaRaw = nil
	local mouseTravado = UserInputService.MouseBehavior == Enum.MouseBehavior.LockCenter

	if mouseTravado then
		local delta = UserInputService:GetMouseDelta()
		mouseVirtual = mouseVirtual + (delta * SENSIBILIDADE)
		if mouseVirtual.Magnitude > RAIO_VIRTUAL then mouseVirtual = mouseVirtual.Unit * RAIO_VIRTUAL end
		novaPosturaRaw = CombateMath.CalcularPostura(mouseVirtual, Vector2.new(0,0))
	else
		local camera = workspace.CurrentCamera
		local centro = camera.ViewportSize / 2
		local mousePos = UserInputService:GetMouseLocation()
		mouseVirtual = mousePos - centro
		novaPosturaRaw = CombateMath.CalcularPostura(mousePos, centro)
	end

	if novaPosturaRaw then posturaAtual = novaPosturaRaw end

	-- TRADUÇÃO PRA ANIM DE GUARDA (IDLE)
	local posturaParaAnim = "Cima"
	if posturaAtual == "Ponta1" or posturaAtual == "Bolinha" then
		posturaParaAnim = "Cima"
	elseif posturaAtual == "Ponta2" or posturaAtual == "Ponta5" then
		posturaParaAnim = "Esquerda"
	elseif posturaAtual == "Ponta3" or posturaAtual == "Ponta4" then
		posturaParaAnim = "Direita"
	end

	if posturaParaAnim ~= ultimaAnimTocada then
		if ultimaAnimTocada and tracksIdle[ultimaAnimTocada] then tracksIdle[ultimaAnimTocada]:Stop(0.2) end
		if tracksIdle[posturaParaAnim] then tracksIdle[posturaParaAnim]:Play(0.2) end
		ultimaAnimTocada = posturaParaAnim
	end
end)

UserInputService.InputBegan:Connect(function(input, gp)
	if gp then return end

	-- TRADUTOR: 5 PONTAS -> 3 LADOS
	local ladoSoco = "Direita"
	local animacaoAlvo = "Direita"

	if posturaAtual == "Ponta1" then
		ladoSoco = "Direita"; animacaoAlvo = "Cima"
	elseif posturaAtual == "Ponta2" then 
		ladoSoco = "Esquerda"; animacaoAlvo = "Esquerda"
	elseif posturaAtual == "Ponta5" then 
		ladoSoco = "Esquerda"; animacaoAlvo = "Esquerda"
	elseif posturaAtual == "Ponta3" then 
		ladoSoco = "Direita"; animacaoAlvo = "Direita"
	elseif posturaAtual == "Ponta4" then 
		ladoSoco = "Direita"; animacaoAlvo = "Direita"
	elseif posturaAtual == "Bolinha" then 
		ladoSoco = "Direita"; animacaoAlvo = "Cima"
	end

	-- ATAQUE FORTE (MB1) - MAIOR COOLDOWN
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		if os.clock() - ultimoAtaque < COOLDOWN_FORTE then return end -- ⛔ Checa Cooldown
		ultimoAtaque = os.clock() -- ✅ Reseta timer

		tocarSomSwing() 
		executarLinhasInteligentes() 
		toggleTrail(ladoSoco, true)
		detectarHitSomPreciso(ladoSoco) 
		task.delay(0.4, function() toggleTrail(ladoSoco, false) end)

		local anim = tracksForte[animacaoAlvo]
		if anim then anim:AdjustSpeed(1.0); anim:Play(); eventoCombate:FireServer("Forte", animacaoAlvo) end
	end

	-- JAB RÁPIDO (MB2) - MENOR COOLDOWN
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		if os.clock() - ultimoAtaque < COOLDOWN_JAB then return end -- ⛔ Checa Cooldown
		ultimoAtaque = os.clock() -- ✅ Reseta timer

		tocarSomSwing()
		executarLinhasInteligentes()
		toggleTrail(ladoSoco, true)
		detectarHitSomPreciso(ladoSoco)
		task.delay(0.3, function() toggleTrail(ladoSoco, false) end)

		local anim = tracksJab[animacaoAlvo]
		if anim then anim:AdjustSpeed(1.3); anim:Play(); eventoCombate:FireServer("Rapido", animacaoAlvo) end
	end
end)

carregarAnimacoes()
prepararSons() 
instalarTrail(character) 

player.CharacterAdded:Connect(function(newChar)
	character = newChar
	humanoid = newChar:WaitForChild("Humanoid")
	rootPart = newChar:WaitForChild("HumanoidRootPart")
	animator = humanoid:WaitForChild("Animator")
	tracksIdle, tracksForte, tracksJab = {}, {}, {}
	ultimaAnimTocada = nil
	carregarAnimacoes()
	prepararSons() 
	task.wait(0.5) 
	instalarTrail(character)
end)