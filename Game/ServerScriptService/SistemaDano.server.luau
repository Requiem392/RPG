local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")
local eventoCombate = ReplicatedStorage:WaitForChild("EventoCombate")
local eventoVFX = ReplicatedStorage:WaitForChild("EventoVFX")

-- === CONFIGURAÇÕES ===
local DANO_FORTE = 25
local DANO_RAPIDO = 10
local DURACAO_HITBOX = 0.4 

local MOSTRAR_RASTRO = true -- Deixe true pra ver as 5 linhas (estilo sua imagem)

-- === CALIBRAGEM R6 (A Mágica da Precisão) ===
-- O braço R6 tem tamanho (1, 2, 1). O Y é a altura.
-- -1 no Y significa "Bem na ponta da mão de baixo".
-- O X varia de -0.5 a 0.5 (largura do braço).
local PONTOS_DE_RASTREIO = {
	CFrame.new(0, -1, 0),     -- 1. Centro da mão (Ponta)
	CFrame.new(0.4, -1, 0),   -- 2. Quina Direita
	CFrame.new(-0.4, -1, 0),  -- 3. Quina Esquerda
	CFrame.new(0.2, -1, 0),   -- 4. Meio Direita
	CFrame.new(-0.2, -1, 0),  -- 5. Meio Esquerda
	CFrame.new(0, -0.5, 0),   -- 6. Meio do Antebraço (pra quem tentar entrar na guarda)
}

local cooldowns = {}

eventoCombate.OnServerEvent:Connect(function(player, tipoAtaque, direcao)
	-- Cooldown simples
	if cooldowns[player.UserId] and (os.clock() - cooldowns[player.UserId]) < 0.3 then return end
	cooldowns[player.UserId] = os.clock()

	local char = player.Character
	if not char then return end

	-- Detecção R6 (Procura Braço Direito ou Esquerdo)
	local mao = nil
	if direcao == "Esquerda" then
		mao = char:FindFirstChild("Left Arm") or char:FindFirstChild("LeftHand")
	else
		mao = char:FindFirstChild("Right Arm") or char:FindFirstChild("RightHand")
	end

	if not mao then return end -- Se não achou, aborta

	-- === INÍCIO DO ATAQUE ===
	local tempoInicio = os.clock()
	local inimigosAtingidos = {} -- Lista negra pra não dar hit duplo

	-- Guarda a posição inicial de CADA ponto de rastreio
	local ultimasPosicoes = {}
	for i, offset in ipairs(PONTOS_DE_RASTREIO) do
		ultimasPosicoes[i] = (mao.CFrame * offset).Position
	end

	local conexao
	conexao = RunService.Heartbeat:Connect(function()
		-- Timer pra parar o script
		if (os.clock() - tempoInicio) > DURACAO_HITBOX then
			conexao:Disconnect()
			return
		end

		-- Loopa por TODOS os 6 pontos do braço
		for i, offset in ipairs(PONTOS_DE_RASTREIO) do
			local posicaoAtual = (mao.CFrame * offset).Position
			local ultimaPosicao = ultimasPosicoes[i]

			local direcaoRaio = posicaoAtual - ultimaPosicao
			local distancia = direcaoRaio.Magnitude

			-- Só processa se houve movimento nesse ponto
			if distancia > 0.05 then
				local params = RaycastParams.new()
				params.FilterDescendantsInstances = {char}
				params.FilterType = Enum.RaycastFilterType.Exclude

				-- Dispara o raio deste ponto específico
				local resultado = workspace:Raycast(ultimaPosicao, direcaoRaio, params)

				-- === VISUAL (RASTRO DE 5 LINHAS) ===
				if MOSTRAR_RASTRO then
					local rastro = Instance.new("Part")
					rastro.Anchored = true
					rastro.CanCollide = false
					rastro.Material = Enum.Material.Neon
					rastro.Color = Color3.fromRGB(255, 50, 50)
					rastro.Transparency = 0.4
					rastro.Size = Vector3.new(0.08, 0.08, distancia) -- Linhas mais finas ficam mais bonitas
					rastro.CFrame = CFrame.lookAt(ultimaPosicao, posicaoAtual) * CFrame.new(0, 0, -distancia/2)
					rastro.Parent = workspace
					Debris:AddItem(rastro, 0.3)
				end

				-- === DANO ===
				if resultado then
					local hitChar = resultado.Instance.Parent
					local hum = hitChar:FindFirstChild("Humanoid")

					if hum and hum.Health > 0 and not inimigosAtingidos[hitChar] then
						inimigosAtingidos[hitChar] = true 

						local dano = (tipoAtaque == "Forte") and DANO_FORTE or DANO_RAPIDO
						hum:TakeDamage(dano)

						-- === ADICIONE ISSO AQUI ===
						-- Avisa TODOS os clientes para desenharem sangue na posição do impacto
						-- Passamos a posição exata e a "normal" (o ângulo da superfície que bateu)
						eventoVFX:FireAllClients("Sangue", resultado.Position, resultado.Normal)
						-- ==========================

						-- Highlight (Se quiser manter ou tirar depois)
						local h = Instance.new("Highlight", hitChar)
						h.FillColor = Color3.fromRGB(255, 0, 0)
						h.OutlineTransparency = 1
						Debris:AddItem(h, 0.2)
					end
				end
			end

			-- Atualiza a posição para o próximo frame
			ultimasPosicoes[i] = posicaoAtual
		end
	end)
end)